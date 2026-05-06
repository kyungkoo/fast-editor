import XCTest
@testable import FastEditorTextEditing

final class TextEditingPrimitivesTests: XCTestCase {
    func testUTF8OffsetsClampToCharacterBoundaries() {
        let text = "a한b"

        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(0, in: text), 0)
        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(1, in: text), 1)
        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(2, in: text), 1)
        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(3, in: text), 1)
        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(4, in: text), 4)
        XCTAssertEqual(TextEditingPrimitives.clampUTF8Offset(99, in: text), 5)
    }

    func testUTF16AndUTF8LocationsRoundTripThroughKoreanText() {
        let text = "a한😀b"

        XCTAssertEqual(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 0), 0)
        XCTAssertEqual(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 1), 1)
        XCTAssertEqual(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 2), 4)
        XCTAssertEqual(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 4), 8)
        XCTAssertEqual(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 5), 9)

        XCTAssertEqual(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 0), 0)
        XCTAssertEqual(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 1), 1)
        XCTAssertEqual(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 4), 2)
        XCTAssertEqual(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 8), 4)
        XCTAssertEqual(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 9), 5)
    }

    func testLineColumnCoordinatesHandleMultibyteCharacters() {
        let text = "one\n한글\nthree"
        let offset = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 2)

        XCTAssertEqual(offset, "one\n한글".utf8.count)
        XCTAssertEqual(TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: offset).line, 1)
        XCTAssertEqual(TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: offset).column, 2)
    }

    func testSelectedRangeNormalizesAnchorAndCursor() {
        let text = "abc한글"
        let anchor = text.utf8.count
        let cursor = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 3)

        let selectedRange = TextEditingPrimitives.selectedUTF8Range(
            anchor: anchor,
            cursor: cursor,
            in: text
        )

        XCTAssertEqual(selectedRange, cursor..<anchor)
        XCTAssertEqual(TextEditingPrimitives.substring(in: text, utf8Range: selectedRange!), "한글")
    }

    func testReplacingUTF8RangePreservesValidCursorAfterKoreanReplacement() {
        let text = "hello 한글 world"
        let start = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 6)
        let end = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 8)

        let result = TextEditingPrimitives.replacingUTF8Range(
            start..<end,
            in: text,
            with: "Swift"
        )

        XCTAssertEqual(result.text, "hello Swift world")
        XCTAssertEqual(result.cursorUTF8Offset, "hello Swift".utf8.count)
    }

    func testReplacingSelectionWithComposedKoreanTextPlacesCursorAfterReplacement() {
        let text = "aㅎb"
        let start = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 1)
        let end = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 2)

        let result = TextEditingPrimitives.replacingUTF8Range(
            start..<end,
            in: text,
            with: "한"
        )

        XCTAssertEqual(result.text, "a한b")
        XCTAssertEqual(result.cursorUTF8Offset, "a한".utf8.count)
    }
}
