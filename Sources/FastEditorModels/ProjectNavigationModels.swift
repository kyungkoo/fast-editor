import Foundation
import FastEditorTextEditing

public struct EditorScrollPosition: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = EditorScrollPosition(x: 0, y: 0)
}

public struct NavigationLocation: Equatable, Sendable {
    public var fileURL: URL
    public var line: Int
    public var column: Int
    public var scrollPosition: EditorScrollPosition

    public init(
        fileURL: URL,
        line: Int,
        column: Int,
        scrollPosition: EditorScrollPosition = .zero
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.line = max(0, line)
        self.column = max(0, column)
        self.scrollPosition = scrollPosition
    }

    public var displayLocation: String {
        "\(fileURL.lastPathComponent):\(line + 1):\(column + 1)"
    }
}

public struct EditorNavigationHistory: Equatable, Sendable {
    public private(set) var current: NavigationLocation?
    public private(set) var backStack: [NavigationLocation]
    public private(set) var forwardStack: [NavigationLocation]

    public init(
        current: NavigationLocation? = nil,
        backStack: [NavigationLocation] = [],
        forwardStack: [NavigationLocation] = []
    ) {
        self.current = current
        self.backStack = backStack
        self.forwardStack = forwardStack
    }

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public mutating func visit(_ location: NavigationLocation) {
        if let current, current != location {
            backStack.append(current)
        }

        current = location
        forwardStack.removeAll()
    }

    public mutating func replaceCurrent(_ location: NavigationLocation?) {
        current = location
    }

    public mutating func goBack() -> NavigationLocation? {
        guard let previous = backStack.popLast() else {
            return nil
        }

        if let current {
            forwardStack.append(current)
        }

        current = previous
        return previous
    }

    public mutating func goForward() -> NavigationLocation? {
        guard let next = forwardStack.popLast() else {
            return nil
        }

        if let current {
            backStack.append(current)
        }

        current = next
        return next
    }
}

public struct QuickOpenCandidate: Identifiable, Equatable, Sendable {
    public var fileURL: URL
    public var displayPath: String

    public init(fileURL: URL, displayPath: String) {
        self.fileURL = fileURL.standardizedFileURL
        self.displayPath = displayPath
    }

    public var id: String {
        fileURL.path
    }

    public var fileName: String {
        fileURL.lastPathComponent
    }
}

public struct QuickOpenResult: Identifiable, Equatable, Sendable {
    public var candidate: QuickOpenCandidate
    public var score: Int

    public init(candidate: QuickOpenCandidate, score: Int) {
        self.candidate = candidate
        self.score = score
    }

    public var id: String {
        candidate.id
    }

    public var fileURL: URL {
        candidate.fileURL
    }

    public var fileName: String {
        candidate.fileName
    }

    public var displayPath: String {
        candidate.displayPath
    }
}

public enum QuickOpenMatcher {
    public static let defaultLimit = 80

    public static func candidates(in workspaceURL: URL) -> [QuickOpenCandidate] {
        WorkspaceFileNode.searchableFileURLs(in: workspaceURL).map { fileURL in
            QuickOpenCandidate(
                fileURL: fileURL,
                displayPath: displayPath(for: fileURL, relativeTo: workspaceURL)
            )
        }
    }

    public static func results(
        query: String,
        candidates: [QuickOpenCandidate],
        openFileURLs: [URL],
        recentFileURLs: [URL],
        limit: Int = defaultLimit
    ) -> [QuickOpenResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let openPaths = Set(openFileURLs.map { $0.standardizedFileURL.path })
        let recentRanks = Dictionary(
            uniqueKeysWithValues: recentFileURLs.enumerated().map { offset, url in
                (url.standardizedFileURL.path, recentFileURLs.count - offset)
            }
        )

        return candidates.compactMap { candidate -> QuickOpenResult? in
            let score: Int
            if normalizedQuery.isEmpty {
                score = 0
            } else if let fuzzyScore = fuzzyScore(query: normalizedQuery, candidate: candidate) {
                score = fuzzyScore
            } else {
                return nil
            }

            let path = candidate.fileURL.path
            let openBoost = openPaths.contains(path) ? 2_000 : 0
            let recentBoost = (recentRanks[path] ?? 0) * 100
            return QuickOpenResult(candidate: candidate, score: score + openBoost + recentBoost)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            return lhs.displayPath.localizedCaseInsensitiveCompare(rhs.displayPath) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    private static func fuzzyScore(query: String, candidate: QuickOpenCandidate) -> Int? {
        let path = candidate.displayPath.lowercased()
        let fileName = candidate.fileName.lowercased()
        guard let pathScore = subsequenceScore(query: query, text: path) else {
            return nil
        }

        var score = pathScore
        if fileName == query {
            score += 1_000
        } else if fileName.hasPrefix(query) {
            score += 700
        } else if fileName.contains(query) {
            score += 450
        } else if path.contains(query) {
            score += 250
        }

        score += max(0, 120 - candidate.displayPath.count)
        return score
    }

    private static func subsequenceScore(query: String, text: String) -> Int? {
        var score = 0
        var textIndex = text.startIndex
        var previousMatchIndex: String.Index?

        for queryCharacter in query {
            guard let matchIndex = text[textIndex...].firstIndex(of: queryCharacter) else {
                return nil
            }

            if matchIndex == text.startIndex || text[text.index(before: matchIndex)] == "/" {
                score += 80
            } else if let previousMatchIndex, text.index(after: previousMatchIndex) == matchIndex {
                score += 45
            } else {
                score += 10
            }

            previousMatchIndex = matchIndex
            textIndex = text.index(after: matchIndex)
        }

        return score
    }

    private static func displayPath(for fileURL: URL, relativeTo workspaceURL: URL) -> String {
        let workspacePath = workspaceURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(workspacePath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(filePath.dropFirst(workspacePath.count + 1))
    }
}

public struct WorkspaceReferenceResult: Identifiable, Equatable, Sendable {
    public var fileURL: URL
    public var displayPath: String
    public var line: Int
    public var column: Int
    public var preview: String
    public var query: String

    public init(
        fileURL: URL,
        displayPath: String,
        line: Int,
        column: Int,
        preview: String,
        query: String
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.displayPath = displayPath
        self.line = line
        self.column = column
        self.preview = preview
        self.query = query
    }

    public var id: String {
        "\(fileURL.path):\(line):\(column):\(query)"
    }

    public var displayLocation: String {
        "\(displayPath):\(line + 1):\(column + 1)"
    }
}

public enum WorkspaceReferenceSearch {
    public static func search(query: String, workspaceURL: URL) -> [WorkspaceReferenceResult] {
        WorkspaceTextSearch.search(query: query, workspaceURL: workspaceURL).map { result in
            WorkspaceReferenceResult(
                fileURL: result.fileURL,
                displayPath: result.displayPath,
                line: result.line,
                column: result.column,
                preview: result.preview,
                query: query
            )
        }
    }
}

public enum TextQueryExtraction {
    public static func query(
        in text: String,
        selectedRange: Range<Int>?,
        cursorUTF8Offset: Int
    ) -> String? {
        if let selectedRange {
            let selectedText = TextEditingPrimitives.substring(in: text, utf8Range: selectedRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedText.isEmpty {
                return selectedText
            }
        }

        guard let wordRange = wordRange(in: text, cursorUTF8Offset: cursorUTF8Offset) else {
            return nil
        }

        let word = TextEditingPrimitives.substring(in: text, utf8Range: wordRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return word.isEmpty ? nil : word
    }

    public static func wordRange(in text: String, cursorUTF8Offset: Int) -> Range<Int>? {
        guard !text.isEmpty else {
            return nil
        }

        var index = TextEditingPrimitives.stringIndex(in: text, atUTF8Offset: cursorUTF8Offset)
        if index == text.endIndex, index > text.startIndex {
            index = text.index(before: index)
        } else if index < text.endIndex, !isWordCharacter(text[index]), index > text.startIndex {
            let previous = text.index(before: index)
            if isWordCharacter(text[previous]) {
                index = previous
            }
        }

        guard index < text.endIndex, isWordCharacter(text[index]) else {
            return nil
        }

        var lowerBound = index
        while lowerBound > text.startIndex {
            let previous = text.index(before: lowerBound)
            guard isWordCharacter(text[previous]) else {
                break
            }
            lowerBound = previous
        }

        var upperBound = text.index(after: index)
        while upperBound < text.endIndex, isWordCharacter(text[upperBound]) {
            upperBound = text.index(after: upperBound)
        }

        return text[..<lowerBound].utf8.count..<text[..<upperBound].utf8.count
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}
