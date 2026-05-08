import Foundation

public enum TextEditingPrimitives {
    public static func clampUTF8Offset(_ offset: Int, in text: String) -> Int {
        var offset = min(max(0, offset), text.utf8.count)

        while offset > 0, isInsideCharacter(offset, in: text) {
            offset -= 1
        }

        return offset
    }

    public static func stringIndex(in text: String, atUTF8Offset offset: Int) -> String.Index {
        let offset = clampUTF8Offset(offset, in: text)
        var currentOffset = 0
        var index = text.startIndex

        while index < text.endIndex {
            if currentOffset == offset {
                return index
            }

            let nextIndex = text.index(after: index)
            let nextOffset = currentOffset + String(text[index]).utf8.count
            if nextOffset > offset {
                return index
            }

            currentOffset = nextOffset
            index = nextIndex
        }

        return text.endIndex
    }

    public static func utf8Offset(in text: String, atUTF16Location location: Int) -> Int {
        let nsText = text as NSString
        let location = min(max(0, location), nsText.length)
        return nsText.substring(to: location).utf8.count
    }

    public static func utf16Offset(in text: String, forUTF8Offset offset: Int) -> Int {
        let index = stringIndex(in: text, atUTF8Offset: offset)
        return text[..<index].utf16.count
    }

    public static func utf8Offset(in text: String, line targetLine: Int, column targetColumn: Int) -> Int {
        var line = 0
        var column = 0
        var offset = 0

        for character in text {
            if line == targetLine, column == targetColumn {
                return offset
            }

            if character == "\n" {
                if line == targetLine {
                    return offset
                }
                line += 1
                column = 0
            } else {
                column += 1
            }

            offset += String(character).utf8.count
        }

        return text.utf8.count
    }

    public static func cursorPosition(in text: String, forUTF8Offset offset: Int) -> (line: Int, column: Int) {
        let offset = clampUTF8Offset(offset, in: text)
        var line = 0
        var column = 0
        var currentOffset = 0

        for character in text {
            if currentOffset == offset {
                return (line, column)
            }

            if character == "\n" {
                line += 1
                column = 0
            } else {
                column += 1
            }

            currentOffset += String(character).utf8.count
        }

        return (line, column)
    }

    public static func selectedUTF8Range(
        anchor: Int?,
        cursor: Int,
        in text: String
    ) -> Range<Int>? {
        guard let anchor else {
            return nil
        }

        let clampedAnchor = clampUTF8Offset(anchor, in: text)
        let clampedCursor = clampUTF8Offset(cursor, in: text)

        guard clampedAnchor != clampedCursor else {
            return nil
        }

        return min(clampedAnchor, clampedCursor)..<max(clampedAnchor, clampedCursor)
    }

    public static func substring(in text: String, utf8Range range: Range<Int>) -> String {
        let lowerBound = stringIndex(in: text, atUTF8Offset: range.lowerBound)
        let upperBound = stringIndex(in: text, atUTF8Offset: range.upperBound)
        return String(text[lowerBound..<upperBound])
    }

    public static func replacingUTF8Range(
        _ range: Range<Int>,
        in text: String,
        with replacement: String
    ) -> (text: String, cursorUTF8Offset: Int) {
        let lowerBound = stringIndex(in: text, atUTF8Offset: range.lowerBound)
        let upperBound = stringIndex(in: text, atUTF8Offset: range.upperBound)
        var text = text
        text.replaceSubrange(lowerBound..<upperBound, with: replacement)
        return (text, range.lowerBound + replacement.utf8.count)
    }

    public static func replacingMarkdownNewline(
        in text: String,
        cursorUTF8Offset: Int,
        selectedRange: Range<Int>? = nil
    ) -> (text: String, cursorUTF8Offset: Int) {
        if let selectedRange {
            let lowerBound = clampUTF8Offset(selectedRange.lowerBound, in: text)
            let upperBound = clampUTF8Offset(selectedRange.upperBound, in: text)
            return replacingUTF8Range(
                min(lowerBound, upperBound)..<max(lowerBound, upperBound),
                in: text,
                with: "\n"
            )
        }

        let cursorUTF8Offset = clampUTF8Offset(cursorUTF8Offset, in: text)
        let cursorIndex = stringIndex(in: text, atUTF8Offset: cursorUTF8Offset)
        let lineStartIndex = lineStartIndex(in: text, before: cursorIndex)
        let lineEndIndex = lineEndIndex(in: text, after: cursorIndex)
        let lineStartUTF8Offset = text[..<lineStartIndex].utf8.count
        let lineEndUTF8Offset = text[..<lineEndIndex].utf8.count
        let currentLine = String(text[lineStartIndex..<lineEndIndex])
        let lineBeforeCursor = String(text[lineStartIndex..<cursorIndex])

        if isInsideMarkdownCodeFence(in: text, upTo: cursorIndex) {
            return replacingUTF8Range(
                cursorUTF8Offset..<cursorUTF8Offset,
                in: text,
                with: "\n\(leadingWhitespace(in: lineBeforeCursor))"
            )
        }

        if let blockQuote = markdownBlockQuoteLine(in: currentLine), blockQuote.content.isEmpty {
            return replacingUTF8Range(lineStartUTF8Offset..<lineEndUTF8Offset, in: text, with: "")
        }

        if let listItem = markdownListItemLine(in: currentLine), listItem.content.isEmpty {
            return replacingUTF8Range(lineStartUTF8Offset..<lineEndUTF8Offset, in: text, with: "")
        }

        if let blockQuote = markdownBlockQuoteLine(in: lineBeforeCursor), !blockQuote.content.isEmpty {
            return replacingUTF8Range(
                cursorUTF8Offset..<cursorUTF8Offset,
                in: text,
                with: "\n\(blockQuote.continuationPrefix)"
            )
        }

        if let listItem = markdownListItemLine(in: lineBeforeCursor), !listItem.content.isEmpty {
            return replacingUTF8Range(
                cursorUTF8Offset..<cursorUTF8Offset,
                in: text,
                with: "\n\(listItem.continuationPrefix)"
            )
        }

        return replacingUTF8Range(cursorUTF8Offset..<cursorUTF8Offset, in: text, with: "\n")
    }

    public static func visibleLineRange(
        scrollY: Double,
        viewportHeight: Double,
        lineHeight: Double,
        lineCount: Int,
        overscanLineCount: Int = 2
    ) -> Range<Int> {
        guard lineCount > 0, viewportHeight > 0, lineHeight > 0 else {
            return 0..<0
        }

        let firstLine = min(
            lineCount,
            max(0, Int((max(0, scrollY) / lineHeight).rounded(.down)))
        )
        let visibleLineCount = max(1, Int((viewportHeight / lineHeight).rounded(.up)))
            + max(0, overscanLineCount)
        let endLine = min(lineCount, firstLine + visibleLineCount)

        return firstLine..<endLine
    }

    private static func isInsideCharacter(_ offset: Int, in text: String) -> Bool {
        var currentOffset = 0

        for character in text {
            let nextOffset = currentOffset + String(character).utf8.count
            if currentOffset < offset, offset < nextOffset {
                return true
            }
            currentOffset = nextOffset
        }

        return false
    }

    private static func lineStartIndex(in text: String, before index: String.Index) -> String.Index {
        if let newlineIndex = text[..<index].lastIndex(of: "\n") {
            return text.index(after: newlineIndex)
        }

        return text.startIndex
    }

    private static func lineEndIndex(in text: String, after index: String.Index) -> String.Index {
        text[index...].firstIndex(of: "\n") ?? text.endIndex
    }

    private static func leadingWhitespace(in line: String) -> String {
        let endIndex = line.firstIndex { !isHorizontalWhitespace($0) } ?? line.endIndex
        return String(line[..<endIndex])
    }

    private static func markdownBlockQuoteLine(
        in line: String
    ) -> (continuationPrefix: String, content: String)? {
        var index = line.startIndex
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }

        let indentation = String(line[..<index])
        guard index < line.endIndex, line[index] == ">" else {
            return nil
        }

        index = line.index(after: index)
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }

        return ("\(indentation)> ", String(line[index...]))
    }

    private static func markdownListItemLine(
        in line: String
    ) -> (continuationPrefix: String, content: String)? {
        var index = line.startIndex
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }

        let indentation = String(line[..<index])
        guard index < line.endIndex else {
            return nil
        }

        let marker = line[index]
        if marker == "-" || marker == "*" || marker == "+" {
            index = line.index(after: index)
            guard index == line.endIndex || isHorizontalWhitespace(line[index]) else {
                return nil
            }
            while index < line.endIndex, isHorizontalWhitespace(line[index]) {
                index = line.index(after: index)
            }

            return ("\(indentation)\(marker) ", String(line[index...]))
        }

        guard marker.isNumber else {
            return nil
        }

        let numberStartIndex = index
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }

        guard index < line.endIndex, line[index] == "." || line[index] == ")" else {
            return nil
        }

        let punctuation = line[index]
        let numberText = String(line[numberStartIndex..<index])
        index = line.index(after: index)
        guard index == line.endIndex || isHorizontalWhitespace(line[index]) else {
            return nil
        }
        while index < line.endIndex, isHorizontalWhitespace(line[index]) {
            index = line.index(after: index)
        }

        let nextNumber = (Int(numberText) ?? 0) + 1
        return ("\(indentation)\(nextNumber)\(punctuation) ", String(line[index...]))
    }

    private static func isInsideMarkdownCodeFence(in text: String, upTo cursorIndex: String.Index) -> Bool {
        var isInsideFence = false

        for line in text[..<cursorIndex].split(separator: "\n", omittingEmptySubsequences: false) {
            if isMarkdownFenceLine(String(line)) {
                isInsideFence.toggle()
            }
        }

        return isInsideFence
    }

    private static func isMarkdownFenceLine(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmedLine.first, marker == "`" || marker == "~" else {
            return false
        }

        var markerCount = 0
        for character in trimmedLine {
            guard character == marker else {
                break
            }
            markerCount += 1
        }

        return markerCount >= 3
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}
