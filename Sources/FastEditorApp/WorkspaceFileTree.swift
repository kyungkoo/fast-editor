import Foundation

struct WorkspaceFileNode: Identifiable, Equatable {
    var url: URL
    var name: String
    var isDirectory: Bool
    var children: [WorkspaceFileNode]?

    var id: String {
        url.path
    }

    static func roots(in workspaceURL: URL) -> [WorkspaceFileNode] {
        children(in: workspaceURL)
    }

    private static func node(for url: URL) -> WorkspaceFileNode? {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let isDirectory = resourceValues?.isDirectory == true
        let isRegularFile = resourceValues?.isRegularFile == true

        guard isDirectory || isRegularFile else {
            return nil
        }

        if isDirectory, ignoredDirectoryNames.contains(url.lastPathComponent) {
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
