import AppKit
import SwiftUI

struct AppKitTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var focusRevision: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.string = text

        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.isEditable = isEditable
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            context.coordinator.isApplyingExternalText = true
            textView.string = text
            textView.setSelectedRange(clamp(selectedRange, to: textView.string))
            context.coordinator.isApplyingExternalText = false
        }

        if isEditable, context.coordinator.lastFocusedRevision != focusRevision {
            context.coordinator.lastFocusedRevision = focusRevision
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func clamp(_ range: NSRange, to text: String) -> NSRange {
        let count = (text as NSString).length
        let location = min(range.location, count)
        let length = min(range.length, count - location)
        return NSRange(location: location, length: length)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var isApplyingExternalText = false
        var lastFocusedRevision = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
        }
    }
}
