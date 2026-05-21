import Foundation

public enum RelayRole: String, Sendable {
    case mac
    case ios

    public var pathComponent: String {
        switch self {
        case .mac: return "connect"
        case .ios: return "listen"
        }
    }
}

public actor RelayClient {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(
        relayURL: URL,
        pairingCode: String,
        role: RelayRole
    ) throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        guard PairingCode.isValid(pairingCode) else {
            throw RelayError.invalidPairingCode(pairingCode)
        }

        let endpoint = relayURL
            .appendingPathComponent(role.pathComponent)
            .appendingPathComponent(pairingCode)

        guard endpoint.scheme == "ws" || endpoint.scheme == "wss" else {
            throw RelayError.invalidRelayURL
        }

        let task = session.webSocketTask(with: endpoint)
        self.task = task
        task.resume()

        let stream = AsyncThrowingStream<RemoteEnvelope, any Error> { continuation in
            let receiveTask = Task {
                await self.receiveLoop(task: task, continuation: continuation)
            }
            self.receiveTask = receiveTask
            continuation.onTermination = { _ in receiveTask.cancel() }
        }
        return stream
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        guard let task else { throw RelayError.notConnected }
        let data: Data
        do {
            data = try JSONEncoder().encode(envelope)
        } catch {
            throw RelayError.encodingFailed(error.localizedDescription)
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        try await task.send(.string(text))
    }

    public func disconnect(code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        task?.cancel(with: code, reason: nil)
        task = nil
        receiveTask?.cancel()
        receiveTask = nil
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        continuation: AsyncThrowingStream<RemoteEnvelope, any Error>.Continuation
    ) async {
        let decoder = JSONDecoder()
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    guard let data = text.data(using: .utf8) else { continue }
                    if let envelope = try? decoder.decode(RemoteEnvelope.self, from: data) {
                        continuation.yield(envelope)
                    }
                case .data(let data):
                    if let envelope = try? decoder.decode(RemoteEnvelope.self, from: data) {
                        continuation.yield(envelope)
                    }
                @unknown default:
                    continue
                }
            } catch {
                continuation.finish(throwing: error)
                return
            }
        }
        continuation.finish()
    }
}
