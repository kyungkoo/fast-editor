import Foundation
import FastEditorTextEditing

struct AgentContext: Equatable {
    struct SelectionMetadata: Equatable {
        var utf8Range: Range<Int>
        var startLine: Int
        var startColumn: Int
        var endLine: Int
        var endColumn: Int

        var displayRange: String {
            "\(startLine + 1):\(startColumn + 1)-\(endLine + 1):\(endColumn + 1)"
        }

        var byteRange: String {
            "\(utf8Range.lowerBound)..<\(utf8Range.upperBound)"
        }
    }

    var fileURL: URL?
    var text: String
    var selection: SelectionMetadata?

    var path: String {
        fileURL?.path ?? "Untitled"
    }

    var isSelection: Bool {
        selection != nil
    }

    var transcriptSummary: String {
        if let selection {
            return "Context: selection \(path):\(selection.displayRange) bytes \(selection.byteRange)"
        }

        return "Context: full file \(path)"
    }

    var requestScopeDescription: String {
        if let selection {
            return """
            Context scope: selected text
            Current file: \(path)
            Selected range: \(selection.displayRange)
            Selected UTF-8 byte range: \(selection.byteRange)
            """
        }

        return """
        Context scope: full file
        Current file: \(path)
        """
    }

    var editInstruction: String {
        if selection != nil {
            return "If you propose an edit, include only the replacement text for the selected range in a fenced block named `fast-editor-replacement`."
        }

        return "If you propose a file edit, include the complete replacement text in a fenced block named `fast-editor-replacement`."
    }

    static func currentFile(fileURL: URL?, text: String, selectedRange: Range<Int>?) -> AgentContext {
        guard let selectedRange else {
            return AgentContext(fileURL: fileURL, text: text, selection: nil)
        }

        let lowerBound = TextEditingPrimitives.clampUTF8Offset(selectedRange.lowerBound, in: text)
        let upperBound = TextEditingPrimitives.clampUTF8Offset(selectedRange.upperBound, in: text)
        let normalizedRange = min(lowerBound, upperBound)..<max(lowerBound, upperBound)
        guard !normalizedRange.isEmpty else {
            return AgentContext(fileURL: fileURL, text: text, selection: nil)
        }

        let start = TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: normalizedRange.lowerBound)
        let end = TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: normalizedRange.upperBound)
        let selection = SelectionMetadata(
            utf8Range: normalizedRange,
            startLine: start.line,
            startColumn: start.column,
            endLine: end.line,
            endColumn: end.column
        )

        return AgentContext(
            fileURL: fileURL,
            text: TextEditingPrimitives.substring(in: text, utf8Range: normalizedRange),
            selection: selection
        )
    }
}
