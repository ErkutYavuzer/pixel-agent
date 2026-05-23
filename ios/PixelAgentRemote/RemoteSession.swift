import CryptoKit
import Foundation
import PixelCore
import PixelLAN
import PixelRemote
import PixelMascot

/// Bir `PairingInfo`'dan iOS-rolünde transport üretir. v0.2.11'den itibaren
/// varsayılan `defaultLANFirstTransportFactory` — `FallbackTransport(primary: LAN,
/// fallback: Relay)`. App entry her seferinde geçersiz kılabilir.
typealias RemoteTransportFactory = @Sendable (PairingInfo) -> any RemoteTransport

/// Relay-only factory — eski davranış. Bonjour erişimi yoksa veya LAN discovery
/// nedensiz gecikmek istemiyorsanız kullanın.
@Sendable
func defaultRelayTransportFactory(for pairing: PairingInfo) -> any RemoteTransport {
    relayTransport(for: pairing)
}

/// LAN-first factory: önce Bonjour ile Mac'i bulmaya çalış (2s timeout), olmazsa
/// relay'e düş. Aynı ağdayken latency çok düşük; farklı ağdayken otomatik fallback.
@Sendable
func defaultLANFirstTransportFactory(for pairing: PairingInfo) -> any RemoteTransport {
    let lan = LANClientTransport(discoveryTimeout: 2.0)
    let relay = relayTransport(for: pairing)
    return FallbackTransport(primary: lan, fallback: relay)
}

@Sendable
private func relayTransport(for pairing: PairingInfo) -> any RemoteTransport {
    guard let url = URL(string: pairing.relayURL) else {
        return RelayTransport(
            relayURL: URL(string: "ws://localhost:0")!,
            pairingCode: pairing.code,
            role: .ios
        )
    }
    return RelayTransport(relayURL: url, pairingCode: pairing.code, role: .ios)
}

@MainActor
final class RemoteSession: ObservableObject {
    @Published var pairing: PairingInfo?
    @Published var isConnected: Bool = false
    @Published var isAutoConnecting: Bool = false
    @Published var messages: [Message] = []
    @Published var lastError: String?
    /// Aktif transport tipi etiketi — "LAN" / "Relay" / nil (bağlı değil).
    /// `FallbackTransport` kullanılıyorsa `connect` sonrası `currentSelection`'dan
    /// türetilir; aksi halde generic "Bağlı".
    @Published var transportLabel: String?
    @Published var mascotState: MascotState = .idle

    private var transport: (any RemoteTransport)?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private let signingKey: Curve25519.Signing.PrivateKey
    private var macPublicKey: Curve25519.Signing.PublicKey?

    private let transportFactory: RemoteTransportFactory

    private static let pairingDefaultsKey = "pixel-agent.pairing.v2"
    private static let keychainService = "dev.erkutyavuzer.pixel-agent"
    private static let keychainAccount = "remote-ios-signing-key"

    init(
        keyStore: KeyStoring = KeychainKeyStore(),
        transportFactory: @escaping RemoteTransportFactory = defaultLANFirstTransportFactory
    ) {
        if let loaded = try? keyStore.loadOrCreate(
            service: Self.keychainService,
            account: Self.keychainAccount
        ) {
            self.signingKey = loaded
        } else {
            self.signingKey = Curve25519.Signing.PrivateKey()
        }
        self.transportFactory = transportFactory

        if let saved = Self.loadSavedPairing() {
            self.pairing = saved
            Task { await self.autoReconnect(to: saved) }
        }
    }

    var publicKeyBase64: String {
        signingKey.publicKey.rawRepresentation.base64EncodedString()
    }

    func connect(pairing: PairingInfo) async {
        await disconnect(forget: false)

        guard let macKeyData = Data(base64Encoded: pairing.macPublicKey),
              let macKey = try? Curve25519.Signing.PublicKey(rawRepresentation: macKeyData)
        else {
            lastError = "Eşleşme bilgisinde Mac public key geçersiz. QR'ı yeniden tarayın."
            return
        }
        self.macPublicKey = macKey

        let transport = transportFactory(pairing)
        self.transport = transport
        self.pairing = pairing

        do {
            let stream = try await transport.connect()
            isConnected = true
            lastError = nil
            transportLabel = await Self.label(for: transport)
            Self.savePairing(pairing)

            // Handshake: hello envelope (unsigned — chicken-and-egg).
            try await transport.send(RemoteEnvelope.hello(publicKey: publicKeyBase64))

            receiveTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await envelope in stream {
                        if Task.isCancelled { break }
                        await self.handle(envelope)
                    }
                    await self.onConnectionLost()
                } catch {
                    await self.onConnectionLost(error: error)
                }
            }
        } catch {
            await self.onConnectionLost(error: error)
        }
    }

    func send(text: String) async {
        guard let transport else {
            lastError = "Bağlı değil"
            return
        }
        let userMsg = Message(role: .user, text: text)
        messages.append(userMsg)
        mascotState = .thinking

        let envelope = RemoteEnvelope.userMessage(text: text, messageID: userMsg.id.uuidString)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = error.localizedDescription
            mascotState = .error
        }
    }

    func disconnect(forget: Bool = true) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        
        await transport?.disconnect()
        transport = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        transportLabel = nil
        macPublicKey = nil
        mascotState = .idle
        if forget {
            pairing = nil
            Self.clearSavedPairing()
        }
    }

    private func onConnectionLost(error: Error? = nil) async {
        isConnected = false
        transportLabel = nil
        mascotState = .error
        if let error {
            lastError = error.localizedDescription
        } else {
            lastError = "Bağlantı koptu"
        }
        
        if pairing != nil && reconnectTask == nil {
            startReconnectionLoop()
        }
    }

    private func startReconnectionLoop() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var delaySeconds: Double = 2.0
            let maxDelaySeconds: Double = 30.0
            
            while !Task.isCancelled {
                guard let self else { break }
                guard let pairing = await self.pairing else { break }
                guard !(await self.isConnected) else { break }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                } catch {
                    break // Task cancelled
                }
                
                if Task.isCancelled { break }
                
                await self.connect(pairing: pairing)
                
                if await self.isConnected {
                    break
                } else {
                    delaySeconds = min(delaySeconds * 2, maxDelaySeconds)
                }
            }
            
            await MainActor.run { [weak self] in
                self?.reconnectTask = nil
            }
        }
    }

    /// Aktif transport tipi etiketini türetir — `FallbackTransport`'sa
    /// `currentSelection`'a göre "LAN" / "Relay"; aksi halde "Bağlı".
    private static func label(for transport: any RemoteTransport) async -> String {
        if let fallback = transport as? FallbackTransport {
            switch await fallback.currentSelection {
            case .primary: return "LAN"
            case .fallback: return "Relay"
            case .none: return "Bağlı"
            }
        }
        if transport is LANClientTransport {
            return "LAN"
        }
        if transport is RelayTransport {
            return "Relay"
        }
        return "Bağlı"
    }

    private func autoReconnect(to pairing: PairingInfo) async {
        isAutoConnecting = true
        await connect(pairing: pairing)
        isAutoConnecting = false

        if !isConnected {
            startReconnectionLoop()
        }
    }

    private func handle(_ envelope: RemoteEnvelope) async {
        guard let macKey = macPublicKey,
              EnvelopeSigner.verify(envelope, with: macKey)
        else {
            return
        }

        switch envelope.type {
        case .assistantChunk:
            if let text = envelope.payload?.text,
               let msgIDString = envelope.payload?.messageID,
               let msgID = UUID(uuidString: msgIDString) {
                if let idx = messages.firstIndex(where: { $0.id == msgID }) {
                    messages[idx].text += text
                } else {
                    let assistantMsg = Message(id: msgID, role: .assistant, text: text)
                    messages.append(assistantMsg)
                }
                mascotState = .speaking
            }
        case .assistantMessage:
            if let text = envelope.payload?.text {
                if let msgIDString = envelope.payload?.messageID,
                   let msgID = UUID(uuidString: msgIDString),
                   let idx = messages.firstIndex(where: { $0.id == msgID }) {
                    messages[idx].text = text
                } else {
                    let assistantMsg = Message(role: .assistant, text: text)
                    messages.append(assistantMsg)
                }
                mascotState = .idle
            }
        case .error:
            if let message = envelope.payload?.errorMessage {
                lastError = message
                mascotState = .error
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
            "pk": pairing.macPublicKey,
        ]
        UserDefaults.standard.set(dict, forKey: pairingDefaultsKey)
    }

    private static func loadSavedPairing() -> PairingInfo? {
        guard let dict = UserDefaults.standard.dictionary(forKey: pairingDefaultsKey) as? [String: String],
              let code = dict["code"],
              let relay = dict["relay"],
              let pk = dict["pk"]
        else {
            return nil
        }
        return PairingInfo(code: code, relayURL: relay, macPublicKey: pk)
    }

    private static func clearSavedPairing() {
        UserDefaults.standard.removeObject(forKey: pairingDefaultsKey)
    }
}

struct PairingInfo: Equatable, Sendable {
    let code: String
    let relayURL: String
    let macPublicKey: String

    init(code: String, relayURL: String, macPublicKey: String) {
        self.code = code
        self.relayURL = relayURL
        self.macPublicKey = macPublicKey
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
        var macPK: String?
        for item in queryItems {
            switch item.name {
            case "code": pairingCode = item.value
            case "relay": relayURLString = item.value
            case "pk": macPK = item.value
            default: break
            }
        }

        guard let code = pairingCode, !code.isEmpty,
              let relay = relayURLString, !relay.isEmpty,
              let pk = macPK, !pk.isEmpty,
              PairingCode.isValid(code),
              let pkData = Data(base64Encoded: pk),
              pkData.count == 32,
              (try? Curve25519.Signing.PublicKey(rawRepresentation: pkData)) != nil
        else {
            return nil
        }

        self.code = code
        self.relayURL = relay
        self.macPublicKey = pk
    }
}
