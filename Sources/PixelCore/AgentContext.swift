import Foundation

public enum AgentID: String, Codable, Sendable {
    case primary
    case secondary
}

/// Bir subagent çalıştığı sürece TaskLocal olarak set edilen tanımlayıcı.
/// `SubagentRunner.run(...)` içine girer, biter bitmez nil olur — log/tracing
/// için root agent ile subagent ayrımı yapmaya yarar.
public struct SubagentID: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let value: String

    public init(value: String = UUID().uuidString) {
        self.value = value
    }

    public var description: String { value }
}

public enum AgentContext {
    @TaskLocal public static var current: AgentID = .primary

    /// Bir subagent çağrı zinciri sırasında binding ile set edilir; ana akışta `nil`.
    @TaskLocal public static var currentSubagentID: SubagentID? = nil
}
