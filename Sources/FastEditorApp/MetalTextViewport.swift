import FastEditorModels
import CoreGraphics
import FastEditorTextEditing

struct MetalTextViewport {
    var scrollOffset = CGPoint.zero
    private(set) var contentSize = CGSize.zero

    mutating func recalculateContentSize(
        snapshot: EditorRenderSnapshot,
        layoutMetrics: MetalTextLayoutMetrics,
        style: MetalTextEditorStyle
    ) {
        let longestLineWidth = snapshot.lines.reduce(CGFloat.zero) { longestWidth, line in
            max(longestWidth, layoutMetrics.prefixWidth(column: line.text.count, in: line))
        }

        contentSize = CGSize(
            width: style.gutterWidth + style.horizontalPadding * 2 + longestLineWidth,
            height: style.verticalPadding * 2 + CGFloat(max(snapshot.lines.count, 1)) * style.lineHeight
        )
    }

    mutating func clamp(to bounds: CGRect) {
        let maxX = max(0, contentSize.width - bounds.width)
        let maxY = max(0, contentSize.height - bounds.height)

        scrollOffset.x = min(max(0, scrollOffset.x), maxX)
        scrollOffset.y = min(max(0, scrollOffset.y), maxY)
    }

    func visibleLineRange(
        lineHeight: CGFloat,
        lineCount: Int,
        viewportHeight: CGFloat
    ) -> Range<Int> {
        TextEditingPrimitives.visibleLineRange(
            scrollY: Double(scrollOffset.y),
            viewportHeight: Double(viewportHeight),
            lineHeight: Double(lineHeight),
            lineCount: lineCount
        )
    }
}
