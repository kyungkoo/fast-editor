import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var editor = EditorCoreBridge()
    @State private var showsMarkdownPreview = false
    @State private var showsAgentPanel = true
    @State private var showsTaskOutputPanel = true
    @State private var showsFindBar = true

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
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.find)) { _ in
            showsFindBar = true
        }
        .onChange(of: editor.selectedTaskPlan?.taskID) { _, taskID in
            if taskID != nil {
                showsTaskOutputPanel = true
            }
        }
    }

    private var workspaceSurface: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)

            centerSurface
                .frame(minWidth: 420)

            if showsAgentPanel {
                AgentPanel(editor: editor)
                    .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)
            }
        }
    }

    private var centerSurface: some View {
        VStack(spacing: 0) {
            editorSurface

            if showsTaskOutputPanel, let plan = editor.selectedTaskPlan {
                Divider()
                taskOutputPanel(plan)
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 300)
            }
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        VStack(spacing: 0) {
            if editor.hasOpenBuffer {
                editorTabs
                Divider()
                if showsFindBar {
                    findBar
                    Divider()
                }
            }

            editorBody
        }
    }

    @ViewBuilder
    private var editorBody: some View {
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

    private var editorTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(editor.openBuffers) { buffer in
                    bufferTab(buffer)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func bufferTab(_ buffer: EditorOpenBuffer) -> some View {
        HStack(spacing: 6) {
            Button {
                editor.switchToBuffer(id: buffer.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: buffer.fileURL == nil ? "doc.badge.plus" : "doc.text")
                    Text(buffer.title)
                        .lineLimit(1)
                    if buffer.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 8)
            }
            .buttonStyle(.plain)

            Button {
                closeBuffer(buffer)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.trailing, 6)
        }
        .foregroundStyle(editor.renderSnapshot.bufferID == buffer.id ? Color.primary : Color.secondary)
        .background(editor.renderSnapshot.bufferID == buffer.id ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(buffer.subtitle)
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in file", text: Binding(
                get: { editor.findQuery },
                set: { query in
                    editor.updateFindQuery(query)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .onSubmit {
                editor.selectNextFindMatch()
            }

            Text(editor.findStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Button {
                editor.selectPreviousFindMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(editor.findMatches.isEmpty)
            .help("Previous match")

            Button {
                editor.selectNextFindMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(editor.findMatches.isEmpty)
            .help("Next match")

            Button {
                showsFindBar = false
            } label: {
                Image(systemName: "xmark")
            }
            .help("Hide find")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var editorPane: some View {
        MetalTextEditor(
            text: editor.textBinding,
            snapshot: editor.renderSnapshot,
            isEditable: editor.hasOpenBuffer,
            focusRevision: editor.focusRevision,
            diagnosticLineIndexes: editor.diagnosticLineIndexesForCurrentFile,
            onTextChange: editor.replaceText,
            onCursorMove: editor.setCursorUTF8Offset,
            onSelectionChange: editor.setSelectionUTF8Range,
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

            if editor.selectedTaskPlan != nil {
                Toggle("Output", isOn: $showsTaskOutputPanel)
                    .toggleStyle(.switch)
            }

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
            }
            .font(.callout)
            .padding(12)

            if editor.workspaceURL != nil {
                Divider()
                workspaceSearchSection
                Divider()
                fileTreeSection
                Divider()
                languageServerSection
                Divider()
                taskSection
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var fileTreeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.workspaceFileTree.isEmpty {
                Label("No files", systemImage: "folder")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    OutlineGroup(editor.workspaceFileTree, children: \.children) { node in
                        fileTreeRow(node)
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .font(.callout)
        .padding(12)
    }

    private var workspaceSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Workspace search", text: Binding(
                get: { editor.workspaceSearchQuery },
                set: { query in
                    editor.updateWorkspaceSearchQuery(query)
                }
            ))
            .textFieldStyle(.roundedBorder)

            if !editor.workspaceSearchQuery.isEmpty {
                if editor.workspaceSearchResults.isEmpty {
                    Label("No matches", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(editor.workspaceSearchResults) { result in
                                Button {
                                    editor.openWorkspaceSearchResult(result)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(result.displayLocation, systemImage: "doc.text.magnifyingglass")
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(result.preview)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .font(.callout)
        .padding(12)
    }

    @ViewBuilder
    private func fileTreeRow(_ node: WorkspaceFileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Button {
                editor.open(url: node.url)
            } label: {
                Label(node.name, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(editor.isCurrentFile(node) ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(node.url.path)
        }
    }

    private var languageServerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language")
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.availableLanguageServerProviders.isEmpty {
                Label("No language server detected", systemImage: "waveform.path.ecg")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Server", selection: Binding(
                    get: { editor.selectedLanguageServerID },
                    set: { id in
                        editor.selectLanguageServer(id)
                    }
                )) {
                    ForEach(editor.availableLanguageServerProviders) { provider in
                        Text(provider.displayName).tag(Optional(provider.id))
                    }
                }
                .labelsHidden()
                .disabled(editor.isLanguageServerRunning)

                HStack {
                    Button(editor.isLanguageServerRunning ? "Stop" : "Start") {
                        if editor.isLanguageServerRunning {
                            editor.stopLanguageServer()
                        } else {
                            editor.startLanguageServer()
                        }
                    }

                    Button {
                        editor.refreshLanguageServers()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(editor.isLanguageServerRunning)
                    .help("Refresh language servers")

                    Spacer()
                }

                Text(editor.languageServerStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !editor.languageServerDiagnosticsForCurrentFile.isEmpty {
                Divider()

                ForEach(editor.languageServerDiagnosticsForCurrentFile) { diagnostic in
                    Button {
                        editor.navigateToLanguageServerDiagnostic(diagnostic)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(diagnostic.locationDisplay, systemImage: diagnosticIcon(for: diagnostic.severity))
                                .foregroundStyle(diagnosticColor(for: diagnostic.severity))
                                .lineLimit(1)

                            Text(diagnostic.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.callout)
        .padding(12)
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

                Button("Output") {
                    showsTaskOutputPanel = true
                }

                Spacer()

                Text(editor.taskStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func taskOutputPanel(_ plan: TaskExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Task Output")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(plan.commandDisplay)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(editor.taskStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button("Hide") {
                    showsTaskOutputPanel = false
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HSplitView {
                ScrollView {
                    Text(editor.taskOutput.isEmpty ? "No output yet" : editor.taskOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(editor.taskOutput.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minWidth: 260)
                .background(Color(nsColor: .textBackgroundColor))

                if !editor.taskDiagnostics.isEmpty {
                    ScrollView {
                        diagnosticsList
                            .padding(12)
                    }
                    .frame(minWidth: 220, idealWidth: 280)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
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

    private func closeBuffer(_ buffer: EditorOpenBuffer) {
        guard buffer.isDirty else {
            editor.closeBuffer(id: buffer.id)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Close \(buffer.title)?"
        alert.informativeText = "This buffer has unsaved changes."
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            editor.closeBuffer(id: buffer.id, force: true)
        }
    }
}
