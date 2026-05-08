import Foundation

public enum LanguageServerID: String, CaseIterable, Equatable, Sendable {
    case sourceKitLSP = "sourcekit-lsp"
    case rustAnalyzer = "rust-analyzer"
    case kotlinLanguageServer = "kotlin-language-server"

    public var displayName: String {
        switch self {
        case .sourceKitLSP:
            "SourceKit-LSP"
        case .rustAnalyzer:
            "rust-analyzer"
        case .kotlinLanguageServer:
            "Kotlin Language Server"
        }
    }

    public var supportedExtensions: Set<String> {
        switch self {
        case .sourceKitLSP:
            ["swift"]
        case .rustAnalyzer:
            ["rs"]
        case .kotlinLanguageServer:
            ["kt", "kts"]
        }
    }

    public var commandName: String {
        rawValue
    }
}

public struct LanguageServerProvider: Identifiable, Equatable, Sendable {
    public var id: LanguageServerID
    public var executablePath: String?
    public var arguments: [String] = []

    public var displayName: String {
        id.displayName
    }

    public var available: Bool {
        executablePath != nil
    }
}

public enum LanguageServerDetector {
    public static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> [LanguageServerProvider] {
        LanguageServerID.allCases.map { id in
            provider(for: id, environment: environment, fileExists: fileExists)
        }
    }

    private static func provider(
        for id: LanguageServerID,
        environment: [String: String],
        fileExists: (String) -> Bool
    ) -> LanguageServerProvider {
        if id == .sourceKitLSP,
           fileExists("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp") {
            return LanguageServerProvider(
                id: id,
                executablePath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp"
            )
        }

        if let path = searchPath(environment: environment, commandName: id.commandName, fileExists: fileExists) {
            return LanguageServerProvider(id: id, executablePath: path)
        }

        if id == .sourceKitLSP, fileExists("/usr/bin/xcrun") {
            return LanguageServerProvider(id: id, executablePath: "/usr/bin/xcrun", arguments: ["sourcekit-lsp"])
        }

        return LanguageServerProvider(id: id, executablePath: nil)
    }

    private static func searchPath(
        environment: [String: String],
        commandName: String,
        fileExists: (String) -> Bool
    ) -> String? {
        let paths = environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        for path in paths {
            let candidate = URL(fileURLWithPath: path)
                .appendingPathComponent(commandName)
                .path
            if fileExists(candidate) {
                return candidate
            }
        }

        return nil
    }
}

public enum LanguageServerDocumentEvent: Equatable, Sendable {
    case didOpen(uri: String, languageID: String, version: Int, text: String)
    case didChange(uri: String, version: Int, text: String)
    case didSave(uri: String, text: String)
    case didClose(uri: String)

    public var method: String {
        switch self {
        case .didOpen:
            "textDocument/didOpen"
        case .didChange:
            "textDocument/didChange"
        case .didSave:
            "textDocument/didSave"
        case .didClose:
            "textDocument/didClose"
        }
    }

    public var payload: [String: Any] {
        switch self {
        case let .didOpen(uri, languageID, version, text):
            [
                "textDocument": [
                    "uri": uri,
                    "languageId": languageID,
                    "version": version,
                    "text": text,
                ],
            ]
        case let .didChange(uri, version, text):
            [
                "textDocument": [
                    "uri": uri,
                    "version": version,
                ],
                "contentChanges": [
                    ["text": text],
                ],
            ]
        case let .didSave(uri, text):
            [
                "textDocument": [
                    "uri": uri,
                ],
                "text": text,
            ]
        case let .didClose(uri):
            [
                "textDocument": [
                    "uri": uri,
                ],
            ]
        }
    }
}

public struct LanguageServerDiagnostic: Identifiable, Equatable, Sendable {
    public var fileURL: URL
    public var severity: TaskDiagnosticSeverity
    public var message: String
    public var line: Int
    public var column: Int

    public var id: String {
        "\(fileURL.path):\(line):\(column):\(severity.rawValue):\(message)"
    }

    public var locationDisplay: String {
        "\(fileURL.lastPathComponent):\(line + 1):\(column + 1)"
    }
}

public enum LanguageServerDiagnosticsParser {
    public static func diagnostics(from jsonData: Data) -> [LanguageServerDiagnostic] {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              object["method"] as? String == "textDocument/publishDiagnostics",
              let params = object["params"] as? [String: Any],
              let uri = params["uri"] as? String,
              let fileURL = URL(string: uri),
              fileURL.isFileURL,
              let diagnostics = params["diagnostics"] as? [[String: Any]]
        else {
            return []
        }

        return diagnostics.compactMap { diagnostic in
            guard let range = diagnostic["range"] as? [String: Any],
                  let start = range["start"] as? [String: Any],
                  let line = start["line"] as? Int,
                  let character = start["character"] as? Int,
                  let message = diagnostic["message"] as? String
            else {
                return nil
            }

            return LanguageServerDiagnostic(
                fileURL: fileURL.standardizedFileURL,
                severity: severity(from: diagnostic["severity"] as? Int),
                message: message,
                line: max(0, line),
                column: max(0, character)
            )
        }
    }

    private static func severity(from value: Int?) -> TaskDiagnosticSeverity {
        switch value {
        case 1:
            .error
        case 2:
            .warning
        default:
            .note
        }
    }
}

public struct LanguageServerMessageFramer {
    private(set) var bufferedData = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        bufferedData.append(data)
        var messages: [Data] = []

        while let headerRange = bufferedData.range(of: Data("\r\n\r\n".utf8)) {
            let headerData = bufferedData[..<headerRange.lowerBound]
            guard let header = String(data: headerData, encoding: .utf8),
                  let contentLength = contentLength(in: header)
            else {
                bufferedData.removeSubrange(..<headerRange.upperBound)
                continue
            }

            let bodyStart = headerRange.upperBound
            let bodyEnd = bodyStart + contentLength
            guard bufferedData.count >= bodyEnd else {
                break
            }

            messages.append(Data(bufferedData[bodyStart..<bodyEnd]))
            bufferedData.removeSubrange(..<bodyEnd)
        }

        return messages
    }

    private func contentLength(in header: String) -> Int? {
        header
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else {
                    return nil
                }
                return Int(parts[1])
            }
            .first
    }
}
