import Testing
@testable import FastEditorTextEditing

struct TextEditingPrimitivesTests {
    @Test func utf8OffsetsClampToCharacterBoundaries() {
        let text = "a한b"

        #expect(TextEditingPrimitives.clampUTF8Offset(0, in: text) == 0)
        #expect(TextEditingPrimitives.clampUTF8Offset(1, in: text) == 1)
        #expect(TextEditingPrimitives.clampUTF8Offset(2, in: text) == 1)
        #expect(TextEditingPrimitives.clampUTF8Offset(3, in: text) == 1)
        #expect(TextEditingPrimitives.clampUTF8Offset(4, in: text) == 4)
        #expect(TextEditingPrimitives.clampUTF8Offset(99, in: text) == 5)
    }

    @Test func utf16AndUTF8LocationsRoundTripThroughKoreanText() {
        let text = "a한😀b"

        #expect(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 0) == 0)
        #expect(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 1) == 1)
        #expect(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 2) == 4)
        #expect(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 4) == 8)
        #expect(TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 5) == 9)

        #expect(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 0) == 0)
        #expect(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 1) == 1)
        #expect(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 4) == 2)
        #expect(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 8) == 4)
        #expect(TextEditingPrimitives.utf16Offset(in: text, forUTF8Offset: 9) == 5)
    }

    @Test func lineColumnCoordinatesHandleMultibyteCharacters() {
        let text = "one\n한글\nthree"
        let offset = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 2)
        let position = TextEditingPrimitives.cursorPosition(in: text, forUTF8Offset: offset)

        #expect(offset == "one\n한글".utf8.count)
        #expect(position.line == 1)
        #expect(position.column == 2)
    }

    @Test func selectedRangeNormalizesAnchorAndCursor() throws {
        let text = "abc한글"
        let anchor = text.utf8.count
        let cursor = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 3)

        let selectedRange = try #require(TextEditingPrimitives.selectedUTF8Range(
            anchor: anchor,
            cursor: cursor,
            in: text
        ))

        #expect(selectedRange == cursor..<anchor)
        #expect(TextEditingPrimitives.substring(in: text, utf8Range: selectedRange) == "한글")
    }

    @Test func replacingUTF8RangePreservesValidCursorAfterKoreanReplacement() {
        let text = "hello 한글 world"
        let start = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 6)
        let end = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 8)

        let result = TextEditingPrimitives.replacingUTF8Range(
            start..<end,
            in: text,
            with: "Swift"
        )

        #expect(result.text == "hello Swift world")
        #expect(result.cursorUTF8Offset == "hello Swift".utf8.count)
    }

    @Test func replacingSelectionWithComposedKoreanTextPlacesCursorAfterReplacement() {
        let text = "aㅎb"
        let start = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 1)
        let end = TextEditingPrimitives.utf8Offset(in: text, atUTF16Location: 2)

        let result = TextEditingPrimitives.replacingUTF8Range(
            start..<end,
            in: text,
            with: "한"
        )

        #expect(result.text == "a한b")
        #expect(result.cursorUTF8Offset == "a한".utf8.count)
    }

    @Test func visibleLineRangeTracksScrolledViewportWithOverscan() {
        let range = TextEditingPrimitives.visibleLineRange(
            scrollY: 45,
            viewportHeight: 60,
            lineHeight: 20,
            lineCount: 20
        )

        #expect(range == 2..<7)
    }

    @Test func visibleLineRangeClampsInvalidAndOverscrolledInputs() {
        #expect(TextEditingPrimitives.visibleLineRange(
            scrollY: 0,
            viewportHeight: 0,
            lineHeight: 20,
            lineCount: 20
        ) == 0..<0)

        #expect(TextEditingPrimitives.visibleLineRange(
            scrollY: 10_000,
            viewportHeight: 60,
            lineHeight: 20,
            lineCount: 20
        ) == 20..<20)
    }
}
