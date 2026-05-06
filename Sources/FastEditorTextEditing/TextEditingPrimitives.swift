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
}
