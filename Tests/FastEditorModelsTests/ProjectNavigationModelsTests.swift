import Foundation
import Testing
@testable import FastEditorModels

struct ProjectNavigationModelsTests {
    @Test func quickOpenRanksOpenAndRecentFilesAheadOfColdMatches() throws {
        let root = try temporaryDirectory("quick-open")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let sources = root.appendingPathComponent("Sources")
        let tests = root.appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let app = sources.appendingPathComponent("AppCoordinator.swift")
        let test = tests.appendingPathComponent("AppCoordinatorTests.swift")
        try "app".write(to: app, atomically: true, encoding: .utf8)
        try "test".write(to: test, atomically: true, encoding: .utf8)

        let candidates = QuickOpenMatcher.candidates(in: root)
        let results = QuickOpenMatcher.results(
            query: "app",
            candidates: candidates,
            openFileURLs: [test],
            recentFileURLs: [app],
            limit: 10
        )

        #expect(results.count == 2)
        #expect(results[0].fileURL == test.standardizedFileURL)
        #expect(results[1].fileURL == app.standardizedFileURL)
    }

    @Test func quickOpenUsesFuzzySubsequenceMatching() {
        let candidate = QuickOpenCandidate(
            fileURL: URL(fileURLWithPath: "/tmp/Sources/EditorCoreBridge.swift"),
            displayPath: "Sources/EditorCoreBridge.swift"
        )

        let results = QuickOpenMatcher.results(
            query: "ecb",
            candidates: [candidate],
            openFileURLs: [],
            recentFileURLs: []
        )

        #expect(results.map(\.displayPath) == ["Sources/EditorCoreBridge.swift"])
    }

    @Test func navigationHistoryMovesBackAndForward() {
        let first = NavigationLocation(fileURL: URL(fileURLWithPath: "/tmp/one.swift"), line: 1, column: 2)
        let second = NavigationLocation(fileURL: URL(fileURLWithPath: "/tmp/two.swift"), line: 3, column: 4)
        var history = EditorNavigationHistory()

        history.visit(first)
        history.visit(second)

        #expect(history.canGoBack)
        #expect(history.goBack() == first)
        #expect(history.canGoForward)
        #expect(history.goForward() == second)
    }

    @Test func queryExtractionUsesSelectionThenCurrentWord() {
        let text = "let selectedSymbol = currentSymbol"
        let selectedRange = text.range(of: "selectedSymbol")!
        let lowerBound = text[..<selectedRange.lowerBound].utf8.count
        let upperBound = text[..<selectedRange.upperBound].utf8.count

        #expect(TextQueryExtraction.query(
            in: text,
            selectedRange: lowerBound..<upperBound,
            cursorUTF8Offset: 0
        ) == "selectedSymbol")

        let cursorOffset = text.range(of: "currentSymbol").map { text[..<$0.lowerBound].utf8.count + 3 }!
        #expect(TextQueryExtraction.query(
            in: text,
            selectedRange: nil,
            cursorUTF8Offset: cursorOffset
        ) == "currentSymbol")
    }

    @Test func workspaceReferenceSearchUsesWorkspaceTextSearchContract() throws {
        let root = try temporaryDirectory("references")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try "func target() {}\ntarget()\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )

        let results = WorkspaceReferenceSearch.search(query: "target", workspaceURL: root)

        #expect(results.count == 2)
        #expect(results[0].displayPath == "Sources/App.swift")
        #expect(results[0].query == "target")
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fast-editor-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
