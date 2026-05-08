import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var editor = EditorCoreBridge()
    @State private var showsMarkdownPreview = false
    @State private var showsAgentPanel = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            workspaceSurface
        }
        .alert("Editor Core Error", isPresented: editor.errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newFile)) { _ in
            editor.newFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openFile)) { _ in
            openFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openFolder)) { _ in
            openFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.save)) { _ in
            saveFile()
        }
    }

    private var workspaceSurface: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

            editorSurface
                .frame(minWidth: 420)

            if showsAgentPanel {
                AgentPanel(editor: editor)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            }
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        if showsMarkdownPreview {
            HStack(spacing: 0) {
                editorPane
                Divider()
                MarkdownPreview(html: editor.markdownPreviewHTML)
                    .frame(minWidth: 280)
            }
        } else {
            editorPane
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        MetalTextEditor(
            text: editor.textBinding,
            snapshot: editor.renderSnapshot,
            isEditable: editor.hasOpenBuffer,
            focusRevision: editor.focusRevision,
            onTextChange: editor.replaceText,
            onCursorMove: editor.setCursorUTF8Offset,
            onUndo: editor.undo,
            onRedo: editor.redo
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("New File") {
                editor.newFile()
            }
            .keyboardShortcut("n")

            Button("Open...") {
                openFile()
            }
            .keyboardShortcut("o")

            Button("Open Folder...") {
                openFolder()
            }
            .keyboardShortcut("O", modifiers: [.command, .shift])

            Button("Save") {
                saveFile()
            }
            .keyboardShortcut("s")
            .disabled(!editor.canSave)

            if editor.hasOpenBuffer {
                Text(editor.isDirty ? "Unsaved" : "Saved")
                    .font(.caption)
                    .foregroundStyle(editor.isDirty ? Color.orange : Color.secondary)
            }

            Text(editor.statusText)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("Preview", isOn: $showsMarkdownPreview)
                .toggleStyle(.switch)
                .disabled(!editor.hasOpenBuffer)

            Toggle("Agent", isOn: $showsAgentPanel)
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Workspace")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label(editor.workspaceURL?.lastPathComponent ?? "No folder open", systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)

                Label(editor.fileURL?.lastPathComponent ?? "No file open", systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .padding(12)

            if editor.workspaceURL != nil {
                Divider()
                taskSection
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tasks")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.projectTaskSummary.detections.isEmpty {
                Label("No build provider detected", systemImage: "hammer")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editor.projectTaskSummary.detections) { detection in
                    Label(detection.providerID.displayName, systemImage: "checkmark.circle")
                        .help(detection.evidence.joined(separator: ", "))
                }

                ForEach(editor.projectTaskSummary.tasks) { task in
                    Button {
                        editor.selectTask(task)
                    } label: {
                        Label(task.label, systemImage: taskIcon(for: task.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(task.detail ?? task.id)
                }

                if let android = editor.projectTaskSummary.android {
                    Divider()

                    Label(android.environment.sdkLocation == nil ? "Android SDK missing" : "Android SDK found",
                          systemImage: android.environment.sdkLocation == nil ? "exclamationmark.triangle" : "checkmark.circle")
                    Label(android.project.hasGradleWrapper ? "Gradle wrapper found" : "Gradle wrapper missing",
                          systemImage: android.project.hasGradleWrapper ? "checkmark.circle" : "exclamationmark.triangle")
                }

                if let plan = editor.selectedTaskPlan {
                    Divider()
                    taskPreview(plan)
                }
            }
        }
        .font(.callout)
        .padding(12)
    }

    private func taskPreview(_ plan: TaskExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(plan.commandDisplay)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)

            HStack {
                Button(editor.isTaskRunning ? "Stop" : "Run") {
                    if editor.isTaskRunning {
                        editor.stopRunningTask()
                    } else {
                        editor.runSelectedTask()
                    }
                }

                Spacer()

                Text(editor.taskStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !editor.taskOutput.isEmpty {
                ScrollView {
                    Text(editor.taskOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .background(Color(nsColor: .textBackgroundColor))
            }

            if !editor.taskDiagnostics.isEmpty {
                Divider()
                diagnosticsList
            }
        }
    }

    private var diagnosticsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostics")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(editor.taskDiagnostics) { diagnostic in
                Button {
                    editor.navigateToDiagnostic(diagnostic)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(diagnostic.locationDisplay, systemImage: diagnosticIcon(for: diagnostic.severity))
                            .foregroundStyle(diagnosticColor(for: diagnostic.severity))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(diagnostic.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Open \(diagnostic.locationDisplay)")
            }
        }
    }

    private func taskIcon(for kind: TaskKind) -> String {
        switch kind {
        case .build:
            "hammer"
        case .run:
            "play"
        case .test:
            "checklist"
        case .script:
            "terminal"
        case .other:
            "gearshape"
        }
    }

    private func diagnosticIcon(for severity: TaskDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            "xmark.octagon"
        case .warning:
            "exclamationmark.triangle"
        case .note:
            "info.circle"
        }
    }

    private func diagnosticColor(for severity: TaskDiagnosticSeverity) -> Color {
        switch severity {
        case .error:
            .red
        case .warning:
            .orange
        case .note:
            .secondary
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            editor.open(url: url)
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            editor.openFolder(url: url)
        }
    }

    private func saveFile() {
        if editor.isUntitled {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Untitled.txt"

            if panel.runModal() == .OK, let url = panel.url {
                _ = editor.saveAs(url: url)
            }
        } else {
            _ = editor.save()
        }
    }
}
