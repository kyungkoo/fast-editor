import Foundation

struct EditorOpenBuffer: Identifiable, Equatable {
    let id: UInt64
    var fileURL: URL?
    var isDirty: Bool

    var title: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    var subtitle: String {
        fileURL?.path ?? "Unsaved buffer"
    }
}
