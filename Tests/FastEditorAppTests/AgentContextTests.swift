import Foundation
import Testing
import FastEditorTextEditing
@testable import FastEditorApp

struct AgentContextTests {
    @Test func fullFileContextUsesCompleteTextWhenNoSelectionExists() {
        let context = AgentContext.currentFile(
            fileURL: URL(fileURLWithPath: "/tmp/Example.swift"),
            text: "let value = 1",
            selectedRange: nil
        )

        #expect(context.text == "let value = 1")
        #expect(context.selection == nil)
        #expect(context.transcriptSummary == "Context: full file /tmp/Example.swift")
    }

    @Test func selectionContextIncludesSelectedTextAndRangeMetadata() throws {
        let text = "one\ntwo\nthree"
        let start = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 0)
        let end = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 3)

        let context = AgentContext.currentFile(
            fileURL: URL(fileURLWithPath: "/tmp/Example.md"),
            text: text,
            selectedRange: start..<end
        )
        let selection = try #require(context.selection)

        #expect(context.text == "two")
        #expect(selection.displayRange == "2:1-2:4")
        #expect(selection.utf8Range == start..<end)
        #expect(context.transcriptSummary.contains("Context: selection /tmp/Example.md:2:1-2:4"))
    }

    @MainActor
    @Test func agentRequestExplainsSelectionScopeAndEditContract() {
        let text = "one\ntwo\nthree"
        let start = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 0)
        let end = TextEditingPrimitives.utf8Offset(in: text, line: 1, column: 3)
        let context = AgentContext.currentFile(
            fileURL: URL(fileURLWithPath: "/tmp/Example.md"),
            text: text,
            selectedRange: start..<end
        )

        let request = AgentPanelModel.buildRequest(context: context, prompt: "Make it louder.")

        #expect(request.contains("Context scope: selected text"))
        #expect(request.contains("Selected range: 2:1-2:4"))
        #expect(request.contains("replacement text for the selected range"))
        #expect(request.contains("```text\ntwo\n```"))
        #expect(!request.contains("three"))
    }
}
