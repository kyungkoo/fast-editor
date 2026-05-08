import Foundation
import Testing
@testable import FastEditorModels

struct EditorSearchModelsTests {
    @Test func textSearchFindsMultibyteMatchesWithUTF8Ranges() {
        let text = "alpha\n한글 beta\nBeta again"

        let matches = TextSearch.matches(in: text, query: "beta")

        #expect(matches.count == 2)
        #expect(matches[0].line == 1)
        #expect(matches[0].column == 3)
        #expect(matches[0].range == 13..<17)
        #expect(matches[0].linePreview == "한글 beta")
        #expect(matches[1].line == 2)
        #expect(matches[1].column == 0)
    }

    @Test func textSearchHandlesEmptyAndNoMatchQueries() {
        #expect(TextSearch.matches(in: "hello", query: "").isEmpty)
        #expect(TextSearch.matches(in: "hello", query: "world").isEmpty)
    }

    @Test func workspaceSearchSkipsIgnoredDirectoriesAndReportsRelativeLocations() throws {
        let root = try temporaryDirectory("workspace-search")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target"), withIntermediateDirectories: true)
        try "let value = 1\nlet targetValue = 2\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "targetValue".write(
            to: root.appendingPathComponent("target/generated.swift"),
            atomically: true,
            encoding: .utf8
        )

        let results = WorkspaceTextSearch.search(query: "target", workspaceURL: root)

        #expect(results.count == 1)
        #expect(results[0].displayPath == "Sources/App.swift")
        #expect(results[0].line == 1)
        #expect(results[0].column == 4)
        #expect(results[0].preview == "let targetValue = 2")
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fast-editor-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
