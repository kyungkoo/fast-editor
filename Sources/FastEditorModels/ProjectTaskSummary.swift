import Foundation

public struct ProjectTaskSummary: Decodable, Equatable, Sendable {
    public var detections: [ProjectDetection]
    public var tasks: [ProjectTaskDefinition]
    public var android: AndroidTaskSummary?

    public static let empty = ProjectTaskSummary(detections: [], tasks: [], android: nil)
}

public struct ProjectDetection: Decodable, Equatable, Sendable, Identifiable {
    public var providerID: TaskProviderID
    public var confidence: DetectionConfidence
    public var projectRoot: String
    public var evidence: [String]

    public var id: TaskProviderID { providerID }

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case confidence
        case projectRoot = "project_root"
        case evidence
    }
}

public struct ProjectTaskDefinition: Decodable, Equatable, Sendable, Identifiable {
    public var providerID: TaskProviderID
    public var id: String
    public var label: String
    public var kind: TaskKind
    public var detail: String?

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case id
        case label
        case kind
        case detail
    }
}

public struct TaskExecutionPlan: Decodable, Equatable, Sendable {
    public var providerID: TaskProviderID
    public var taskID: String
    public var program: String
    public var args: [String]
    public var cwd: String
    public var environment: [[String]]

    public var commandDisplay: String {
        ([program] + args).map(shellQuote).joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case taskID = "task_id"
        case program
        case args
        case cwd
        case environment
    }
}

public struct TaskDiagnostic: Decodable, Equatable, Sendable, Identifiable {
    public var severity: TaskDiagnosticSeverity
    public var message: String
    public var file: String?
    public var line: Int?
    public var column: Int?

    public var id: String {
        "\(severity.rawValue):\(file ?? ""):\(line ?? 0):\(column ?? 0):\(message)"
    }

    public var locationDisplay: String {
        guard let file else {
            return "Task output"
        }

        if let line, let column {
            return "\(file):\(line):\(column)"
        }

        if let line {
            return "\(file):\(line)"
        }

        return file
    }

    public var targetLineIndex: Int? {
        line.map { max(0, $0 - 1) }
    }

    public var targetColumnIndex: Int? {
        column.map { max(0, $0 - 1) }
    }

    public func resolvedFileURL(workspaceURL: URL?) -> URL? {
        guard let file, !file.isEmpty else {
            return nil
        }

        if file.hasPrefix("/") {
            return URL(fileURLWithPath: file).standardizedFileURL
        }

        guard let workspaceURL else {
            return nil
        }

        return workspaceURL
            .appendingPathComponent(file)
            .standardizedFileURL
    }
}

public enum TaskDiagnosticSeverity: String, Decodable, Sendable, Equatable {
    case error
    case warning
    case note
}

public enum TaskProviderID: String, Decodable, Sendable, Equatable {
    case android
    case swiftPackage = "swift_package"
    case web

    public var displayName: String {
        switch self {
        case .android:
            "Android"
        case .swiftPackage:
            "Swift Package"
        case .web:
            "Web"
        }
    }
}

public enum DetectionConfidence: String, Decodable, Sendable, Equatable {
    case high
    case medium
    case low
}

public enum TaskKind: String, Decodable, Sendable, Equatable {
    case build
    case run
    case test
    case script
    case other
}

private func shellQuote(_ value: String) -> String {
    if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'"))) == nil {
        return value
    }

    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

public struct AndroidTaskSummary: Decodable, Equatable, Sendable {
    public var environment: AndroidEnvironmentInspection
    public var project: AndroidProjectDescription
}

public struct AndroidEnvironmentInspection: Decodable, Equatable, Sendable {
    public var sdkLocation: String?
    public var androidHome: String?
    public var androidSDKRoot: String?
    public var androidCLIPath: String?
    public var gradleWrapperPath: String?
    public var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case sdkLocation = "sdk_location"
        case androidHome = "android_home"
        case androidSDKRoot = "android_sdk_root"
        case androidCLIPath = "android_cli_path"
        case gradleWrapperPath = "gradle_wrapper_path"
        case notes
    }
}

public struct AndroidProjectDescription: Decodable, Equatable, Sendable {
    public var projectRoot: String
    public var settingsFiles: [String]
    public var rootBuildFiles: [String]
    public var moduleBuildFiles: [String]
    public var manifestFiles: [String]
    public var hasGradleWrapper: Bool

    private enum CodingKeys: String, CodingKey {
        case projectRoot = "project_root"
        case settingsFiles = "settings_files"
        case rootBuildFiles = "root_build_files"
        case moduleBuildFiles = "module_build_files"
        case manifestFiles = "manifest_files"
        case hasGradleWrapper = "has_gradle_wrapper"
    }
}
