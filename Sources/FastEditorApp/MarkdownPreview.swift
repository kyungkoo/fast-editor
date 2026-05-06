import SwiftUI
import WebKit

struct MarkdownPreview: NSViewRepresentable {
    var html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else {
            return
        }

        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(loadedHTML: html)
    }

    final class Coordinator {
        var loadedHTML: String

        init(loadedHTML: String) {
            self.loadedHTML = loadedHTML
        }
    }
}
