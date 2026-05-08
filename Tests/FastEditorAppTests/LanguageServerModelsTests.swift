import Foundation
import Testing
@testable import FastEditorApp

struct LanguageServerModelsTests {
    @Test func detectsAvailableLanguageServersFromPath() {
        let providers = LanguageServerDetector.detect(
            environment: ["PATH": "/bin:/toolchain/bin"],
            fileExists: { path in
                path == "/toolchain/bin/rust-analyzer"
            }
        )

        #expect(providers.first { $0.id == .rustAnalyzer }?.executablePath == "/toolchain/bin/rust-analyzer")
        #expect(providers.first { $0.id == .sourceKitLSP }?.available == false)
    }

    @Test func detectsSourceKitLSPThroughXcrunFallback() throws {
        let providers = LanguageServerDetector.detect(
            environment: ["PATH": "/bin"],
            fileExists: { path in
                path == "/usr/bin/xcrun"
            }
        )
        let sourceKit = try #require(providers.first { $0.id == .sourceKitLSP })

        #expect(sourceKit.executablePath == "/usr/bin/xcrun")
        #expect(sourceKit.arguments == ["sourcekit-lsp"])
    }

    @Test func documentEventsExposeLSPNotificationPayloads() throws {
        let event = LanguageServerDocumentEvent.didOpen(
            uri: "file:///tmp/App.swift",
            languageID: "swift",
            version: 3,
            text: "let value = 1"
        )

        let textDocument = try #require(event.payload["textDocument"] as? [String: Any])

        #expect(event.method == "textDocument/didOpen")
        #expect(textDocument["uri"] as? String == "file:///tmp/App.swift")
        #expect(textDocument["languageId"] as? String == "swift")
        #expect(textDocument["version"] as? Int == 3)
        #expect(textDocument["text"] as? String == "let value = 1")
    }

    @Test func parsesPublishDiagnosticsPayload() throws {
        let payload = """
        {
          "jsonrpc": "2.0",
          "method": "textDocument/publishDiagnostics",
          "params": {
            "uri": "file:///tmp/App.swift",
            "diagnostics": [
              {
                "range": {
                  "start": { "line": 4, "character": 2 },
                  "end": { "line": 4, "character": 7 }
                },
                "severity": 1,
                "message": "cannot find value"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let diagnostics = LanguageServerDiagnosticsParser.diagnostics(from: payload)

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].fileURL.path == "/tmp/App.swift")
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].line == 4)
        #expect(diagnostics[0].column == 2)
        #expect(diagnostics[0].message == "cannot find value")
    }

    @Test func lspMessageFramerHandlesSplitContentLengthFrames() {
        let body = #"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file:///tmp/App.swift","diagnostics":[]}}"#
        let frame = "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
        var framer = LanguageServerMessageFramer()

        let prefix = Data(frame.prefix(20).utf8)
        let suffix = Data(frame.dropFirst(20).utf8)

        #expect(framer.append(prefix).isEmpty)
        let messages = framer.append(suffix)

        #expect(messages.count == 1)
        #expect(String(decoding: messages[0], as: UTF8.self) == body)
    }
}
