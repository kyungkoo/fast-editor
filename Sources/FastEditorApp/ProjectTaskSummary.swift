import Foundation

struct ProjectTaskSummary: Decodable, Equatable {
    var detections: [ProjectDetection]
    var tasks: [ProjectTaskDefinition]
    var android: AndroidTaskSummary?

    static let empty = ProjectTaskSummary(detections: [], tasks: [], android: nil)
}

struct ProjectDetection: Decodable, Equatable, Identifiable {
    var providerID: TaskProviderID
    var confidence: DetectionConfidence
    var projectRoot: String
    var evidence: [String]

    var id: TaskProviderID { providerID }

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case confidence
        case projectRoot = "project_root"
        case evidence
    }
}

struct ProjectTaskDefinition: Decodable, Equatable, Identifiable {
    var providerID: TaskProviderID
    var id: String
    var label: String
    var kind: TaskKind
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case id
        case label
        case kind
        case detail
    }
}

struct TaskExecutionPlan: Decodable, Equatable {
    var providerID: TaskProviderID
    var taskID: String
    var program: String
    var args: [String]
    var cwd: String
    var environment: [[String]]

    var commandDisplay: String {
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

struct TaskDiagnostic: Decodable, Equatable, Identifiable {
    var severity: TaskDiagnosticSeverity
    var message: String
    var file: String?
    var line: Int?
    var column: Int?

    var id: String {
        "\(severity.rawValue):\(file ?? ""):\(line ?? 0):\(column ?? 0):\(message)"
    }

    var locationDisplay: String {
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

    var targetLineIndex: Int? {
        line.map { max(0, $0 - 1) }
    }

    var targetColumnIndex: Int? {
        column.map { max(0, $0 - 1) }
    }

    func resolvedFileURL(workspaceURL: URL?) -> URL? {
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

enum TaskDiagnosticSeverity: String, Decodable, Equatable {
    case error
    case warning
    case note
}

enum TaskProviderID: String, Decodable, Equatable {
    case android
    case swiftPackage = "swift_package"
    case web

    var displayName: String {
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

enum DetectionConfidence: String, Decodable, Equatable {
    case high
    case medium
    case low
}

enum TaskKind: String, Decodable, Equatable {
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

struct AndroidTaskSummary: Decodable, Equatable {
    var environment: AndroidEnvironmentInspection
    var project: AndroidProjectDescription
}

struct AndroidEnvironmentInspection: Decodable, Equatable {
    var sdkLocation: String?
    var androidHome: String?
    var androidSDKRoot: String?
    var androidCLIPath: String?
    var gradleWrapperPath: String?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case sdkLocation = "sdk_location"
        case androidHome = "android_home"
        case androidSDKRoot = "android_sdk_root"
        case androidCLIPath = "android_cli_path"
        case gradleWrapperPath = "gradle_wrapper_path"
        case notes
    }
}

struct AndroidProjectDescription: Decodable, Equatable {
    var projectRoot: String
    var settingsFiles: [String]
    var rootBuildFiles: [String]
    var moduleBuildFiles: [String]
    var manifestFiles: [String]
    var hasGradleWrapper: Bool

    private enum CodingKeys: String, CodingKey {
        case projectRoot = "project_root"
        case settingsFiles = "settings_files"
        case rootBuildFiles = "root_build_files"
        case moduleBuildFiles = "module_build_files"
        case manifestFiles = "manifest_files"
        case hasGradleWrapper = "has_gradle_wrapper"
    }
}
