import Foundation

public struct WorkspaceFileNode: Identifiable, Equatable, Sendable {
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var children: [WorkspaceFileNode]?

    public var id: String {
        url.path
    }

    public static func roots(in workspaceURL: URL) -> [WorkspaceFileNode] {
        children(in: workspaceURL)
    }

    public static func searchableFileURLs(in workspaceURL: URL) -> [URL] {
        children(in: workspaceURL)
            .flatMap(\.searchableFileURLs)
    }

    public static func isIgnoredDirectoryName(_ name: String) -> Bool {
        ignoredDirectoryNames.contains(name)
    }

    private var searchableFileURLs: [URL] {
        if isDirectory {
            return children?.flatMap(\.searchableFileURLs) ?? []
        }

        return [url]
    }

    private static func node(for url: URL) -> WorkspaceFileNode? {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let isDirectory = resourceValues?.isDirectory == true
        let isRegularFile = resourceValues?.isRegularFile == true

        guard isDirectory || isRegularFile else {
            return nil
        }

        if isDirectory, isIgnoredDirectoryName(url.lastPathComponent) {
            return nil
        }

        let children = isDirectory ? Self.children(in: url) : nil
        return WorkspaceFileNode(
            url: url.standardizedFileURL,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            children: children?.isEmpty == true ? nil : children
        )
    }

    private static func children(in directoryURL: URL) -> [WorkspaceFileNode] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .compactMap(node)
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".gradle",
        "build",
        "node_modules",
        "target",
    ]
}
