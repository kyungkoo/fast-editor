import Foundation
import SwiftUI

struct MarkdownPreview: View {
    var markdown: String

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(blocks) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var blocks: [MarkdownPreviewBlock] {
        MarkdownPreviewParser(markdown: markdown).parse()
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownPreviewBlock) -> some View {
        switch block.kind {
        case .heading(let level, let text):
            inlineText(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .padding(.top, level == 1 ? 2 : 8)
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
                .lineSpacing(3)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.green.opacity(0.55))
                    .frame(width: 3)
                inlineText(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 2)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func inlineText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:
            24
        case 2:
            20
        case 3:
            17
        default:
            15
        }
    }
}

private struct MarkdownPreviewBlock: Identifiable {
    var id: Int
    var kind: MarkdownPreviewBlockKind
}

private enum MarkdownPreviewBlockKind {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case unorderedList([String])
    case orderedList([String])
    case code(String)
}

private struct MarkdownPreviewParser {
    var markdown: String

    func parse() -> [MarkdownPreviewBlock] {
        var blocks: [MarkdownPreviewBlock] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if isCodeFence(trimmed) {
                let result = parseCodeBlock(lines: lines, start: index)
                append(.code(result.text), to: &blocks)
                index = result.nextIndex
                continue
            }

            if let heading = parseHeading(trimmed) {
                append(.heading(level: heading.level, text: heading.text), to: &blocks)
                index += 1
                continue
            }

            if let quote = trimmed.stripPrefix(">") {
                append(.quote(quote.trimmingCharacters(in: .whitespaces)), to: &blocks)
                index += 1
                continue
            }

            if unorderedListItem(trimmed) != nil {
                let result = parseUnorderedList(lines: lines, start: index)
                append(.unorderedList(result.items), to: &blocks)
                index = result.nextIndex
                continue
            }

            if orderedListItem(trimmed) != nil {
                let result = parseOrderedList(lines: lines, start: index)
                append(.orderedList(result.items), to: &blocks)
                index = result.nextIndex
                continue
            }

            let result = parseParagraph(lines: lines, start: index)
            append(.paragraph(result.text), to: &blocks)
            index = result.nextIndex
        }

        return blocks
    }

    private func append(_ kind: MarkdownPreviewBlockKind, to blocks: inout [MarkdownPreviewBlock]) {
        blocks.append(MarkdownPreviewBlock(id: blocks.count, kind: kind))
    }

    private func parseCodeBlock(lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        let fence = lines[start].trimmingCharacters(in: .whitespaces).prefix(3)
        var codeLines: [String] = []
        var index = start + 1

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(String(fence)) {
                return (codeLines.joined(separator: "\n"), index + 1)
            }

            codeLines.append(lines[index])
            index += 1
        }

        return (codeLines.joined(separator: "\n"), index)
    }

    private func parseUnorderedList(lines: [String], start: Int) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = unorderedListItem(trimmed) else {
                break
            }

            items.append(item)
            index += 1
        }

        return (items, index)
    }

    private func parseOrderedList(lines: [String], start: Int) -> (items: [String], nextIndex: Int) {
        var items: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let item = orderedListItem(trimmed) else {
                break
            }

            items.append(item)
            index += 1
        }

        return (items, index)
    }

    private func parseParagraph(lines: [String], start: Int) -> (text: String, nextIndex: Int) {
        var paragraphLines: [String] = []
        var index = start

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || isCodeFence(trimmed)
                || parseHeading(trimmed) != nil
                || trimmed.hasPrefix(">")
                || unorderedListItem(trimmed) != nil
                || orderedListItem(trimmed) != nil
            {
                break
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        return (paragraphLines.joined(separator: " "), index)
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level),
              line.dropFirst(level).first?.isWhitespace == true
        else {
            return nil
        }

        return (level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
    }

    private func unorderedListItem(_ line: String) -> String? {
        guard let marker = line.first,
              ["-", "*", "+"].contains(marker),
              line.dropFirst().first?.isWhitespace == true
        else {
            return nil
        }

        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private func orderedListItem(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: "."),
              dotIndex > line.startIndex,
              line[..<dotIndex].allSatisfy(\.isNumber)
        else {
            return nil
        }

        let rest = line[line.index(after: dotIndex)...]
        guard rest.first?.isWhitespace == true else {
            return nil
        }

        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private func isCodeFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }
}

private extension String {
    func stripPrefix(_ prefix: Character) -> String? {
        guard first == prefix else {
            return nil
        }

        return String(dropFirst())
    }
}
