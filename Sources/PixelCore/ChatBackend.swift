import Foundation

public protocol ChatBackend: Sendable {
    var modelID: String { get }

    func send(
        messages: [Message],
        system: String?,
        options: ChatOptions
    ) -> AsyncThrowingStream<StreamDelta, any Error>
}

extension ChatBackend {
    /// Varsayılan `ChatOptions()` ile çağrı — eski call-site'lar için convenience.
    public func send(
        messages: [Message],
        system: String?
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        send(messages: messages, system: system, options: ChatOptions())
    }
}
