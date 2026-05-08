import FastEditorModels
import SwiftUI

extension ContentView {
    var statusBar: some View {
        HStack(spacing: 14) {
            Label(editor.fileURL?.lastPathComponent ?? "No file", systemImage: "doc.text")
                .lineLimit(1)
                .truncationMode(.middle)

            Text(editor.isDirty ? "Unsaved" : "Saved")
                .foregroundStyle(editor.isDirty ? .orange : .secondary)

            Text(editor.renderSnapshot.language.displayName)
                .foregroundStyle(.secondary)

            Text("Ln \(editor.renderSnapshot.cursorLine + 1), Col \(editor.renderSnapshot.cursorColumn + 1)")
                .foregroundStyle(.secondary)

            Spacer()

            if editor.isWorkspaceSearchRunning || editor.isReferenceSearchRunning || editor.isTaskRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }

            Text(backgroundActivityText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var backgroundActivityText: String {
        if editor.isWorkspaceSearchRunning {
            return "Searching workspace"
        }

        if editor.isReferenceSearchRunning {
            return "Finding references"
        }

        if editor.isTaskRunning {
            return editor.taskStatusText
        }

        return editor.statusText
    }
}

struct QuickOpenPanel: View {
    @ObservedObject var editor: EditorCoreBridge
    @Binding var isPresented: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Quick open", text: Binding(
                get: { editor.quickOpenQuery },
                set: { query in
                    editor.updateQuickOpenQuery(query)
                    selectedIndex = 0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .onSubmit(openDefaultResult)
            .onKeyPress(.tab, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    selectPreviousResult()
                } else {
                    selectNextResult()
                }
                return .handled
            }

            Text(editor.quickOpenStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if editor.workspaceURL == nil {
                emptyState("Open a folder to quick-open project files", systemImage: "folder")
            } else if editor.quickOpenResults.isEmpty {
                emptyState(editor.quickOpenQuery.isEmpty ? "No project files" : "No matching files",
                           systemImage: "magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(editor.quickOpenResults.enumerated()), id: \.element.id) { index, result in
                            Button {
                                editor.openQuickOpenResult(result)
                                isPresented = false
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.fileName)
                                            .lineLimit(1)
                                        Text(result.displayPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 6)
                                .contentShape(Rectangle())
                                .background(selectedIndex == index ? Color.accentColor.opacity(0.14) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .help(result.fileURL.path)
                        }
                    }
                }
            }
        }
        .padding(14)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: editor.quickOpenResults) { _, results in
            selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        }
    }

    private func openDefaultResult() {
        let index = min(selectedIndex, max(editor.quickOpenResults.count - 1, 0))
        guard editor.quickOpenResults.indices.contains(index) else {
            return
        }

        let result = editor.quickOpenResults[index]
        editor.openQuickOpenResult(result)
        isPresented = false
    }

    private func selectNextResult() {
        guard !editor.quickOpenResults.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = (selectedIndex + 1) % editor.quickOpenResults.count
    }

    private func selectPreviousResult() {
        guard !editor.quickOpenResults.isEmpty else {
            selectedIndex = 0
            return
        }

        selectedIndex = (selectedIndex - 1 + editor.quickOpenResults.count) % editor.quickOpenResults.count
    }

    private func emptyState(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GoToLinePanel: View {
    @ObservedObject var editor: EditorCoreBridge
    @Binding var input: String
    @Binding var isPresented: Bool
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Go to Line")
                .font(.headline)

            TextField("Line number", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit(jump)

            Text("1...\(max(editor.renderSnapshot.lines.count, 1))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .onAppear {
            isInputFocused = true
        }
    }

    private func jump() {
        if editor.goToLine(input) {
            isPresented = false
        }
    }
}

private extension EditorDocumentLanguage {
    var displayName: String {
        switch self {
        case .plainText:
            "Plain Text"
        case .markdown:
            "Markdown"
        case .kotlin:
            "Kotlin"
        case .rust:
            "Rust"
        case .swift:
            "Swift"
        }
    }
}
