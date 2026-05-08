import FastEditorModels
import AppKit
import Testing
@testable import FastEditorApp

struct MetalTextLayoutMetricsTests {
    @Test func prefixWidthUsesStyledHeadingSpanWidth() {
        let text = "# Project Design Notes"
        let line = EditorRenderLine(
            index: 0,
            lineNumber: 1,
            text: text,
            spans: [
                EditorRenderSpan(
                    startColumn: 0,
                    endColumn: text.count,
                    kind: .markdownHeading
                )
            ]
        )
        let metrics = makeMetrics(defaultWidth: 10, headingWidth: 16)

        #expect(metrics.prefixWidth(column: text.count, in: line) == CGFloat(text.count * 16))
        #expect(metrics.prefixWidth(column: 3, in: line) == 48)
    }

    @Test func prefixWidthAddsDefaultAndStyledSegments() {
        let text = "abc**bold**z"
        let line = EditorRenderLine(
            index: 0,
            lineNumber: 1,
            text: text,
            spans: [
                EditorRenderSpan(
                    startColumn: 3,
                    endColumn: 11,
                    kind: .markdownEmphasis
                )
            ]
        )
        let metrics = makeMetrics(defaultWidth: 10, emphasisWidth: 14)
        let fullWidth: CGFloat = 152
        let partialWidth: CGFloat = 58

        #expect(metrics.prefixWidth(column: text.count, in: line) == fullWidth)
        #expect(metrics.prefixWidth(column: 5, in: line) == partialWidth)
    }

    @Test func hitTestingUsesStyledSegmentMidpoints() {
        let text = "# 제목"
        let line = EditorRenderLine(
            index: 0,
            lineNumber: 1,
            text: text,
            spans: [
                EditorRenderSpan(
                    startColumn: 0,
                    endColumn: text.count,
                    kind: .markdownHeading
                )
            ]
        )
        let metrics = makeMetrics(defaultWidth: 10, headingWidth: 20)

        #expect(metrics.column(in: line, closestTo: 9) == 0)
        #expect(metrics.column(in: line, closestTo: 11) == 1)
        #expect(metrics.column(in: line, closestTo: 79) == text.count)
    }

    private func makeMetrics(
        defaultWidth: CGFloat,
        headingWidth: CGFloat = 18,
        emphasisWidth: CGFloat = 13
    ) -> MetalTextLayoutMetrics {
        MetalTextLayoutMetrics(
            defaultAttributes: [.font: "default"],
            attributesForSpanKind: { kind, defaultAttributes in
                var attributes = defaultAttributes
                switch kind {
                case .markdownHeading:
                    attributes[.font] = "heading"
                case .markdownEmphasis:
                    attributes[.font] = "emphasis"
                default:
                    break
                }
                return attributes
            },
            measureText: { text, attributes in
                let width: CGFloat
                switch attributes[.font] as? String {
                case "heading":
                    width = headingWidth
                case "emphasis":
                    width = emphasisWidth
                default:
                    width = defaultWidth
                }
                return CGFloat(text.count) * width
            }
        )
    }
}
