struct EditorRenderSnapshot: Decodable, Equatable {
    var bufferID: UInt64
    var dirty: Bool
    var language: EditorDocumentLanguage
    var cursorLine: Int
    var cursorColumn: Int
    var lines: [EditorRenderLine]

    static let empty = EditorRenderSnapshot(
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

enum EditorDocumentLanguage: String, Decodable {
    case plainText = "plain_text"
    case markdown
    case kotlin
    case rust
    case swift
}

struct EditorRenderLine: Decodable, Equatable {
    var index: Int
    var lineNumber: Int
    var text: String
    var spans: [EditorRenderSpan]

    private enum CodingKeys: String, CodingKey {
        case index
        case lineNumber = "line_number"
        case text
        case spans
    }
}

struct EditorRenderSpan: Decodable, Equatable {
    var startColumn: Int
    var endColumn: Int
    var kind: EditorRenderSpanKind

    private enum CodingKeys: String, CodingKey {
        case startColumn = "start_column"
        case endColumn = "end_column"
        case kind
    }
}

enum EditorRenderSpanKind: String, Decodable {
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
