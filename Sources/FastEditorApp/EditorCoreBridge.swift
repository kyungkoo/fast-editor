import FastEditorModels
import Foundation
import SwiftUI
import FastEditorTextEditing

@MainActor
final class EditorCoreBridge: ObservableObject {
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var fileURL: URL?
    @Published private(set) var openBuffers: [EditorOpenBuffer] = []
    @Published private(set) var workspaceFileTree: [WorkspaceFileNode] = []
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
    @Published private(set) var languageServerProviders: [LanguageServerProvider] = []
    @Published private(set) var selectedLanguageServerID: LanguageServerID?
    @Published private(set) var languageServerStatusText = "No language server detected"
    @Published private(set) var isLanguageServerRunning = false
    @Published private(set) var languageServerDiagnostics: [LanguageServerDiagnostic] = []
    @Published private(set) var selectedTextRange: Range<Int>?
    @Published private(set) var findQuery = ""
    @Published private(set) var findMatches: [TextSearchMatch] = []
    @Published private(set) var activeFindMatchIndex: Int?
    @Published private(set) var workspaceSearchQuery = ""
    @Published private(set) var workspaceSearchResults: [WorkspaceSearchResult] = []
    @Published private(set) var isWorkspaceSearchRunning = false
    @Published private(set) var activeWorkspaceSearchResultIndex: Int?
    @Published private(set) var quickOpenQuery = ""
    @Published private(set) var quickOpenResults: [QuickOpenResult] = []
    @Published private(set) var referenceQuery = ""
    @Published private(set) var referenceResults: [WorkspaceReferenceResult] = []
    @Published private(set) var isReferenceSearchRunning = false
    @Published private(set) var navigationHistory = EditorNavigationHistory()
    @Published private(set) var recentFileURLs: [URL] = []
    @Published private(set) var scrollPositionRevision = 0
    @Published var text = ""
    @Published var errorMessage = ""

    private let session = EditorCoreSession()
    private var isSyncingFromCore = false
    private var runningTaskProcess: Process?
    private var runningLanguageServerProcess: Process?
    private var languageServerInput: FileHandle?
    private var languageServerFramer = LanguageServerMessageFramer()
    private var documentVersions: [UInt64: Int] = [:]
    private var taskStdout = ""
    private var taskStderr = ""
    private var selectedTextRanges: [UInt64: Range<Int>] = [:]
    private var scrollPositions: [UInt64: EditorScrollPosition] = [:]
    private var quickOpenCandidates: [QuickOpenCandidate] = []
    private var workspaceSearchTask: Task<Void, Never>?
    private var referenceSearchTask: Task<Void, Never>?
    private var sessionPersistenceTask: Task<Void, Never>?
    private let sessionRestorationStore = EditorSessionRestorationStore()
    private var isRestoringSession = false

    init() {
        refreshLanguageServers()
        restoreEditorSession()
    }

    deinit {
        workspaceSearchTask?.cancel()
        referenceSearchTask?.cancel()
        sessionPersistenceTask?.cancel()
    }

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

    var currentScrollPosition: EditorScrollPosition {
        scrollPositions[bufferID] ?? .zero
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

    var agentContext: AgentContext {
        AgentContext.currentFile(fileURL: fileURL, text: text, selectedRange: selectedTextRange)
    }

    var findStatusText: String {
        guard !findQuery.isEmpty else {
            return "Find"
        }

        guard let activeFindMatchIndex else {
            return "No matches"
        }

        return "\(activeFindMatchIndex + 1) of \(findMatches.count)"
    }

    var workspaceSearchStatusText: String {
        guard !workspaceSearchQuery.isEmpty else {
            return "Search"
        }

        if isWorkspaceSearchRunning {
            return "Searching..."
        }

        if workspaceSearchResults.isEmpty {
            return "No matches"
        }

        return "\(workspaceSearchResults.count) results"
    }

    var quickOpenStatusText: String {
        guard workspaceURL != nil else {
            return "Open a folder first"
        }

        guard !quickOpenCandidates.isEmpty else {
            return "No project files"
        }

        return quickOpenResults.isEmpty ? "No matches" : "\(quickOpenResults.count) files"
    }

    var referenceStatusText: String {
        if isReferenceSearchRunning {
            return "Searching..."
        }

        guard !referenceQuery.isEmpty else {
            return "No symbol selected"
        }

        return referenceResults.isEmpty ? "No references" : "\(referenceResults.count) references"
    }

    var diagnosticLineIndexesForCurrentFile: Set<Int> {
        guard let fileURL else {
            return []
        }

        let taskLines = taskDiagnostics.compactMap { diagnostic -> Int? in
            guard diagnostic.resolvedFileURL(workspaceURL: workspaceURL)?.standardizedFileURL == fileURL.standardizedFileURL else {
                return nil
            }

            return diagnostic.targetLineIndex
        }
        let languageServerLines = languageServerDiagnostics.compactMap { diagnostic -> Int? in
            guard diagnostic.fileURL.standardizedFileURL == fileURL.standardizedFileURL else {
                return nil
            }

            return diagnostic.line
        }

        return Set(taskLines + languageServerLines)
    }

    var selectedLanguageServerProvider: LanguageServerProvider? {
        guard let selectedLanguageServerID else {
            return nil
        }

        return languageServerProviders.first { $0.id == selectedLanguageServerID }
    }

    var availableLanguageServerProviders: [LanguageServerProvider] {
        languageServerProviders.filter(\.available)
    }

    var languageServerDiagnosticsForCurrentFile: [LanguageServerDiagnostic] {
        guard let fileURL else {
            return []
        }

        return languageServerDiagnostics.filter {
            $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL
        }
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

    @discardableResult
    func open(url: URL) -> Bool {
        if let buffer = session.buffer(forFileURL: url) {
            return switchToBuffer(id: buffer.id)
        }

        captureCurrentViewState()
        let openedID = url.path.withCString { path in
            feOpenFile(path)
        }

        guard openedID != 0 else {
            reportLastError(prefix: "Open failed")
            return false
        }

        fileURL = url.standardizedFileURL
        session.open(buffer: EditorOpenBuffer(id: openedID, fileURL: fileURL, isDirty: false))
        documentVersions[openedID] = 1
        selectedTextRange = nil
        syncCurrentBufferState()
        sendCurrentDocumentOpenToLanguageServer()
        recordRecentFile(url)
        navigationHistory.replaceCurrent(currentNavigationLocation())
        focusRevision += 1
        statusText = "Opened \(url.path)"
        scheduleSessionStatePersistence()
        return true
    }

    func openFolder(url: URL) {
        workspaceURL = url
        workspaceFileTree = WorkspaceFileNode.roots(in: url)
        refreshQuickOpenCandidates()
        syncProjectTaskSummary(for: url)
        syncWorkspaceSearch()
        clearSelectedTask()
        statusText = "Opened folder \(url.path)"
        scheduleSessionStatePersistence()
    }

    func newFile() {
        let newID = feNewFile()

        guard newID != 0 else {
            reportLastError(prefix: "New file failed")
            return
        }

        fileURL = nil
        session.open(buffer: EditorOpenBuffer(id: newID, fileURL: nil, isDirty: false))
        documentVersions[newID] = 1
        selectedTextRange = nil
        syncCurrentBufferState()
        navigationHistory.replaceCurrent(nil)
        focusRevision += 1
        statusText = "New untitled file"
        scheduleSessionStatePersistence()
    }

    @discardableResult
    func switchToBuffer(id bufferID: UInt64) -> Bool {
        captureCurrentViewState()
        guard session.switchToBuffer(id: bufferID) else {
            return false
        }

        syncPathFromCore()
        syncCurrentBufferState()
        selectedTextRange = selectedTextRanges[self.bufferID]
        sendCurrentDocumentOpenToLanguageServer()
        if let fileURL {
            recordRecentFile(fileURL)
        }
        navigationHistory.replaceCurrent(currentNavigationLocation())
        focusRevision += 1
        statusText = "Switched to \(displayPath)"
        scheduleSessionStatePersistence()
        return true
    }

    func closeBuffer(id bufferID: UInt64, force: Bool = false) {
        guard let buffer = session.buffer(for: bufferID) else {
            return
        }

        if buffer.isDirty, !force {
            statusText = "Save or discard changes before closing \(buffer.title)"
            return
        }

        let wasCurrentBuffer = bufferID == self.bufferID
        if wasCurrentBuffer {
            captureCurrentViewState()
        }
        sendDocumentCloseToLanguageServer(fileURL: buffer.fileURL)
        session.closeBuffer(id: bufferID)
        documentVersions[bufferID] = nil
        selectedTextRanges[bufferID] = nil
        scrollPositions[bufferID] = nil
        syncOpenBuffers()

        if session.hasOpenBuffer {
            if wasCurrentBuffer {
                syncPathFromCore()
                syncCurrentBufferState()
                selectedTextRange = selectedTextRanges[self.bufferID]
                navigationHistory.replaceCurrent(currentNavigationLocation())
                focusRevision += 1
            }
        } else {
            clearCurrentBufferState()
            navigationHistory.replaceCurrent(nil)
            statusText = "No file open"
        }
        scheduleSessionStatePersistence()
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
        syncOpenBuffers()
        statusText = "Saved \(displayPath)"
        sendCurrentDocumentSaveToLanguageServer()
        if let fileURL {
            recordRecentFile(fileURL)
        }
        syncWorkspaceSearch()
        scheduleSessionStatePersistence()
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
        syncOpenBuffers()
        recordRecentFile(url)
        refreshQuickOpenCandidates()
        statusText = "Saved \(displayPath)"
        sendCurrentDocumentSaveToLanguageServer()
        syncWorkspaceSearch()
        scheduleSessionStatePersistence()
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
            syncFindMatches()
            syncOpenBuffers()
            sendCurrentDocumentChangeToLanguageServer()
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
        navigationHistory.replaceCurrent(currentNavigationLocation())
        scheduleSessionStatePersistence()
    }

    func setSelectionUTF8Range(_ range: Range<Int>?) {
        selectedTextRange = range
        if hasOpenBuffer {
            selectedTextRanges[bufferID] = range
        }
        scheduleSessionStatePersistence()
    }

    func setScrollPosition(_ position: EditorScrollPosition) {
        guard hasOpenBuffer else {
            return
        }

        scrollPositions[bufferID] = position
        scheduleSessionStatePersistence()
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
        selectedTextRange = nil
        focusRevision += 1
    }

    func applyAgentReplacement(_ proposedEdit: AgentProposedEdit) {
        guard hasOpenBuffer else {
            return
        }

        if let targetRange = proposedEdit.targetRange {
            let result = TextEditingPrimitives.replacingUTF8Range(
                targetRange,
                in: text,
                with: proposedEdit.replacementText
            )
            text = result.text
            replaceText(result.text, cursorUTF8Offset: result.cursorUTF8Offset)
        } else {
            text = proposedEdit.replacementText
            replaceText(proposedEdit.replacementText)
        }

        selectedTextRange = nil
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

    func refreshLanguageServers() {
        languageServerProviders = LanguageServerDetector.detect()
        if selectedLanguageServerID == nil || selectedLanguageServerProvider?.available != true {
            selectedLanguageServerID = availableLanguageServerProviders.first?.id
        }
        languageServerStatusText = availableLanguageServerProviders.isEmpty
            ? "No language server detected"
            : "Ready"
    }

    func selectLanguageServer(_ id: LanguageServerID?) {
        guard !isLanguageServerRunning else {
            return
        }

        selectedLanguageServerID = id
    }

    func startLanguageServer() {
        guard !isLanguageServerRunning,
              let provider = selectedLanguageServerProvider,
              let executablePath = provider.executablePath
        else {
            languageServerStatusText = "No language server selected"
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = provider.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment

        languageServerInput = inputPipe.fileHandleForWriting
        languageServerFramer = LanguageServerMessageFramer()
        languageServerStatusText = "Starting \(provider.displayName)"
        isLanguageServerRunning = true
        runningLanguageServerProcess = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                self?.appendLanguageServerOutput(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { @MainActor in
                self?.languageServerStatusText = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        process.terminationHandler = { [weak self, weak outputPipe, weak errorPipe] process in
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            errorPipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.isLanguageServerRunning = false
                self?.runningLanguageServerProcess = nil
                self?.languageServerInput = nil
                self?.languageServerStatusText = "Exited with \(process.terminationStatus)"
            }
        }

        do {
            try process.run()
            languageServerStatusText = "Running \(provider.displayName)"
            sendLanguageServerRequest(method: "initialize", id: 1, params: initializeParams())
            sendLanguageServerNotification(method: "initialized", params: [:])
            sendCurrentDocumentOpenToLanguageServer()
        } catch {
            isLanguageServerRunning = false
            runningLanguageServerProcess = nil
            languageServerInput = nil
            languageServerStatusText = "Failed to start \(provider.displayName)"
            errorMessage = "Language server failed: \(error.localizedDescription)"
        }
    }

    func stopLanguageServer() {
        guard isLanguageServerRunning else {
            return
        }

        sendLanguageServerRequest(method: "shutdown", id: 2, params: [:])
        sendLanguageServerNotification(method: "exit", params: [:])
        runningLanguageServerProcess?.terminate()
        languageServerStatusText = "Stopping language server"
    }

    func navigateToLanguageServerDiagnostic(_ diagnostic: LanguageServerDiagnostic) {
        guard open(url: diagnostic.fileURL) else {
            return
        }

        let cursorOffset = TextEditingPrimitives.utf8Offset(
            in: text,
            line: diagnostic.line,
            column: diagnostic.column
        )
        setCursorUTF8Offset(cursorOffset)
        focusRevision += 1
        statusText = "Opened \(diagnostic.locationDisplay)"
    }

    func applyLanguageServerMessage(_ data: Data) {
        let diagnostics = LanguageServerDiagnosticsParser.diagnostics(from: data)
        guard !diagnostics.isEmpty || isPublishDiagnosticsMessage(data) else {
            return
        }

        if let fileURL = diagnostics.first?.fileURL ?? publishDiagnosticsURL(data) {
            languageServerDiagnostics.removeAll {
                $0.fileURL.standardizedFileURL == fileURL.standardizedFileURL
            }
        }

        languageServerDiagnostics.append(contentsOf: diagnostics)
        languageServerStatusText = diagnostics.isEmpty
            ? "No diagnostics"
            : "\(diagnostics.count) diagnostics"
    }

    func navigateToDiagnostic(_ diagnostic: TaskDiagnostic) {
        guard let url = diagnostic.resolvedFileURL(workspaceURL: workspaceURL) else {
            errorMessage = "Diagnostic navigation failed: no file path for \(diagnostic.locationDisplay)"
            return
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            errorMessage = "Diagnostic navigation failed: cannot read \(url.path)"
            return
        }

        guard open(url: url) else {
            return
        }

        if let line = diagnostic.targetLineIndex {
            let column = diagnostic.targetColumnIndex ?? 0
            let cursorOffset = TextEditingPrimitives.utf8Offset(
                in: text,
                line: line,
                column: column
            )
            setCursorUTF8Offset(cursorOffset)
            focusRevision += 1
            statusText = "Opened \(url.path):\(line + 1):\(column + 1)"
        }
    }

    func updateFindQuery(_ query: String) {
        findQuery = query
        syncFindMatches()
    }

    func selectNextFindMatch() {
        guard !findMatches.isEmpty else {
            activeFindMatchIndex = nil
            return
        }

        let nextIndex = activeFindMatchIndex.map { ($0 + 1) % findMatches.count } ?? 0
        selectFindMatch(at: nextIndex)
    }

    func selectPreviousFindMatch() {
        guard !findMatches.isEmpty else {
            activeFindMatchIndex = nil
            return
        }

        let nextIndex = activeFindMatchIndex.map { ($0 - 1 + findMatches.count) % findMatches.count }
            ?? findMatches.count - 1
        selectFindMatch(at: nextIndex)
    }

    func selectFindMatch(at index: Int) {
        guard findMatches.indices.contains(index) else {
            return
        }

        recordNavigationBeforeJump()
        let match = findMatches[index]
        activeFindMatchIndex = index
        selectedTextRange = match.range
        selectedTextRanges[bufferID] = match.range
        setCursorUTF8Offset(match.range.lowerBound)
        focusRevision += 1
        navigationHistory.replaceCurrent(currentNavigationLocation())
        statusText = "Found \(findQuery) at \(match.displayLocation)"
    }

    func updateWorkspaceSearchQuery(_ query: String) {
        workspaceSearchQuery = query
        syncWorkspaceSearch()
    }

    func selectNextWorkspaceSearchResult() {
        guard !workspaceSearchResults.isEmpty else {
            activeWorkspaceSearchResultIndex = nil
            return
        }

        activeWorkspaceSearchResultIndex = activeWorkspaceSearchResultIndex
            .map { ($0 + 1) % workspaceSearchResults.count }
            ?? 0
    }

    func selectPreviousWorkspaceSearchResult() {
        guard !workspaceSearchResults.isEmpty else {
            activeWorkspaceSearchResultIndex = nil
            return
        }

        activeWorkspaceSearchResultIndex = activeWorkspaceSearchResultIndex
            .map { ($0 - 1 + workspaceSearchResults.count) % workspaceSearchResults.count }
            ?? workspaceSearchResults.count - 1
    }

    func openActiveWorkspaceSearchResult() {
        guard let activeWorkspaceSearchResultIndex,
              workspaceSearchResults.indices.contains(activeWorkspaceSearchResultIndex)
        else {
            return
        }

        openWorkspaceSearchResult(workspaceSearchResults[activeWorkspaceSearchResultIndex])
    }

    func openWorkspaceSearchResult(_ result: WorkspaceSearchResult) {
        recordNavigationBeforeJump()
        guard open(url: result.fileURL) else {
            return
        }

        let cursorOffset = TextEditingPrimitives.utf8Offset(
            in: text,
            line: result.line,
            column: result.column
        )
        setCursorUTF8Offset(cursorOffset)
        focusRevision += 1
        navigationHistory.replaceCurrent(currentNavigationLocation())
        statusText = "Opened \(result.displayLocation)"
    }

    func updateQuickOpenQuery(_ query: String) {
        quickOpenQuery = query
        syncQuickOpenResults()
    }

    func openQuickOpenResult(_ result: QuickOpenResult) {
        recordNavigationBeforeJump()
        guard open(url: result.fileURL) else {
            return
        }

        navigationHistory.replaceCurrent(currentNavigationLocation())
        statusText = "Opened \(result.displayPath)"
    }

    func goToLine(_ input: String) -> Bool {
        guard hasOpenBuffer else {
            statusText = "Open a file before jumping to a line"
            return false
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lineNumber = Int(trimmed), lineNumber > 0 else {
            statusText = "Enter a valid line number"
            return false
        }

        let maxLine = max(renderSnapshot.lines.count, 1)
        guard lineNumber <= maxLine else {
            statusText = "Line \(lineNumber) is beyond the end of the file"
            return false
        }

        recordNavigationBeforeJump()
        let cursorOffset = TextEditingPrimitives.utf8Offset(in: text, line: lineNumber - 1, column: 0)
        selectedTextRange = nil
        selectedTextRanges[bufferID] = nil
        setCursorUTF8Offset(cursorOffset)
        focusRevision += 1
        navigationHistory.replaceCurrent(currentNavigationLocation())
        statusText = "Jumped to line \(lineNumber)"
        return true
    }

    func findReferencesForCurrentQuery() {
        guard let workspaceURL else {
            referenceQuery = ""
            referenceResults = []
            statusText = "Open a folder before finding references"
            return
        }

        guard hasOpenBuffer,
              let query = TextQueryExtraction.query(
                in: text,
                selectedRange: selectedTextRange,
                cursorUTF8Offset: TextEditingPrimitives.utf8Offset(
                    in: text,
                    line: renderSnapshot.cursorLine,
                    column: renderSnapshot.cursorColumn
                )
              )
        else {
            referenceQuery = ""
            referenceResults = []
            statusText = "Select a symbol or place the cursor on a word"
            return
        }

        referenceSearchTask?.cancel()
        referenceQuery = query
        referenceResults = []
        isReferenceSearchRunning = true
        statusText = "Finding references for \(query)"

        referenceSearchTask = Task { [workspaceURL, query] in
            let results = await Task.detached {
                WorkspaceReferenceSearch.search(query: query, workspaceURL: workspaceURL)
            }.value

            guard !Task.isCancelled else {
                return
            }

            self.referenceResults = results
            self.isReferenceSearchRunning = false
            self.statusText = results.isEmpty
                ? "No references for \(query)"
                : "Found \(results.count) references for \(query)"
        }
    }

    func openReferenceResult(_ result: WorkspaceReferenceResult) {
        recordNavigationBeforeJump()
        guard open(url: result.fileURL) else {
            return
        }

        let cursorOffset = TextEditingPrimitives.utf8Offset(
            in: text,
            line: result.line,
            column: result.column
        )
        setCursorUTF8Offset(cursorOffset)
        focusRevision += 1
        navigationHistory.replaceCurrent(currentNavigationLocation())
        statusText = "Opened \(result.displayLocation)"
    }

    func goBackInNavigationHistory() {
        navigationHistory.replaceCurrent(currentNavigationLocation())
        guard let location = navigationHistory.goBack() else {
            statusText = "No previous navigation location"
            return
        }

        navigate(to: location)
    }

    func goForwardInNavigationHistory() {
        navigationHistory.replaceCurrent(currentNavigationLocation())
        guard let location = navigationHistory.goForward() else {
            statusText = "No next navigation location"
            return
        }

        navigate(to: location)
    }

    func isCurrentFile(_ node: WorkspaceFileNode) -> Bool {
        guard !node.isDirectory, let fileURL else {
            return false
        }

        return fileURL.standardizedFileURL == node.url.standardizedFileURL
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

    private func syncCurrentBufferState() {
        syncTextFromCore()
        syncRenderSnapshot()
        syncMarkdownPreviewHTML()
        syncDirtyState()
        syncFindMatches()
        syncOpenBuffers()
    }

    private func clearCurrentBufferState() {
        fileURL = nil
        selectedTextRange = nil
        text = ""
        renderSnapshot = .empty
        markdownPreviewHTML = ""
        isDirty = false
        syncFindMatches()
        syncOpenBuffers()
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

    private func appendLanguageServerOutput(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        for message in languageServerFramer.append(data) {
            applyLanguageServerMessage(message)
        }
    }

    private func sendCurrentDocumentOpenToLanguageServer() {
        guard let fileURL,
              let provider = selectedLanguageServerProvider,
              provider.id.supportedExtensions.contains(fileURL.pathExtension),
              isLanguageServerRunning
        else {
            return
        }

        let version = documentVersions[bufferID, default: 1]
        let event = LanguageServerDocumentEvent.didOpen(
            uri: fileURL.absoluteString,
            languageID: languageID(for: fileURL),
            version: version,
            text: text
        )
        sendLanguageServerNotification(method: event.method, params: event.payload)
    }

    private func sendCurrentDocumentChangeToLanguageServer() {
        guard let fileURL, isLanguageServerRunning else {
            return
        }

        let version = (documentVersions[bufferID] ?? 1) + 1
        documentVersions[bufferID] = version
        let event = LanguageServerDocumentEvent.didChange(
            uri: fileURL.absoluteString,
            version: version,
            text: text
        )
        sendLanguageServerNotification(method: event.method, params: event.payload)
    }

    private func sendCurrentDocumentSaveToLanguageServer() {
        guard let fileURL, isLanguageServerRunning else {
            return
        }

        let event = LanguageServerDocumentEvent.didSave(
            uri: fileURL.absoluteString,
            text: text
        )
        sendLanguageServerNotification(method: event.method, params: event.payload)
    }

    private func sendDocumentCloseToLanguageServer(fileURL: URL?) {
        guard let fileURL, isLanguageServerRunning else {
            return
        }

        let event = LanguageServerDocumentEvent.didClose(uri: fileURL.absoluteString)
        sendLanguageServerNotification(method: event.method, params: event.payload)
    }

    private func sendLanguageServerRequest(method: String, id: Int, params: [String: Any]) {
        sendLanguageServerObject([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ])
    }

    private func sendLanguageServerNotification(method: String, params: [String: Any]) {
        sendLanguageServerObject([
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ])
    }

    private func sendLanguageServerObject(_ object: [String: Any]) {
        guard let input = languageServerInput,
              let payload = try? JSONSerialization.data(withJSONObject: object)
        else {
            return
        }

        var message = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        message.append(payload)
        input.write(message)
    }

    private func initializeParams() -> [String: Any] {
        let rootURI: Any = workspaceURL.map(\.absoluteString) ?? NSNull()
        return [
            "processId": ProcessInfo.processInfo.processIdentifier,
            "rootUri": rootURI,
            "capabilities": [
                "textDocument": [
                    "synchronization": [
                        "didSave": true,
                    ],
                    "publishDiagnostics": [:],
                ],
            ],
        ]
    }

    private func languageID(for fileURL: URL) -> String {
        switch fileURL.pathExtension {
        case "swift":
            "swift"
        case "rs":
            "rust"
        case "kt", "kts":
            "kotlin"
        default:
            "plaintext"
        }
    }

    private func isPublishDiagnosticsMessage(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        return object["method"] as? String == "textDocument/publishDiagnostics"
    }

    private func publishDiagnosticsURL(_ data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let params = object["params"] as? [String: Any],
              let uri = params["uri"] as? String,
              let url = URL(string: uri)
        else {
            return nil
        }

        return url.standardizedFileURL
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
            syncFindMatches()
            syncOpenBuffers()
            sendCurrentDocumentChangeToLanguageServer()
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
            syncFindMatches()
            syncOpenBuffers()
            sendCurrentDocumentChangeToLanguageServer()
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
            session.updateCurrentBuffer(fileURL: fileURL, isDirty: isDirty)
            syncOpenBuffers()
        }
    }

    private func syncFindMatches() {
        guard !findQuery.isEmpty else {
            findMatches = []
            activeFindMatchIndex = nil
            return
        }

        findMatches = TextSearch.matches(in: text, query: findQuery)

        if findMatches.isEmpty {
            activeFindMatchIndex = nil
        } else if let activeFindMatchIndex, findMatches.indices.contains(activeFindMatchIndex) {
        } else {
            activeFindMatchIndex = 0
        }
    }

    private func syncWorkspaceSearch() {
        guard let workspaceURL else {
            workspaceSearchTask?.cancel()
            isWorkspaceSearchRunning = false
            workspaceSearchResults = []
            activeWorkspaceSearchResultIndex = nil
            return
        }

        let query = workspaceSearchQuery
        workspaceSearchTask?.cancel()

        guard !query.isEmpty else {
            workspaceSearchResults = []
            activeWorkspaceSearchResultIndex = nil
            isWorkspaceSearchRunning = false
            return
        }

        isWorkspaceSearchRunning = true
        workspaceSearchTask = Task { [workspaceURL, query] in
            let results = await Task.detached {
                WorkspaceTextSearch.search(query: query, workspaceURL: workspaceURL)
            }.value

            guard !Task.isCancelled, self.workspaceSearchQuery == query else {
                return
            }

            self.workspaceSearchResults = results
            self.activeWorkspaceSearchResultIndex = results.isEmpty ? nil : 0
            self.isWorkspaceSearchRunning = false
        }
    }

    private func refreshQuickOpenCandidates() {
        if let workspaceURL {
            quickOpenCandidates = QuickOpenMatcher.candidates(in: workspaceURL)
        } else {
            quickOpenCandidates = []
        }
        syncQuickOpenResults()
    }

    private func syncQuickOpenResults() {
        quickOpenResults = QuickOpenMatcher.results(
            query: quickOpenQuery,
            candidates: quickOpenCandidates,
            openFileURLs: openBuffers.compactMap(\.fileURL),
            recentFileURLs: recentFileURLs
        )
    }

    private func recordRecentFile(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        recentFileURLs.removeAll { $0.standardizedFileURL == standardizedURL }
        recentFileURLs.insert(standardizedURL, at: 0)
        if recentFileURLs.count > 40 {
            recentFileURLs.removeLast(recentFileURLs.count - 40)
        }
        syncQuickOpenResults()
        scheduleSessionStatePersistence()
    }

    private func captureCurrentViewState() {
        guard hasOpenBuffer else {
            return
        }

        selectedTextRanges[bufferID] = selectedTextRange
    }

    private func recordNavigationBeforeJump() {
        guard let location = currentNavigationLocation() else {
            return
        }

        navigationHistory.visit(location)
    }

    private func currentNavigationLocation() -> NavigationLocation? {
        guard hasOpenBuffer, let fileURL else {
            return nil
        }

        return NavigationLocation(
            fileURL: fileURL,
            line: renderSnapshot.cursorLine,
            column: renderSnapshot.cursorColumn,
            scrollPosition: currentScrollPosition
        )
    }

    private func navigate(to location: NavigationLocation) {
        guard open(url: location.fileURL) else {
            return
        }

        let cursorOffset = TextEditingPrimitives.utf8Offset(
            in: text,
            line: location.line,
            column: location.column
        )
        scrollPositions[bufferID] = location.scrollPosition
        scrollPositionRevision += 1
        setCursorUTF8Offset(cursorOffset)
        focusRevision += 1
        navigationHistory.replaceCurrent(location)
        statusText = "Opened \(location.displayLocation)"
    }

    private func restoreEditorSession() {
        guard let state = sessionRestorationStore.load() else {
            return
        }

        isRestoringSession = true
        defer {
            isRestoringSession = false
            syncOpenBuffers()
            refreshQuickOpenCandidates()
            navigationHistory.replaceCurrent(currentNavigationLocation())
            scheduleSessionStatePersistence()
        }

        let fileManager = FileManager.default
        if let workspacePath = state.workspacePath,
           fileManager.fileExists(atPath: workspacePath) {
            openFolder(url: URL(fileURLWithPath: workspacePath))
        }

        let statesByPath = Dictionary(uniqueKeysWithValues: state.openFiles.map { ($0.path, $0) })
        for fileState in state.openFiles where fileManager.isReadableFile(atPath: fileState.path) {
            let url = URL(fileURLWithPath: fileState.path)
            guard open(url: url) else {
                continue
            }

            restore(fileState, toCurrentBufferWith: url)
        }

        if let currentFilePath = state.currentFilePath,
           fileManager.isReadableFile(atPath: currentFilePath) {
            let currentURL = URL(fileURLWithPath: currentFilePath)
            if open(url: currentURL),
               let fileState = statesByPath[currentFilePath] {
                restore(fileState, toCurrentBufferWith: currentURL)
            }
        }

        recentFileURLs = state.recentFilePaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { fileManager.isReadableFile(atPath: $0.path) }

        statusText = hasOpenBuffer
            ? "Restored \(openBuffers.count) files"
            : "Open a file to start editing through the Rust core."
    }

    private func restore(_ fileState: EditorSessionFileState, toCurrentBufferWith url: URL) {
        guard hasOpenBuffer, fileURL?.standardizedFileURL == url.standardizedFileURL else {
            return
        }

        let cursorOffset = TextEditingPrimitives.utf8Offset(
            in: text,
            line: fileState.line,
            column: fileState.column
        )
        _ = feSetCursorOffset(bufferID, cursorOffset)
        selectedTextRange = fileState.selectedUTF8Range
        selectedTextRanges[bufferID] = fileState.selectedUTF8Range
        scrollPositions[bufferID] = fileState.scrollPosition
        syncRenderSnapshot()
    }

    private func scheduleSessionStatePersistence() {
        guard !isRestoringSession else {
            return
        }

        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            self?.persistEditorSessionState()
        }
    }

    private func persistEditorSessionState() {
        guard !isRestoringSession else {
            return
        }

        captureCurrentViewState()

        let fileStates = openBuffers.compactMap { buffer -> EditorSessionFileState? in
            guard let fileURL = buffer.fileURL?.standardizedFileURL else {
                return nil
            }

            let snapshot = renderSnapshot(for: buffer.id)
            let scrollPosition = scrollPositions[buffer.id] ?? .zero
            let selectedRange = selectedTextRanges[buffer.id]

            return EditorSessionFileState(
                path: fileURL.path,
                line: snapshot?.cursorLine ?? 0,
                column: snapshot?.cursorColumn ?? 0,
                scrollX: scrollPosition.x,
                scrollY: scrollPosition.y,
                selectionLowerUTF8Offset: selectedRange?.lowerBound,
                selectionUpperUTF8Offset: selectedRange?.upperBound
            )
        }

        let state = EditorSessionRestorationState(
            workspacePath: workspaceURL?.standardizedFileURL.path,
            currentFilePath: fileURL?.standardizedFileURL.path,
            openFiles: fileStates,
            recentFilePaths: recentFileURLs.map { $0.standardizedFileURL.path }
        )
        sessionRestorationStore.save(state)
    }

    private func renderSnapshot(for bufferID: UInt64) -> EditorRenderSnapshot? {
        let value = feGetRenderSnapshot(bufferID)
        defer {
            feFreeString(value)
        }

        guard let pointer = value.ptr else {
            return nil
        }

        return try? JSONDecoder().decode(
            EditorRenderSnapshot.self,
            from: Data(bytes: pointer, count: value.len)
        )
    }

    private func syncOpenBuffers() {
        openBuffers = session.openBuffers
        syncQuickOpenResults()
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
