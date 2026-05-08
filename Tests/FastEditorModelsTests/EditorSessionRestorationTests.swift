import Foundation
import Testing
@testable import FastEditorModels

struct EditorSessionRestorationTests {
    @Test func restorationStateRoundTripsThroughJSON() throws {
        let state = EditorSessionRestorationState(
            workspacePath: "/workspace",
            currentFilePath: "/workspace/Sources/App.swift",
            openFiles: [
                EditorSessionFileState(
                    path: "/workspace/Sources/App.swift",
                    line: 10,
                    column: 4,
                    scrollX: 12,
                    scrollY: 120,
                    selectionLowerUTF8Offset: 20,
                    selectionUpperUTF8Offset: 28
                )
            ],
            recentFilePaths: ["/workspace/Sources/App.swift", "/workspace/README.md"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EditorSessionRestorationState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.openFiles[0].selectedUTF8Range == 20..<28)
        #expect(decoded.openFiles[0].scrollPosition == EditorScrollPosition(x: 12, y: 120))
    }

    @Test func fileStateClampsInvalidPositionsAndIgnoresEmptySelections() {
        let state = EditorSessionFileState(
            path: "/tmp/file.swift",
            line: -1,
            column: -2,
            scrollX: -10,
            scrollY: -20,
            selectionLowerUTF8Offset: 8,
            selectionUpperUTF8Offset: 8
        )

        #expect(state.line == 0)
        #expect(state.column == 0)
        #expect(state.scrollPosition == .zero)
        #expect(state.selectedUTF8Range == nil)
    }
}
