import Testing
@testable import FastEditorApp

struct AgentDiffPreviewTests {
    @Test func extractsReplacementBlockFromTranscript() {
        let transcript = """
        Here is a proposed edit:

        ```fast-editor-replacement
        let value = 2
        ```
        """

        let edit = AgentDiffPreview.extractProposedEdit(from: transcript)

        #expect(edit?.replacementText == "let value = 2")
    }

    @Test func rendersSimpleUnifiedPreview() {
        let preview = AgentDiffPreview.unifiedPreview(
            original: "let value = 1\nprint(value)",
            replacement: "let value = 2\nprint(value)",
            path: "Example.swift"
        )

        #expect(preview.contains("--- Example.swift"))
        #expect(preview.contains("+++ Example.swift"))
        #expect(preview.contains("- let value = 1"))
        #expect(preview.contains("+ let value = 2"))
        #expect(preview.contains("  print(value)"))
    }
}
