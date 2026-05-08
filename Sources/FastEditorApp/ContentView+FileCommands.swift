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

    @discardableResult
    func saveFile() -> Bool {
        if editor.isUntitled {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "Untitled.txt"

            if panel.runModal() == .OK, let url = panel.url {
                return editor.saveAs(url: url)
            }

            return false
        } else {
            return editor.save()
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
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let previousBufferID = editor.renderSnapshot.bufferID
            if previousBufferID != buffer.id {
                _ = editor.switchToBuffer(id: buffer.id)
            }
            guard saveFile() else {
                if previousBufferID != buffer.id {
                    _ = editor.switchToBuffer(id: previousBufferID)
                }
                return
            }
            editor.closeBuffer(id: buffer.id)
        case .alertSecondButtonReturn:
            editor.closeBuffer(id: buffer.id, force: true)
        default:
            break
        }
    }
}
