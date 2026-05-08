import FastEditorModels
import AppKit

struct MetalTextLayoutMetrics {
    typealias AttributeResolver = (
        EditorRenderSpanKind,
        [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any]
    typealias TextMeasurer = (String, [NSAttributedString.Key: Any]) -> CGFloat

    var defaultAttributes: [NSAttributedString.Key: Any]
    var attributesForSpanKind: AttributeResolver
    var measureText: TextMeasurer

    init(
        defaultAttributes: [NSAttributedString.Key: Any],
        attributesForSpanKind: @escaping AttributeResolver,
        measureText: @escaping TextMeasurer = MetalTextLayoutMetrics.defaultMeasureText
    ) {
        self.defaultAttributes = defaultAttributes
        self.attributesForSpanKind = attributesForSpanKind
        self.measureText = measureText
    }

    func prefixWidth(column: Int, in line: EditorRenderLine?) -> CGFloat {
        guard let line else {
            return 0
        }

        let characters = Array(line.text)
        let targetColumn = min(max(0, column), characters.count)
        var currentColumn = 0
        var measuredWidth = CGFloat.zero

        for span in line.spans.sorted(by: { $0.startColumn < $1.startColumn }) {
            let startColumn = min(max(span.startColumn, currentColumn), characters.count)
            let endColumn = min(max(span.endColumn, startColumn), characters.count)

            if currentColumn < startColumn {
                let segmentEnd = min(startColumn, targetColumn)
                if currentColumn < segmentEnd {
                    measuredWidth += width(
                        of: String(characters[currentColumn..<segmentEnd]),
                        attributes: defaultAttributes
                    )
                }
                if targetColumn <= startColumn {
                    return measuredWidth
                }
                currentColumn = startColumn
            }

            if currentColumn < endColumn {
                let segmentEnd = min(endColumn, targetColumn)
                if currentColumn < segmentEnd {
                    measuredWidth += width(
                        of: String(characters[currentColumn..<segmentEnd]),
                        attributes: attributesForSpanKind(span.kind, defaultAttributes)
                    )
                }
                if targetColumn <= endColumn {
                    return measuredWidth
                }
            }

            currentColumn = endColumn
        }

        if currentColumn < targetColumn {
            measuredWidth += width(
                of: String(characters[currentColumn..<targetColumn]),
                attributes: defaultAttributes
            )
        }

        return measuredWidth
    }

    func column(in line: EditorRenderLine?, closestTo x: CGFloat) -> Int {
        guard x > 0 else {
            return 0
        }

        var lastWidth = CGFloat.zero

        for index in 0..<(line?.text.count ?? 0) {
            let nextWidth = prefixWidth(column: index + 1, in: line)
            if x < (lastWidth + nextWidth) / 2 {
                return index
            }
            lastWidth = nextWidth
        }

        return line?.text.count ?? 0
    }

    func width(of text: String) -> CGFloat {
        width(of: text, attributes: defaultAttributes)
    }

    func width(
        of text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        measureText(text, attributes)
    }

    private static func defaultMeasureText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }
}
