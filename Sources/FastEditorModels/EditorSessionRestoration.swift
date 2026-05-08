import Foundation

public struct EditorSessionRestorationState: Codable, Equatable, Sendable {
    public var workspacePath: String?
    public var currentFilePath: String?
    public var openFiles: [EditorSessionFileState]
    public var recentFilePaths: [String]

    public init(
        workspacePath: String?,
        currentFilePath: String?,
        openFiles: [EditorSessionFileState],
        recentFilePaths: [String]
    ) {
        self.workspacePath = workspacePath
        self.currentFilePath = currentFilePath
        self.openFiles = openFiles
        self.recentFilePaths = recentFilePaths
    }
}

public struct EditorSessionFileState: Codable, Equatable, Sendable {
    public var path: String
    public var line: Int
    public var column: Int
    public var scrollX: Double
    public var scrollY: Double
    public var selectionLowerUTF8Offset: Int?
    public var selectionUpperUTF8Offset: Int?

    public init(
        path: String,
        line: Int,
        column: Int,
        scrollX: Double = 0,
        scrollY: Double = 0,
        selectionLowerUTF8Offset: Int? = nil,
        selectionUpperUTF8Offset: Int? = nil
    ) {
        self.path = path
        self.line = max(0, line)
        self.column = max(0, column)
        self.scrollX = max(0, scrollX)
        self.scrollY = max(0, scrollY)
        self.selectionLowerUTF8Offset = selectionLowerUTF8Offset
        self.selectionUpperUTF8Offset = selectionUpperUTF8Offset
    }

    public var scrollPosition: EditorScrollPosition {
        EditorScrollPosition(x: scrollX, y: scrollY)
    }

    public var selectedUTF8Range: Range<Int>? {
        guard let selectionLowerUTF8Offset,
              let selectionUpperUTF8Offset,
              selectionLowerUTF8Offset < selectionUpperUTF8Offset
        else {
            return nil
        }

        return selectionLowerUTF8Offset..<selectionUpperUTF8Offset
    }
}
