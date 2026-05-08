import Foundation

struct AgentProposedEdit: Equatable {
    var replacementText: String
}

enum AgentDiffPreview {
    static func extractProposedEdit(from transcript: String) -> AgentProposedEdit? {
        guard let range = fencedBlockRange(named: "fast-editor-replacement", in: transcript) else {
            return nil
        }

        return AgentProposedEdit(replacementText: String(transcript[range]))
    }

    static func unifiedPreview(
        original: String,
        replacement: String,
        path: String
    ) -> String {
        let originalLines = splitLines(original)
        let replacementLines = splitLines(replacement)
        var rows = [
            "--- \(path)",
            "+++ \(path)"
        ]

        var originalIndex = 0
        var replacementIndex = 0
        while originalIndex < originalLines.count || replacementIndex < replacementLines.count {
            if originalIndex < originalLines.count,
               replacementIndex < replacementLines.count,
               originalLines[originalIndex] == replacementLines[replacementIndex] {
                rows.append("  \(originalLines[originalIndex])")
                originalIndex += 1
                replacementIndex += 1
            } else {
                if originalIndex < originalLines.count {
                    rows.append("- \(originalLines[originalIndex])")
                    originalIndex += 1
                }
                if replacementIndex < replacementLines.count {
                    rows.append("+ \(replacementLines[replacementIndex])")
                    replacementIndex += 1
                }
            }
        }

        return rows.joined(separator: "\n")
    }

    private static func fencedBlockRange(
        named name: String,
        in text: String
    ) -> Range<String.Index>? {
        guard let opening = text.range(of: "```\(name)") else {
            return nil
        }

        let contentStart = text[opening.upperBound...].first == "\n"
            ? text.index(after: opening.upperBound)
            : opening.upperBound

        guard let closing = text[contentStart...].range(of: "\n```") else {
            return nil
        }

        return contentStart..<closing.lowerBound
    }

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
