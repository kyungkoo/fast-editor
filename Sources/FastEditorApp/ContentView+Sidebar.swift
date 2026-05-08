import FastEditorModels
import SwiftUI

enum ProjectSidebarMode: String, CaseIterable {
    case files
    case search
    case references
    case project

    var title: String {
        switch self {
        case .files:
            "Files"
        case .search:
            "Search"
        case .references:
            "References"
        case .project:
            "Project"
        }
    }

    var systemImage: String {
        switch self {
        case .files:
            "folder"
        case .search:
            "magnifyingglass"
        case .references:
            "scope"
        case .project:
            "wrench.and.screwdriver"
        }
    }
}

extension ContentView {
    var sidebar: some View {
        HStack(spacing: 0) {
            sidebarModeRail
            Divider()
            sidebarPanel
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    var sidebarModeRail: some View {
        VStack(spacing: 6) {
            ForEach(ProjectSidebarMode.allCases, id: \.self) { mode in
                Button {
                    sidebarMode = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .frame(width: 28, height: 28)
                        .background(sidebarMode == mode ? Color.accentColor.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }

            Spacer()
        }
        .padding(.top, 10)
        .frame(width: 40)
    }

    var sidebarPanel: some View {
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
                activeSidebarSection
            }

            Spacer()
        }
    }

    @ViewBuilder
    var activeSidebarSection: some View {
        switch sidebarMode {
        case .files:
            fileTreeSection
        case .search:
            workspaceSearchSection
        case .references:
            referencesSection
        case .project:
            projectToolsSection
        }
    }

    var fileTreeSection: some View {
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
            }
        }
        .font(.callout)
        .padding(12)
    }

    var workspaceSearchSection: some View {
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
            .onSubmit {
                editor.openActiveWorkspaceSearchResult()
            }
            .onKeyPress(.tab, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    editor.selectPreviousWorkspaceSearchResult()
                } else {
                    editor.selectNextWorkspaceSearchResult()
                }
                return .handled
            }

            HStack(spacing: 8) {
                Text(editor.workspaceSearchStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    editor.selectPreviousWorkspaceSearchResult()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(editor.workspaceSearchResults.isEmpty)
                .help("Previous result")

                Button {
                    editor.selectNextWorkspaceSearchResult()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(editor.workspaceSearchResults.isEmpty)
                .help("Next result")
            }
            .buttonStyle(.borderless)

            if !editor.workspaceSearchQuery.isEmpty {
                if editor.isWorkspaceSearchRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if editor.workspaceSearchResults.isEmpty {
                    Label("No matches", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(editor.workspaceSearchResults.enumerated()), id: \.element.id) { index, result in
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
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 4)
                                    .background(editor.activeWorkspaceSearchResultIndex == index ? Color.accentColor.opacity(0.14) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .font(.callout)
        .padding(12)
    }

    var referencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("References")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editor.findReferencesForCurrentQuery()
                } label: {
                    Image(systemName: "scope")
                }
                .help("Find references")
            }

            Text(editor.referenceStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if editor.isReferenceSearchRunning {
                ProgressView()
                    .controlSize(.small)
            } else if !editor.referenceResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(editor.referenceResults) { result in
                            Button {
                                editor.openReferenceResult(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(result.displayLocation, systemImage: "point.3.connected.trianglepath.dotted")
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
            }
        }
        .font(.callout)
        .padding(12)
    }

    var projectToolsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                languageServerSection
                Divider()
                taskSection
            }
        }
    }

    @ViewBuilder
    func fileTreeRow(_ node: WorkspaceFileNode) -> some View {
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

    var languageServerSection: some View {
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

    var taskSection: some View {
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
}
