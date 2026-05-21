import Foundation

public enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct Message: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let role: MessageRole
    public var text: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public enum StreamDelta: Sendable, Equatable {
    case textChunk(String)
    case done
}
