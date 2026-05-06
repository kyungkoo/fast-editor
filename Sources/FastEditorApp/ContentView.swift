import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var editor = EditorCoreBridge()
    @State private var renderMode = EditorRenderMode.appKit

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editorSurface
        }
        .alert("Editor Core Error", isPresented: editor.errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage)
        }
    }

    @ViewBuilder
    private var editorSurface: some View {
        switch renderMode {
        case .appKit:
            AppKitTextEditor(
                text: editor.textBinding,
                isEditable: editor.hasOpenBuffer,
                focusRevision: editor.focusRevision
            )
        case .metal:
            MetalTextEditor(
                text: editor.textBinding,
                snapshot: editor.renderSnapshot,
                isEditable: editor.hasOpenBuffer,
                focusRevision: editor.focusRevision,
                onTextChange: editor.replaceText,
                onCursorMove: editor.setCursorUTF8Offset
            )
        }
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

            Picker("Renderer", selection: $renderMode) {
                ForEach(EditorRenderMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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

private enum EditorRenderMode: String, CaseIterable, Identifiable {
    case appKit
    case metal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appKit:
            "AppKit"
        case .metal:
            "Metal"
        }
    }
}
