import FastEditorModels
import AppKit

extension ContentView {
    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            editor.open(url: url)
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            editor.openFolder(url: url)
        }
    }

    func saveFile() {
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

    func closeBuffer(_ buffer: EditorOpenBuffer) {
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
