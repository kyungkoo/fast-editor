import SwiftUI

extension ContentView {
    var toolbar: some View {
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
}
