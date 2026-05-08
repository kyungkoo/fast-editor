import Foundation

public struct AgentProvider: Decodable, Identifiable, Equatable, Sendable {
    public var id: AgentProviderID
    public var displayName: String
    public var executablePath: String?
    public var available: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case executablePath = "executable_path"
        case available
    }
}

public enum AgentProviderID: String, Decodable, Sendable, Equatable {
    case codex
    case claude
    case gemini
}
