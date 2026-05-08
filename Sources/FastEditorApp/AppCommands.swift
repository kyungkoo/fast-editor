import Foundation

enum AppCommand {
    static let newFile = Notification.Name("FastEditorNewFileCommand")
    static let openFile = Notification.Name("FastEditorOpenFileCommand")
    static let openFolder = Notification.Name("FastEditorOpenFolderCommand")
    static let save = Notification.Name("FastEditorSaveCommand")
    static let undo = Notification.Name("FastEditorUndoCommand")
    static let redo = Notification.Name("FastEditorRedoCommand")
    static let find = Notification.Name("FastEditorFindCommand")
    static let workspaceSearch = Notification.Name("FastEditorWorkspaceSearchCommand")
    static let quickOpen = Notification.Name("FastEditorQuickOpenCommand")
    static let goToLine = Notification.Name("FastEditorGoToLineCommand")
    static let findReferences = Notification.Name("FastEditorFindReferencesCommand")
    static let navigateBack = Notification.Name("FastEditorNavigateBackCommand")
    static let navigateForward = Notification.Name("FastEditorNavigateForwardCommand")

    static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
