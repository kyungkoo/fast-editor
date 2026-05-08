import Foundation

enum AppCommand {
    static let newFile = Notification.Name("FastEditorNewFileCommand")
    static let openFile = Notification.Name("FastEditorOpenFileCommand")
    static let openFolder = Notification.Name("FastEditorOpenFolderCommand")
    static let save = Notification.Name("FastEditorSaveCommand")
    static let find = Notification.Name("FastEditorFindCommand")

    static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
