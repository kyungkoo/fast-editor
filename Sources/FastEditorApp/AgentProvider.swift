import Foundation

struct AgentProvider: Decodable, Identifiable, Equatable {
    var id: AgentProviderID
    var displayName: String
    var executablePath: String?
    var available: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case executablePath = "executable_path"
        case available
    }
}

enum AgentProviderID: String, Decodable, Equatable {
    case codex
    case claude
    case gemini
}
