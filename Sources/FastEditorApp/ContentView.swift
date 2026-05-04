import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var editor = EditorCoreBridge()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            AppKitTextEditor(
                text: editor.textBinding,
                isEditable: editor.hasOpenBuffer,
                focusRevision: editor.focusRevision
            )
        }
        .alert("Editor Core Error", isPresented: editor.errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editor.errorMessage)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Open...") {
                openFile()
            }
            .keyboardShortcut("o")

            Button("Save") {
                editor.save()
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
}
