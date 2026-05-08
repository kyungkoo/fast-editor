import AppKit

enum MetalTextInputDecoder {
    static func plainText(from insertString: Any) -> String? {
        if let text = insertString as? String {
            return text
        }

        if let attributedText = insertString as? NSAttributedString {
            return attributedText.string
        }

        return nil
    }
}
