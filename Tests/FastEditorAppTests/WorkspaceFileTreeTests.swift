import Foundation
import Testing
@testable import FastEditorApp

struct WorkspaceFileTreeTests {
    @Test func buildsSortedTreeAndSkipsGeneratedDirectories() throws {
        let root = try temporaryDirectory("file-tree")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("target"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try "swift".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "main".write(to: root.appendingPathComponent("Sources/main.swift"), atomically: true, encoding: .utf8)
        try "ignored".write(to: root.appendingPathComponent("target/output.txt"), atomically: true, encoding: .utf8)

        let roots = WorkspaceFileNode.roots(in: root)

        #expect(roots.map(\.name) == ["Sources", "Package.swift"])
        #expect(roots[0].children?.map(\.name) == ["main.swift"])
        #expect(!roots.contains { $0.name == "target" })
        #expect(!roots.contains { $0.name == "node_modules" })
    }

    @Test func handlesEmptyFolders() throws {
        let root = try temporaryDirectory("empty-file-tree")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Empty"), withIntermediateDirectories: true)

        let roots = WorkspaceFileNode.roots(in: root)

        #expect(roots.count == 1)
        #expect(roots[0].name == "Empty")
        #expect(roots[0].isDirectory)
        #expect(roots[0].children == nil)
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fast-editor-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
