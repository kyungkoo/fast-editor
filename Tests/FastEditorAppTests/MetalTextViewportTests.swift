import CoreGraphics
import Testing
@testable import FastEditorApp

struct MetalTextViewportTests {
    @Test func recalculatesContentSizeAndClampsScrollOffset() {
        let style = MetalTextEditorStyle()
        let snapshot = EditorRenderSnapshot(
            bufferID: 1,
            dirty: false,
            language: .plainText,
            cursorLine: 0,
            cursorColumn: 0,
            lines: [
                EditorRenderLine(index: 0, lineNumber: 1, text: "short", spans: []),
                EditorRenderLine(index: 1, lineNumber: 2, text: "longer line", spans: [])
            ]
        )
        let metrics = MetalTextLayoutMetrics(
            defaultAttributes: [:],
            attributesForSpanKind: { _, attributes in attributes },
            measureText: { text, _ in CGFloat(text.count * 10) }
        )
        var viewport = MetalTextViewport()

        viewport.recalculateContentSize(
            snapshot: snapshot,
            layoutMetrics: metrics,
            style: style
        )

        #expect(viewport.contentSize.width == style.gutterWidth + style.horizontalPadding * 2 + 110)
        #expect(viewport.contentSize.height == style.verticalPadding * 2 + style.lineHeight * 2)

        viewport.scrollOffset = CGPoint(x: 1_000, y: 1_000)
        viewport.clamp(to: CGRect(x: 0, y: 0, width: 120, height: style.lineHeight))

        #expect(viewport.scrollOffset.x == viewport.contentSize.width - 120)
        #expect(viewport.scrollOffset.y == viewport.contentSize.height - style.lineHeight)
    }
}
