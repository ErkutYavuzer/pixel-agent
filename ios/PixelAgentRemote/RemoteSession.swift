import Foundation
import PixelCore
import PixelRemote

@MainActor
final class RemoteSession: ObservableObject {
    @Published var pairing: PairingInfo?
    @Published var isConnected: Bool = false
    @Published var isAutoConnecting: Bool = false
    @Published var messages: [Message] = []
    @Published var lastError: String?

    private var client: RelayClient?
    private var receiveTask: Task<Void, Never>?

    private static let pairingDefaultsKey = "pixel-agent.pairing.v1"

    init() {
        if let saved = Self.loadSavedPairing() {
            self.pairing = saved
            Task { await self.autoReconnect(to: saved) }
        }
    }

    func connect(pairing: PairingInfo) async {
        guard let relayURL = URL(string: pairing.relayURL) else {
            lastError = "Geçersiz relay URL"
            return
        }

        await disconnect(forget: false)

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
            Self.savePairing(pairing)

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

    /// `forget: true` ile çağrılırsa kayıtlı pairing de silinir (kullanıcı "Bağlantıyı kes" butonu).
    /// `forget: false` (default) sadece in-memory state'i temizler — bir sonraki açılışta auto-reconnect dener.
    func disconnect(forget: Bool = true) async {
        await client?.disconnect()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        if forget {
            pairing = nil
            Self.clearSavedPairing()
        }
    }

    private func autoReconnect(to pairing: PairingInfo) async {
        isAutoConnecting = true
        defer { isAutoConnecting = false }

        let connectTask = Task { await self.connect(pairing: pairing) }

        // 5s timeout polling (LAN IP değişmiş olabilir → ölü pairing forget)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if isConnected || connectTask.isCancelled { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if !isConnected {
            connectTask.cancel()
            try? await Task.sleep(nanoseconds: 100_000_000)
            await disconnect(forget: true)
            lastError = "Otomatik bağlanma başarısız (5s timeout). QR kodu yeniden tarayın."
        }
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

    // MARK: - Persistence

    private static func savePairing(_ pairing: PairingInfo) {
        let dict: [String: String] = [
            "code": pairing.code,
            "relay": pairing.relayURL,
        ]
        UserDefaults.standard.set(dict, forKey: pairingDefaultsKey)
    }

    private static func loadSavedPairing() -> PairingInfo? {
        guard let dict = UserDefaults.standard.dictionary(forKey: pairingDefaultsKey) as? [String: String],
              let code = dict["code"],
              let relay = dict["relay"]
        else {
            return nil
        }
        return PairingInfo(code: code, relayURL: relay)
    }

    private static func clearSavedPairing() {
        UserDefaults.standard.removeObject(forKey: pairingDefaultsKey)
    }
}

struct PairingInfo: Equatable {
    let code: String
    let relayURL: String

    init(code: String, relayURL: String) {
        self.code = code
        self.relayURL = relayURL
    }

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
