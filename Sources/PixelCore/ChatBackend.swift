import Foundation

public protocol ChatBackend: Sendable {
    var modelID: String { get }

    func send(
        messages: [Message],
        system: String?
    ) -> AsyncThrowingStream<StreamDelta, any Error>
}
