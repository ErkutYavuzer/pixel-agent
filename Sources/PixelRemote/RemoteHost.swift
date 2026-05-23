import Combine
import CryptoKit
import Foundation

@MainActor
public final class RemoteHost: ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var lastError: String?
    @Published public private(set) var pairingCode: String
    /// iOS tarafı hello envelope'unu gönderip public key'i bize ulaştığında `true`.
    @Published public private(set) var isPaired: Bool = false

    public var onClientConfigReceived: ((_ backend: String, _ model: String, _ planMode: Bool) -> Void)?
    public var onClientActionReceived: ((_ action: String, _ targetID: String?) -> Void)?

    public var relayURL: String

    /// QR payload'una eklenecek mac public key (base64).
    public let publicKeyBase64: String

    private let signingKey: Curve25519.Signing.PrivateKey
    private var peerPublicKey: Curve25519.Signing.PublicKey?

    /// Provided transport (LAN-only veya FallbackTransport gibi); nil ise eski
    /// API kullanılıyor demektir, connect() içinde RelayTransport oluşturulur.
    private let providedTransport: (any RemoteTransport)?

    /// Builder pattern — closure pairingCode + publicKey'i alır ve transport döner.
    /// Hem `transport` hem `transportBuilder` set'lenmişse `transport` öncelikli.
    public typealias TransportBuilder = @MainActor (_ pairingCode: String, _ publicKeyBase64: String) -> any RemoteTransport
    private let transportBuilder: TransportBuilder?

    private var activeTransport: (any RemoteTransport)?
    private var receiveTask: Task<Void, Never>?
    private let inboundContinuation: AsyncStream<String>.Continuation
    public let inboundTexts: AsyncStream<String>

    /// Geriye uyumlu init — relay URL ile çalışır. Eski API.
    public init(
        relayURL: String = "ws://localhost:8787",
        keyStore: KeyStoring = KeychainKeyStore(),
        keyService: String = "dev.erkutyavuzer.pixel-agent",
        keyAccount: String = "remote-mac-signing-key"
    ) {
        self.relayURL = relayURL
        self.providedTransport = nil
        self.transportBuilder = nil
        self.pairingCode = PairingCode.generate()

        let key: Curve25519.Signing.PrivateKey
        if let loaded = try? keyStore.loadOrCreate(service: keyService, account: keyAccount) {
            key = loaded
        } else {
            key = Curve25519.Signing.PrivateKey()
        }
        self.signingKey = key
        self.publicKeyBase64 = key.publicKey.rawRepresentation.base64EncodedString()

        var captured: AsyncStream<String>.Continuation!
        self.inboundTexts = AsyncStream<String> { continuation in
            captured = continuation
        }
        self.inboundContinuation = captured
    }

    /// Transport DI init — sabit bir transport. `LANServerTransport`, `FallbackTransport`, vs.
    /// `relayURL` QR payload için isteğe bağlı (transport ne kullanırsa kullansın).
    public init(
        transport: any RemoteTransport,
        relayURL: String = "",
        keyStore: KeyStoring = KeychainKeyStore(),
        keyService: String = "dev.erkutyavuzer.pixel-agent",
        keyAccount: String = "remote-mac-signing-key"
    ) {
        self.relayURL = relayURL
        self.providedTransport = transport
        self.transportBuilder = nil
        self.pairingCode = PairingCode.generate()

        let key: Curve25519.Signing.PrivateKey
        if let loaded = try? keyStore.loadOrCreate(service: keyService, account: keyAccount) {
            key = loaded
        } else {
            key = Curve25519.Signing.PrivateKey()
        }
        self.signingKey = key
        self.publicKeyBase64 = key.publicKey.rawRepresentation.base64EncodedString()

        var captured: AsyncStream<String>.Continuation!
        self.inboundTexts = AsyncStream<String> { continuation in
            captured = continuation
        }
        self.inboundContinuation = captured
    }

    /// Builder init — `connect()` zamanında closure çağrılır; pairingCode ve
    /// publicKey'i alır. Mac side MergeTransport(LAN, Relay) için circular dep
    /// (transport pairingCode'a, RemoteHost transport'a ihtiyaç duyar) çözümü.
    public init(
        relayURL: String,
        keyStore: KeyStoring = KeychainKeyStore(),
        keyService: String = "dev.erkutyavuzer.pixel-agent",
        keyAccount: String = "remote-mac-signing-key",
        transportBuilder: @escaping TransportBuilder
    ) {
        self.relayURL = relayURL
        self.providedTransport = nil
        self.transportBuilder = transportBuilder
        self.pairingCode = PairingCode.generate()

        let key: Curve25519.Signing.PrivateKey
        if let loaded = try? keyStore.loadOrCreate(service: keyService, account: keyAccount) {
            key = loaded
        } else {
            key = Curve25519.Signing.PrivateKey()
        }
        self.signingKey = key
        self.publicKeyBase64 = key.publicKey.rawRepresentation.base64EncodedString()

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
        await disconnect()

        let transport: any RemoteTransport
        if let provided = providedTransport {
            transport = provided
        } else if let builder = transportBuilder {
            transport = builder(pairingCode, publicKeyBase64)
        } else {
            guard let url = URL(string: relayURL) else {
                lastError = "Geçersiz relay URL: \(relayURL)"
                return
            }
            transport = RelayTransport(
                relayURL: url,
                pairingCode: pairingCode,
                role: .mac
            )
        }

        do {
            let stream = try await transport.connect()
            self.activeTransport = transport
            isConnected = true
            isPaired = false
            peerPublicKey = nil
            lastError = nil

            let inboundContinuation = self.inboundContinuation
            receiveTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await envelope in stream {
                        await self.handle(envelope, inbound: inboundContinuation)
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
        await activeTransport?.disconnect()
        activeTransport = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        isPaired = false
        peerPublicKey = nil
    }

    public func sendAssistantMessage(_ text: String, messageID: String? = nil) async {
        guard let transport = activeTransport else { return }
        let envelope = RemoteEnvelope.assistantMessage(text: text, messageID: messageID)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Mesaj gönderilemedi: \(error.localizedDescription)"
        }
    }

    public func sendAssistantChunk(_ text: String, messageID: String) async {
        guard let transport = activeTransport else { return }
        let envelope = RemoteEnvelope.assistantChunk(text: text, messageID: messageID)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Chunk gönderilemedi: \(error.localizedDescription)"
        }
    }

    public func sendHostStatus(
        selectedBackend: String,
        selectedModel: String,
        planMode: Bool,
        availableBackends: [String],
        availableModels: [String: [String]],
        activeSubagents: [SubagentStatusPayload],
        systemMetrics: SystemMetricsPayload
    ) async {
        guard let transport = activeTransport else { return }
        let envelope = RemoteEnvelope.hostStatus(
            selectedBackend: selectedBackend,
            selectedModel: selectedModel,
            planMode: planMode,
            availableBackends: availableBackends,
            availableModels: availableModels,
            activeSubagents: activeSubagents,
            systemMetrics: systemMetrics
        )
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Host status gönderilemedi: \(error.localizedDescription)"
        }
    }

    public func sendScreenshot(base64Image: String) async {
        guard let transport = activeTransport else { return }
        let envelope = RemoteEnvelope.screenshotPayload(base64Image: base64Image)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Ekran görüntüsü gönderilemedi: \(error.localizedDescription)"
        }
    }

    // MARK: - Inbound handshake + signature verification

    private func handle(
        _ envelope: RemoteEnvelope,
        inbound: AsyncStream<String>.Continuation
    ) async {
        // Handshake: ilk envelope, hello + payload.publicKey ile gelmeli. Aksi reddedilir.
        if !isPaired {
            guard envelope.type == .hello,
                  let pkB64 = envelope.payload?.publicKey,
                  let pkData = Data(base64Encoded: pkB64),
                  let pubkey = try? Curve25519.Signing.PublicKey(rawRepresentation: pkData)
            else {
                return
            }
            peerPublicKey = pubkey
            isPaired = true
            return
        }

        guard let peer = peerPublicKey,
              EnvelopeSigner.verify(envelope, with: peer)
        else {
            return
        }

        switch envelope.type {
        case .userMessage:
            if let text = envelope.payload?.text, !text.isEmpty {
                inbound.yield(text)
            }
        case .clientConfig:
            if let backend = envelope.payload?.selectedBackend,
               let model = envelope.payload?.selectedModel,
               let plan = envelope.payload?.planMode {
                onClientConfigReceived?(backend, model, plan)
            }
        case .clientAction:
            if let action = envelope.payload?.actionType {
                onClientActionReceived?(action, envelope.payload?.targetID)
            }
        default:
            break
        }
    }
}
