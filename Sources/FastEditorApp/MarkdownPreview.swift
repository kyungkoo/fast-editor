import AppKit
import SwiftUI

struct MarkdownPreview: NSViewRepresentable {
    var html: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.lastHTML != html,
              let textView = context.coordinator.textView
        else {
            return
        }

        context.coordinator.lastHTML = html
        textView.textStorage?.setAttributedString(attributedPreview(from: html))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func attributedPreview(from html: String) -> NSAttributedString {
        guard let data = html.data(using: .utf8),
              let attributedString = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              )
        else {
            return NSAttributedString(string: "")
        }

        return attributedString
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastHTML = ""
    }
}
