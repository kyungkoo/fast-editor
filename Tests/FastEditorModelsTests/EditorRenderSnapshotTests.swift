import Foundation
import Testing
@testable import FastEditorModels

struct EditorRenderSnapshotTests {
    @Test func decodesTreeSitterLanguagesAndSpanKinds() throws {
        let payload = """
        {
          "buffer_id": 7,
          "dirty": true,
          "language": "swift",
          "cursor_line": 1,
          "cursor_column": 4,
          "lines": [
            {
              "index": 0,
              "line_number": 1,
              "text": "func count() -> Int",
              "spans": [
                {
                  "start_column": 0,
                  "end_column": 4,
                  "kind": "swift_keyword"
                },
                {
                  "start_column": 5,
                  "end_column": 10,
                  "kind": "swift_function"
                },
                {
                  "start_column": 16,
                  "end_column": 19,
                  "kind": "swift_type"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(EditorRenderSnapshot.self, from: payload)

        #expect(snapshot.bufferID == 7)
        #expect(snapshot.dirty)
        #expect(snapshot.language == .swift)
        #expect(snapshot.cursorLine == 1)
        #expect(snapshot.cursorColumn == 4)
        #expect(snapshot.lines[0].spans.map(\.kind) == [
            .swiftKeyword,
            .swiftFunction,
            .swiftType
        ])
    }

    @Test func decodesKotlinAndRustSpanKinds() throws {
        let payload = """
        {
          "buffer_id": 8,
          "dirty": false,
          "language": "kotlin",
          "cursor_line": 0,
          "cursor_column": 0,
          "lines": [
            {
              "index": 0,
              "line_number": 1,
              "text": "fun count(): Int",
              "spans": [
                {
                  "start_column": 0,
                  "end_column": 3,
                  "kind": "kotlin_keyword"
                },
                {
                  "start_column": 4,
                  "end_column": 9,
                  "kind": "kotlin_function"
                },
                {
                  "start_column": 13,
                  "end_column": 16,
                  "kind": "rust_type"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(EditorRenderSnapshot.self, from: payload)

        #expect(snapshot.language == .kotlin)
        #expect(snapshot.lines[0].spans.map(\.kind) == [
            .kotlinKeyword,
            .kotlinFunction,
            .rustType
        ])
    }
}
