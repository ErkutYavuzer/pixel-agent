public enum AgentID: String, Codable, Sendable {
    case primary
    case secondary
}

public enum AgentContext {
    @TaskLocal public static var current: AgentID = .primary
}
