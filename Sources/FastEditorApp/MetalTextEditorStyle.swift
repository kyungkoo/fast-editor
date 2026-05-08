import AppKit

struct MetalTextEditorStyle {
    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    let gutterWidth: CGFloat = 56
    let horizontalPadding: CGFloat = 12
    let verticalPadding: CGFloat = 10
    let caretWidth: CGFloat = 1.5

    var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading + 5)
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
    }

    var lineNumberAttributes: [NSAttributedString.Key: Any] {
        [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    func textAttributes(
        for kind: EditorRenderSpanKind,
        defaultAttributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var attributes = defaultAttributes
        attributes[.foregroundColor] = color(for: kind)

        switch kind {
        case .markdownHeading:
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        case .markdownCode, .markdownInlineCode:
            attributes[.backgroundColor] = NSColor.controlBackgroundColor
        case .markdownEmphasis, .kotlinKeyword, .kotlinType, .kotlinFunction,
             .rustKeyword, .rustType, .rustFunction,
             .swiftKeyword, .swiftType, .swiftFunction:
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        default:
            break
        }

        return attributes
    }

    private func color(for kind: EditorRenderSpanKind) -> NSColor {
        switch kind {
        case .markdownHeading:
            return .systemBlue
        case .markdownListMarker:
            return .systemOrange
        case .markdownQuote:
            return .systemGreen
        case .markdownCode, .markdownInlineCode:
            return .systemPurple
        case .markdownLink:
            return .systemBlue
        case .markdownEmphasis:
            return .systemPink
        case .kotlinKeyword:
            return .systemPink
        case .kotlinType:
            return .systemTeal
        case .kotlinFunction:
            return .systemBlue
        case .kotlinString:
            return .systemGreen
        case .kotlinComment:
            return .secondaryLabelColor
        case .kotlinNumber:
            return .systemOrange
        case .kotlinAnnotation:
            return .systemPurple
        case .rustKeyword:
            return .systemPink
        case .rustType:
            return .systemTeal
        case .rustFunction:
            return .systemBlue
        case .rustString:
            return .systemGreen
        case .rustComment:
            return .secondaryLabelColor
        case .rustNumber:
            return .systemOrange
        case .rustAttribute:
            return .systemPurple
        case .swiftKeyword:
            return .systemPink
        case .swiftType:
            return .systemTeal
        case .swiftFunction:
            return .systemBlue
        case .swiftString:
            return .systemGreen
        case .swiftComment:
            return .secondaryLabelColor
        case .swiftNumber:
            return .systemOrange
        case .swiftAttribute:
            return .systemPurple
        }
    }
}
