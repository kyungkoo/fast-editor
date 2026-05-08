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
