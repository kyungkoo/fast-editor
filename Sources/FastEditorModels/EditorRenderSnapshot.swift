public struct EditorRenderSnapshot: Decodable, Equatable, Sendable {
    public var bufferID: UInt64
    public var dirty: Bool
    public var language: EditorDocumentLanguage
    public var cursorLine: Int
    public var cursorColumn: Int
    public var lines: [EditorRenderLine]

    public init(
        bufferID: UInt64,
        dirty: Bool,
        language: EditorDocumentLanguage,
        cursorLine: Int,
        cursorColumn: Int,
        lines: [EditorRenderLine]
    ) {
        self.bufferID = bufferID
        self.dirty = dirty
        self.language = language
        self.cursorLine = cursorLine
        self.cursorColumn = cursorColumn
        self.lines = lines
    }

    public static let empty = EditorRenderSnapshot(
        bufferID: 0,
        dirty: false,
        language: .plainText,
        cursorLine: 0,
        cursorColumn: 0,
        lines: [EditorRenderLine(index: 0, lineNumber: 1, text: "", spans: [])]
    )

    private enum CodingKeys: String, CodingKey {
        case bufferID = "buffer_id"
        case dirty
        case language
        case cursorLine = "cursor_line"
        case cursorColumn = "cursor_column"
        case lines
    }
}

public enum EditorDocumentLanguage: String, Decodable, Sendable {
    case plainText = "plain_text"
    case markdown
    case kotlin
    case rust
    case swift
}

public struct EditorRenderLine: Decodable, Equatable, Sendable {
    public var index: Int
    public var lineNumber: Int
    public var text: String
    public var spans: [EditorRenderSpan]

    public init(index: Int, lineNumber: Int, text: String, spans: [EditorRenderSpan]) {
        self.index = index
        self.lineNumber = lineNumber
        self.text = text
        self.spans = spans
    }

    private enum CodingKeys: String, CodingKey {
        case index
        case lineNumber = "line_number"
        case text
        case spans
    }
}

public struct EditorRenderSpan: Decodable, Equatable, Sendable {
    public var startColumn: Int
    public var endColumn: Int
    public var kind: EditorRenderSpanKind

    public init(startColumn: Int, endColumn: Int, kind: EditorRenderSpanKind) {
        self.startColumn = startColumn
        self.endColumn = endColumn
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case startColumn = "start_column"
        case endColumn = "end_column"
        case kind
    }
}

public enum EditorRenderSpanKind: String, Decodable, Sendable {
    case markdownHeading = "markdown_heading"
    case markdownListMarker = "markdown_list_marker"
    case markdownQuote = "markdown_quote"
    case markdownCode = "markdown_code"
    case markdownInlineCode = "markdown_inline_code"
    case markdownLink = "markdown_link"
    case markdownEmphasis = "markdown_emphasis"
    case kotlinKeyword = "kotlin_keyword"
    case kotlinType = "kotlin_type"
    case kotlinFunction = "kotlin_function"
    case kotlinString = "kotlin_string"
    case kotlinComment = "kotlin_comment"
    case kotlinNumber = "kotlin_number"
    case kotlinAnnotation = "kotlin_annotation"
    case rustKeyword = "rust_keyword"
    case rustType = "rust_type"
    case rustFunction = "rust_function"
    case rustString = "rust_string"
    case rustComment = "rust_comment"
    case rustNumber = "rust_number"
    case rustAttribute = "rust_attribute"
    case swiftKeyword = "swift_keyword"
    case swiftType = "swift_type"
    case swiftFunction = "swift_function"
    case swiftString = "swift_string"
    case swiftComment = "swift_comment"
    case swiftNumber = "swift_number"
    case swiftAttribute = "swift_attribute"
}
