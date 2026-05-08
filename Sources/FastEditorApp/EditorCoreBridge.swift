import Foundation
import SwiftUI

@MainActor
final class EditorCoreBridge: ObservableObject {
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var fileURL: URL?
    @Published private(set) var statusText = "Open a file to start editing through the Rust core."
    @Published private(set) var isDirty = false
    @Published private(set) var focusRevision = 0
    @Published private(set) var renderSnapshot = EditorRenderSnapshot.empty
    @Published private(set) var markdownPreviewHTML = ""
    @Published private(set) var projectTaskSummary = ProjectTaskSummary.empty
    @Published private(set) var selectedTask: ProjectTaskDefinition?
    @Published private(set) var selectedTaskPlan: TaskExecutionPlan?
    @Published private(set) var taskOutput = ""
    @Published private(set) var taskDiagnostics: [TaskDiagnostic] = []
    @Published private(set) var taskStatusText = "No task selected"
    @Published private(set) var isTaskRunning = false
    @Published var text = ""
    @Published var errorMessage = ""

    private let session = EditorCoreSession()
    private var isSyncingFromCore = false
    private var runningTaskProcess: Process?
    private var taskStdout = ""
    private var taskStderr = ""

    private var bufferID: UInt64 {
        session.currentBufferID
    }

    var hasOpenBuffer: Bool {
        session.hasOpenBuffer
    }

    var canSave: Bool {
        hasOpenBuffer && isDirty
    }

    var isUntitled: Bool {
        hasOpenBuffer && fileURL == nil
    }

    var textBinding: Binding<String> {
        Binding(
            get: { self.text },
            set: { newValue in
                self.text = newValue
                self.replaceText(newValue)
            }
        )
    }

    var errorPresented: Binding<Bool> {
        Binding(
            get: { !self.errorMessage.isEmpty },
            set: { presented in
                if !presented {
                    self.errorMessage = ""
                }
            }
        )
    }

    func open(url: URL) {
        let openedID = url.path.withCString { path in
            feOpenFile(path)
        }

        guard openedID != 0 else {
            reportLastError(prefix: "Open failed")
            return
        }

        session.replace(with: openedID)
        fileURL = url
        syncTextFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        focusRevision += 1
        statusText = "Opened \(url.path)"
    }

    func openFolder(url: URL) {
        workspaceURL = url
        syncProjectTaskSummary(for: url)
        clearSelectedTask()
        statusText = "Opened folder \(url.path)"
    }

    func newFile() {
        let newID = feNewFile()

        guard newID != 0 else {
            reportLastError(prefix: "New file failed")
            return
        }

        session.replace(with: newID)
        fileURL = nil
        syncTextFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        focusRevision += 1
        statusText = "New untitled file"
    }

    func save() -> Bool {
        guard hasOpenBuffer else {
            return false
        }

        if isUntitled {
            return false
        }

        replaceText(text)
        guard feSaveFile(bufferID) != 0 else {
            reportLastError(prefix: "Save failed")
            return false
        }

        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        statusText = "Saved \(displayPath)"
        return true
    }

    func saveAs(url: URL) -> Bool {
        guard hasOpenBuffer else {
            return false
        }

        replaceText(text)
        let result = url.path.withCString { path in
            feSaveFileAs(bufferID, path)
        }

        guard result != 0 else {
            reportLastError(prefix: "Save failed")
            return false
        }

        fileURL = url
        syncPathFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        statusText = "Saved \(displayPath)"
        return true
    }

    func replaceText(_ newText: String, cursorUTF8Offset: Int) {
        guard hasOpenBuffer, !isSyncingFromCore else {
            return
        }

        text = newText
        let bytes = Array(newText.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            feReplaceTextWithCursor(bufferID, buffer.baseAddress, buffer.count, cursorUTF8Offset)
        }

        if result == 0 {
            reportLastError(prefix: "Edit failed")
        } else {
            syncRenderSnapshot()
            syncMarkdownPreviewHTML()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        }
    }

    func setCursorUTF8Offset(_ cursorUTF8Offset: Int) {
        guard hasOpenBuffer else {
            return
        }

        guard feSetCursorOffset(bufferID, cursorUTF8Offset) != 0 else {
            reportLastError(prefix: "Cursor update failed")
            return
        }

        syncRenderSnapshot()
    }

    func undo() {
        applyHistoryAction(feUndo, emptyMessage: "Nothing to undo")
    }

    func redo() {
        applyHistoryAction(feRedo, emptyMessage: "Nothing to redo")
    }

    func applyAgentReplacement(_ replacement: String) {
        guard hasOpenBuffer else {
            return
        }

        text = replacement
        replaceText(replacement)
        focusRevision += 1
    }

    func selectTask(_ task: ProjectTaskDefinition) {
        guard let workspaceURL else {
            return
        }

        let value = workspaceURL.path.withCString { path in
            task.providerID.rawValue.withCString { providerID in
                task.id.withCString { taskID in
                    feGetProjectTaskExecutionPlan(path, providerID, taskID)
                }
            }
        }
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            selectedTask = nil
            selectedTaskPlan = nil
            taskStatusText = "Task preview failed"
            reportLastError(prefix: "Task preview failed")
            return
        }

        let data = Data(bytes: pointer, count: value.len)
        do {
            selectedTask = task
            selectedTaskPlan = try JSONDecoder().decode(TaskExecutionPlan.self, from: data)
            taskOutput = ""
            taskDiagnostics = []
            taskStdout = ""
            taskStderr = ""
            taskStatusText = "Ready to run \(task.label)"
        } catch {
            selectedTask = nil
            selectedTaskPlan = nil
            taskStatusText = "Task preview failed"
            errorMessage = "Task preview failed: \(error.localizedDescription)"
        }
    }

    func runSelectedTask() {
        guard let plan = selectedTaskPlan, !isTaskRunning else {
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.currentDirectoryURL = URL(fileURLWithPath: plan.cwd)

        if plan.program.contains("/") {
            process.executableURL = URL(fileURLWithPath: plan.program, relativeTo: process.currentDirectoryURL)
            process.arguments = plan.args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [plan.program] + plan.args
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment

        for entry in plan.environment where entry.count == 2 {
            process.environment?[entry[0]] = entry[1]
        }

        taskOutput = "$ \(plan.commandDisplay)\n"
        taskDiagnostics = []
        taskStdout = ""
        taskStderr = ""
        taskStatusText = "Running \(selectedTask?.label ?? plan.taskID)"
        isTaskRunning = true
        runningTaskProcess = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                self?.appendTaskOutput(data, stream: .standardOutput)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                self?.appendTaskOutput(data, stream: .standardError)
            }
        }
        process.terminationHandler = { [weak self, weak outputPipe, weak errorPipe] process in
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            errorPipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.isTaskRunning = false
                self?.runningTaskProcess = nil
                self?.taskStatusText = "Exited with \(process.terminationStatus)"
                self?.taskOutput += "\n[exited \(process.terminationStatus)]\n"
                self?.syncTaskDiagnostics(exitCode: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            isTaskRunning = false
            runningTaskProcess = nil
            taskStatusText = "Task failed to start"
            taskOutput += "Failed to start: \(error.localizedDescription)\n"
            taskDiagnostics = []
        }
    }

    func stopRunningTask() {
        runningTaskProcess?.terminate()
        taskStatusText = "Stopping task"
    }

    private func syncTextFromCore() {
        guard hasOpenBuffer else {
            return
        }

        let value = feGetText(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Read failed")
            return
        }

        isSyncingFromCore = true
        text = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        isSyncingFromCore = false
    }

    private func syncRenderSnapshot() {
        guard hasOpenBuffer else {
            renderSnapshot = .empty
            return
        }

        let value = feGetRenderSnapshot(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Render snapshot failed")
            return
        }

        let data = Data(bytes: pointer, count: value.len)

        do {
            renderSnapshot = try JSONDecoder().decode(EditorRenderSnapshot.self, from: data)
        } catch {
            errorMessage = "Render snapshot failed: \(error.localizedDescription)"
        }
    }

    private func syncMarkdownPreviewHTML() {
        guard hasOpenBuffer else {
            markdownPreviewHTML = ""
            return
        }

        let value = feGetMarkdownPreviewHTML(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            reportLastError(prefix: "Markdown preview failed")
            return
        }

        markdownPreviewHTML = String(
            decoding: UnsafeBufferPointer(start: pointer, count: value.len),
            as: UTF8.self
        )
    }

    private func syncPathFromCore() {
        guard hasOpenBuffer else {
            fileURL = nil
            return
        }

        let value = feGetPath(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr, value.len > 0 else {
            fileURL = nil
            return
        }

        let path = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        fileURL = URL(fileURLWithPath: path)
    }

    private func syncProjectTaskSummary(for url: URL) {
        let value = url.path.withCString { path in
            feInspectProjectTasks(path)
        }
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            projectTaskSummary = .empty
            reportLastError(prefix: "Task inspection failed")
            return
        }

        let data = Data(bytes: pointer, count: value.len)
        do {
            projectTaskSummary = try JSONDecoder().decode(ProjectTaskSummary.self, from: data)
        } catch {
            projectTaskSummary = .empty
            errorMessage = "Task inspection failed: \(error.localizedDescription)"
        }
    }

    private func clearSelectedTask() {
        selectedTask = nil
        selectedTaskPlan = nil
        taskOutput = ""
        taskDiagnostics = []
        taskStatusText = "No task selected"
        isTaskRunning = false
        runningTaskProcess = nil
        taskStdout = ""
        taskStderr = ""
    }

    private func appendTaskOutput(_ data: Data, stream: TaskOutputStream) {
        guard !data.isEmpty else {
            return
        }

        let text = String(decoding: data, as: UTF8.self)
        switch stream {
        case .standardOutput:
            taskStdout += text
        case .standardError:
            taskStderr += text
        }
        taskOutput += text
    }

    private func syncTaskDiagnostics(exitCode: Int32) {
        guard let providerID = selectedTask?.providerID else {
            taskDiagnostics = []
            return
        }

        let stdoutBytes = Array(taskStdout.utf8)
        let stderrBytes = Array(taskStderr.utf8)
        let value = providerID.rawValue.withCString { providerID in
            stdoutBytes.withUnsafeBufferPointer { stdout in
                stderrBytes.withUnsafeBufferPointer { stderr in
                    feParseTaskDiagnostics(
                        providerID,
                        stdout.baseAddress,
                        stdout.count,
                        stderr.baseAddress,
                        stderr.count,
                        exitCode
                    )
                }
            }
        }
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            taskDiagnostics = []
            reportLastError(prefix: "Diagnostic parsing failed")
            return
        }

        let data = Data(bytes: pointer, count: value.len)
        do {
            taskDiagnostics = try JSONDecoder().decode([TaskDiagnostic].self, from: data)
        } catch {
            taskDiagnostics = []
            errorMessage = "Diagnostic parsing failed: \(error.localizedDescription)"
        }
    }

    private func replaceText(_ newText: String) {
        guard hasOpenBuffer, !isSyncingFromCore else {
            return
        }

        let bytes = Array(newText.utf8)
        let result = bytes.withUnsafeBufferPointer { buffer in
            feReplaceText(bufferID, buffer.baseAddress, buffer.count)
        }

        if result == 0 {
            reportLastError(prefix: "Edit failed")
        } else {
            syncRenderSnapshot()
            syncMarkdownPreviewHTML()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        }
    }

    private func applyHistoryAction(_ action: (UInt64) -> Int32, emptyMessage: String) {
        guard hasOpenBuffer else {
            return
        }

        let result = action(bufferID)
        if result == 1 {
            syncTextFromCore()
            syncRenderSnapshot()
            syncMarkdownPreviewHTML()
            syncDirtyState()
            statusText = isDirty ? "Unsaved changes in \(displayPath)" : "Saved \(displayPath)"
        } else if result == 0 {
            statusText = emptyMessage
        } else {
            reportLastError(prefix: "Edit history failed")
        }
    }

    private func syncDirtyState() {
        guard hasOpenBuffer else {
            isDirty = false
            return
        }

        let result = feIsDirty(bufferID)
        if result == -1 {
            reportLastError(prefix: "State read failed")
        } else {
            isDirty = result == 1
        }
    }

    private func reportLastError(prefix: String) {
        let value = feLastError()
        defer {
            feFreeString(value)
        }

        let detail: String
        if let pointer = value.ptr, value.len > 0 {
            detail = String(decoding: UnsafeBufferPointer(start: pointer, count: value.len), as: UTF8.self)
        } else {
            detail = "Unknown error"
        }

        errorMessage = "\(prefix): \(detail)"
    }

    private var displayPath: String {
        fileURL?.path ?? "Untitled"
    }
}

private enum TaskOutputStream {
    case standardOutput
    case standardError
}
