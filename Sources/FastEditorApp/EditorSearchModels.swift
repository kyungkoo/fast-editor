import Foundation
import FastEditorTextEditing

struct TextSearchMatch: Identifiable, Equatable {
    var range: Range<Int>
    var line: Int
    var column: Int
    var linePreview: String

    var id: Int {
        range.lowerBound
    }

    var displayLocation: String {
        "\(line + 1):\(column + 1)"
    }
}

enum TextSearch {
    static func matches(
        in text: String,
        query: String,
        caseInsensitive: Bool = true
    ) -> [TextSearchMatch] {
        guard !query.isEmpty else {
            return []
        }

        var matches: [TextSearchMatch] = []
        var searchRange = text.startIndex..<text.endIndex
        let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []

        while let range = text.range(of: query, options: options, range: searchRange) {
            let lowerBound = text[..<range.lowerBound].utf8.count
            let upperBound = text[..<range.upperBound].utf8.count
            let position = TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: lowerBound)
            matches.append(TextSearchMatch(
                range: lowerBound..<upperBound,
                line: position.line,
                column: position.column,
                linePreview: linePreview(in: text, containing: range.lowerBound)
            ))

            guard range.upperBound < text.endIndex else {
                break
            }
            searchRange = range.upperBound..<text.endIndex
        }

        return matches
    }

    private static func linePreview(in text: String, containing index: String.Index) -> String {
        let lineStart = text[..<index].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[index...].firstIndex(of: "\n") ?? text.endIndex
        let line = String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? "(blank line)" : line
    }
}

struct WorkspaceSearchResult: Identifiable, Equatable {
    var fileURL: URL
    var displayPath: String
    var line: Int
    var column: Int
    var preview: String

    var id: String {
        "\(fileURL.path):\(line):\(column):\(preview)"
    }

    var displayLocation: String {
        "\(displayPath):\(line + 1):\(column + 1)"
    }
}

enum WorkspaceTextSearch {
    static let resultLimit = 200

    static func search(
        query: String,
        workspaceURL: URL
    ) -> [WorkspaceSearchResult] {
        guard !query.isEmpty else {
            return []
        }

        let files = WorkspaceFileNode.searchableFileURLs(in: workspaceURL)
        var results: [WorkspaceSearchResult] = []

        for fileURL in files {
            guard results.count < resultLimit,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8)
            else {
                continue
            }

            for match in TextSearch.matches(in: text, query: query) {
                results.append(WorkspaceSearchResult(
                    fileURL: fileURL,
                    displayPath: displayPath(for: fileURL, relativeTo: workspaceURL),
                    line: match.line,
                    column: match.column,
                    preview: match.linePreview
                ))

                if results.count >= resultLimit {
                    return results
                }
            }
        }

        return results
    }

    private static func displayPath(for fileURL: URL, relativeTo workspaceURL: URL) -> String {
        let workspacePath = workspaceURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(workspacePath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(workspacePath.count + 1))
    }
}
