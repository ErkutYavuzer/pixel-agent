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

    public var relayURL: String

    /// QR payload'una eklenecek mac public key (base64).
    public let publicKeyBase64: String

    private let signingKey: Curve25519.Signing.PrivateKey
    private var peerPublicKey: Curve25519.Signing.PublicKey?

    private var client: RelayClient?
    private var receiveTask: Task<Void, Never>?
    private let inboundContinuation: AsyncStream<String>.Continuation
    public let inboundTexts: AsyncStream<String>

    public init(
        relayURL: String = "ws://localhost:8787",
        keyStore: KeyStoring = KeychainKeyStore(),
        keyService: String = "dev.erkutyavuzer.pixel-agent",
        keyAccount: String = "remote-mac-signing-key"
    ) {
        self.relayURL = relayURL
        self.pairingCode = PairingCode.generate()

        // Keychain başarısız olursa ephemeral key — bağlantı çalışır ama her açılışta
        // yeni QR gerekli. Üretimde kullanıcı uyarılır (lastError).
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
        await client?.disconnect()
        client = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        isPaired = false
        peerPublicKey = nil
    }

    public func sendAssistantMessage(_ text: String) async {
        guard let client else { return }
        let envelope = RemoteEnvelope.assistantMessage(text: text)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await client.send(signed)
        } catch {
            lastError = "Mesaj imzalanamadı: \(error.localizedDescription)"
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
                // Handshake öncesi başka envelope → sessizce drop.
                return
            }
            peerPublicKey = pubkey
            isPaired = true
            return
        }

        guard let peer = peerPublicKey,
              EnvelopeSigner.verify(envelope, with: peer)
        else {
            // Geçersiz imza → drop. (UI'a yansıtmıyoruz — log'a yazılabilir.)
            return
        }

        switch envelope.type {
        case .userMessage:
            if let text = envelope.payload?.text, !text.isEmpty {
                inbound.yield(text)
            }
        default:
            break
        }
    }
}
