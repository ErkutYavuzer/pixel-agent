import Foundation
import PixelCore
import PixelRemote

@MainActor
final class RemoteSession: ObservableObject {
    @Published var pairing: PairingInfo?
    @Published var isConnected: Bool = false
    @Published var messages: [Message] = []
    @Published var lastError: String?

    private var client: RelayClient?
    private var receiveTask: Task<Void, Never>?

    func connect(pairing: PairingInfo) async {
        guard let relayURL = URL(string: pairing.relayURL) else {
            lastError = "Geçersiz relay URL"
            return
        }

        let client = RelayClient()
        self.client = client
        self.pairing = pairing

        do {
            let stream = try await client.connect(
                relayURL: relayURL,
                pairingCode: pairing.code,
                role: .ios
            )
            isConnected = true
            lastError = nil

            receiveTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await envelope in stream {
                        await self.handle(envelope)
                    }
                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.isConnected = false
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
            isConnected = false
        }
    }

    func send(text: String) async {
        guard let client else {
            lastError = "Bağlı değil"
            return
        }
        let userMsg = Message(role: .user, text: text)
        messages.append(userMsg)

        let envelope = RemoteEnvelope.userMessage(text: text, messageID: userMsg.id.uuidString)
        do {
            try await client.send(envelope)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        pairing = nil
    }

    private func handle(_ envelope: RemoteEnvelope) async {
        switch envelope.type {
        case .assistantMessage:
            if let text = envelope.payload?.text {
                let assistantMsg = Message(role: .assistant, text: text)
                messages.append(assistantMsg)
            }
        case .error:
            if let message = envelope.payload?.errorMessage {
                lastError = message
            }
        default:
            break
        }
    }
}

struct PairingInfo: Equatable {
    let code: String
    let relayURL: String

    init?(qrPayload: String) {
        guard let url = URL(string: qrPayload),
              url.scheme == "pixel-agent-pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else {
            return nil
        }

        var pairingCode: String?
        var relayURLString: String?
        for item in queryItems {
            switch item.name {
            case "code": pairingCode = item.value
            case "relay": relayURLString = item.value
            default: break
            }
        }

        guard let code = pairingCode, !code.isEmpty,
              let relay = relayURLString, !relay.isEmpty,
              PairingCode.isValid(code)
        else {
            return nil
        }

        self.code = code
        self.relayURL = relay
    }
}
