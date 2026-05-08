import Foundation
import Testing
@testable import FastEditorApp

struct AgentProviderTests {
    @Test func decodesProviderDetectionPayload() throws {
        let payload = """
        [
          {
            "id": "codex",
            "display_name": "Codex",
            "executable_path": "/opt/homebrew/bin/codex",
            "available": true
          },
          {
            "id": "gemini",
            "display_name": "Gemini",
            "executable_path": null,
            "available": false
          }
        ]
        """.data(using: .utf8)!

        let providers = try JSONDecoder().decode([AgentProvider].self, from: payload)

        #expect(providers[0].id == .codex)
        #expect(providers[0].displayName == "Codex")
        #expect(providers[0].executablePath == "/opt/homebrew/bin/codex")
        #expect(providers[0].available)
        #expect(providers[1].id == .gemini)
        #expect(providers[1].executablePath == nil)
        #expect(!providers[1].available)
    }
}
