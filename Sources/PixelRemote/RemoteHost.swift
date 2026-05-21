import Combine
import Foundation

@MainActor
public final class RemoteHost: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var lastError: String?
    @Published public private(set) var pairingCode: String

    public var relayURL: String

    private var client: RelayClient?
    private var receiveTask: Task<Void, Never>?
    private let inboundContinuation: AsyncStream<String>.Continuation
    public let inboundTexts: AsyncStream<String>

    public init(relayURL: String = "ws://localhost:8787") {
        self.relayURL = relayURL
        self.pairingCode = PairingCode.generate()
        var captured: AsyncStream<String>.Continuation!
        self.inboundTexts = AsyncStream<String> { continuation in
            captured = continuation
        }
        self.inboundContinuation = captured
    }

    public func regenerateCode() {
        pairingCode = PairingCode.generate()
    }

    public func connect() async {
        guard let url = URL(string: relayURL) else {
            lastError = "Geçersiz relay URL: \(relayURL)"
            return
        }

        await disconnect()

        let client = RelayClient()
        do {
            let stream = try await client.connect(
                relayURL: url,
                pairingCode: pairingCode,
                role: .mac
            )
            self.client = client
            isConnected = true
            lastError = nil

            let inboundContinuation = self.inboundContinuation
            receiveTask = Task {
                do {
                    for try await envelope in stream {
                        if envelope.type == .userMessage,
                           let text = envelope.payload?.text,
                           !text.isEmpty {
                            inboundContinuation.yield(text)
                        }
                    }
                    await MainActor.run { self.isConnected = false }
                } catch {
                    await MainActor.run {
                        self.lastError = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        self.isConnected = false
                    }
                }
            }
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isConnected = false
        }
    }

    public func disconnect() async {
        await client?.disconnect()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
    }

    public func sendAssistantMessage(_ text: String) async {
        guard let client else { return }
        let envelope = RemoteEnvelope.assistantMessage(text: text)
        try? await client.send(envelope)
    }
}
