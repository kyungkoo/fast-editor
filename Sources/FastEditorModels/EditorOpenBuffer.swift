import Foundation

public struct EditorOpenBuffer: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public var fileURL: URL?
    public var isDirty: Bool

    public init(id: UInt64, fileURL: URL?, isDirty: Bool) {
        self.id = id
        self.fileURL = fileURL
        self.isDirty = isDirty
    }

    public var title: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }

    public var subtitle: String {
        fileURL?.path ?? "Unsaved buffer"
    }
}
