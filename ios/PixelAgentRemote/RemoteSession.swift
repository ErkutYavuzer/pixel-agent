import CryptoKit
import Foundation
import UIKit
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

    @Published var activeSubagents: [SubagentStatusPayload] = []
    @Published var cpuUsage: Double = 0.0
    @Published var ramUsage: Double = 0.0
    @Published var activeWindow: String = ""
    @Published var availableBackends: [String] = []
    @Published var availableModels: [String: [String]] = [:]
    @Published var selectedBackend: String = ""
    @Published var selectedModel: String = ""
    @Published var planMode: Bool = false
    @Published var latestScreenshot: UIImage? = nil
    /// **Sprint 23 (v0.2.48):** Mac coordinator'ın `WireLatencyTracker` ile
    /// ölçtüğü son round-trip latency (ms). `hostStatus` veya `hostStatusDelta`
    /// envelope'ında geliyor (3sn periyodik delta loop). UI'da Mac Paneli
    /// "Ekran Resmi" section'unda badge olarak gösterilir, görselleştirme
    /// `isStreamingScreenshots` gate'iyle.
    /// **Sprint 24 (v0.2.49):** Per-frame `screenshotPayload.wireLatencyMs`
    /// embed yolu ile de güncellenir (~1Hz, hostStatus path'ından daha güncel).
    @Published var screenshotWireLatencyMs: Int? = nil
    /// **Sprint 25 (v0.2.50):** Son N latency ölçümünün ring buffer'ı —
    /// Mac Paneli'nde sparkline (trend grafiği) için. Per-frame envelope
    /// geldiğinde `LatencySparkline.push` ile append; stream durunca
    /// `stopScreenshotStream` temizler. Sabit `Self.wireLatencyHistoryMax`
    /// = 20 frame (~20 sn @ 1Hz default).
    @Published var wireLatencyHistory: [Int] = []
    static let wireLatencyHistoryMax = 20
    /// C12: Son tool call event'leri (en yeni ilk). Ring buffer ~30 kayıt.
    @Published var recentToolCalls: [ToolCallEventPayload] = []
    /// **Sprint 5 (iOS history viewer):** Mac'ten alınan arşiv listesi.
    /// `requestArchiveList()` sonrası `archiveListResponse` ile dolar.
    @Published var archiveEntries: [ArchiveEntryPayload] = []
    /// **Sprint 5:** Seçilen arşivin mesajları. `requestArchive(id:)`
    /// sonrası `archiveLoadResponse` ile dolar.
    @Published var loadedArchiveMessages: [Message] = []
    @Published var isLoadingArchives: Bool = false
    /// **Sprint 11 (v0.2.36):** Bağlantı kopukken bir sonraki reconnection
    /// denemesinin yapılacağı an. Banner buradan elapsed countdown gösterir
    /// (TimelineView). nil → şu an deneme yapılmıyor (loop bekleme arası
    /// veya bağlantı aktif).
    @Published var nextReconnectAt: Date? = nil
    /// **Sprint 15 (v0.2.40):** Continuous screenshot stream aktif mi.
    /// UI toggle bu state'i `startScreenshotStream` / `stopScreenshotStream`
    /// ile değiştirir; Mac side bağımsız state tutar, iOS optimistic.
    @Published var isStreamingScreenshots: Bool = false

    /// **Sprint 35 (v0.2.62):** Reconnect loop sürekli fail ediyorsa veya
    /// Mac side signing key/code değişmişse `true` olur — UI prominent
    /// "Mac eşleştirmesi değişmiş olabilir — QR'ı Yeniden Tara" banner'ı
    /// gösterir. `ReconnectAttemptTracker.isPairingStaleSuspected`'ın ayna'sı,
    /// SwiftUI binding için @Published mirror.
    @Published var pairingStaleSuspected: Bool = false

    private var transport: (any RemoteTransport)?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    /// **Sprint 35 (v0.2.62):** Connect/verify fail sayaçları. Threshold
    /// aşıldığında `pairingStaleSuspected` true — UI auto-recovery prompt.
    private var attemptTracker = ReconnectAttemptTracker()

    /// **Sprint 35 (v0.2.62):** Connect başarılı olduktan sonra ilk
    /// verify-passed envelope için bekleme task'i. 8 saniye içinde gelmezse
    /// silent fail (key mismatch) → `recordVerifyFailure()`.
    private var readyTimeoutTask: Task<Void, Never>?

    /// **Sprint 35 (v0.2.62):** Aktif bağlantıda en az bir verify-passed
    /// envelope alındı mı? `establishConnection` başında false; ilk
    /// `handle()` verify pass'inde true + `attemptTracker.recordSuccess()`.
    private var hasReceivedVerifiedEnvelope: Bool = false

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

    private func cleanActiveConnection() async {
        await transport?.disconnect()
        transport = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        transportLabel = nil
        macPublicKey = nil
        mascotState = .idle
        lastError = nil
        // Sprint 11 (A): Successful connection veya manual disconnect →
        // pending countdown bitsin (banner clean state).
        nextReconnectAt = nil
        // Sprint 15 (v0.2.40): Stream state temizle — disconnect sonrası
        // Mac side coordinator zaten task'i cancel eder (transport down),
        // iOS UI'da "Live" toggle otomatik off görünmeli.
        isStreamingScreenshots = false
    }

    func connect(pairing: PairingInfo) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        await establishConnection(pairing: pairing)
    }

    private func establishConnection(pairing: PairingInfo) async {
        await cleanActiveConnection()

        guard let macKeyData = Data(base64Encoded: pairing.macPublicKey),
              let macKey = try? Curve25519.Signing.PublicKey(rawRepresentation: macKeyData)
        else {
            lastError = "Eşleşme bilgisinde Mac public key geçersiz. QR'ı yeniden tarayın."
            // **Sprint 35 (v0.2.62):** PairingInfo bozuk = stale pairing
            // sentinel'i; UI prompt'u hemen tetiklensin.
            attemptTracker.recordVerifyFailure()
            pairingStaleSuspected = attemptTracker.isPairingStaleSuspected
            return
        }
        self.macPublicKey = macKey

        let transport = transportFactory(pairing)
        self.transport = transport
        self.pairing = pairing

        // **Sprint 35 (v0.2.62):** Yeni connect denemesi başlıyor —
        // ready timeout için flag/task reset.
        hasReceivedVerifiedEnvelope = false
        readyTimeoutTask?.cancel()

        do {
            let stream = try await transport.connect()
            isConnected = true
            lastError = nil
            transportLabel = await Self.label(for: transport)
            Self.savePairing(pairing)

            // Handshake: hello envelope (unsigned — chicken-and-egg).
            try await transport.send(RemoteEnvelope.hello(publicKey: publicKeyBase64))

            // **Sprint 35 (v0.2.62):** Connect başarılı — ready timeout
            // task'i başlat. 8 saniye içinde verify-passed envelope gelmezse
            // sessiz key mismatch demektir; verify counter artırılır.
            readyTimeoutTask = Task { [weak self] in
                let seconds = ReconnectAttemptTracker.defaultReadyTimeoutSeconds
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.handleReadyTimeout()
            }

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
            // **Sprint 35 (v0.2.62):** Connect fail counter — exponential
            // backoff ile threshold'a ulaşırsa UI stale prompt'u açar.
            attemptTracker.recordConnectFailure()
            pairingStaleSuspected = attemptTracker.isPairingStaleSuspected
            await self.onConnectionLost(error: error)
        }
    }

    /// **Sprint 35 (v0.2.62):** Connect başarılı olduktan sonra ilk
    /// verify-passed envelope gelmezse (default 8 saniye) çağrılır.
    /// Mac signing key değiştiyse `EnvelopeSigner.verify` her envelope'ı
    /// sessizce reject eder — bu timeout o durumu yakalar.
    private func handleReadyTimeout() async {
        guard !hasReceivedVerifiedEnvelope else { return }
        attemptTracker.recordVerifyFailure()
        pairingStaleSuspected = attemptTracker.isPairingStaleSuspected
    }

    /// **Sprint 35 (v0.2.62):** UI'dan tetiklenir — saved pairing'i
    /// UserDefaults'tan sil, tracker sayaçlarını sıfırla, `pairing = nil`
    /// → `ContentView` otomatik `PairingScannerView`'a düşer. Kullanıcı
    /// yeni QR'ı tarar, fresh pairing UserDefaults'a yazılır.
    func forgetAndRescan() async {
        await disconnect(forget: true)
        attemptTracker = ReconnectAttemptTracker()
        pairingStaleSuspected = false
        hasReceivedVerifiedEnvelope = false
        readyTimeoutTask?.cancel()
        readyTimeoutTask = nil
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

    func updateConfig(backend: String, model: String, planMode: Bool) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.clientConfig(backend: backend, model: model, planMode: planMode)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Konfigürasyon güncellenemedi: \(error.localizedDescription)"
        }
    }

    func cancelSubagent(id: String) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.clientAction(type: "cancelSubagent", targetID: id)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Subagent sonlandırılamadı: \(error.localizedDescription)"
        }
    }

    func requestScreenshot() async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.clientAction(type: "requestScreenshot")
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Ekran resmi istenemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 5 (iOS history viewer):** Mac'ten arşiv listesi iste.
    /// `archiveListResponse` envelope geldiğinde `archiveEntries` dolar.
    func requestArchiveList() async {
        guard let transport else { return }
        isLoadingArchives = true
        loadedArchiveMessages = []
        let envelope = RemoteEnvelope.archiveListRequest()
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            isLoadingArchives = false
            lastError = "Arşiv listesi istenemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 5:** Mac'ten belirli bir arşivin mesajlarını iste.
    /// `archiveLoadResponse` envelope geldiğinde `loadedArchiveMessages` dolar.
    func requestArchive(id: String) async {
        guard let transport else { return }
        loadedArchiveMessages = []
        let envelope = RemoteEnvelope.archiveLoadRequest(id: id)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Arşiv yüklenemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 6 (iOS → Mac archive load):** iOS'tan tetiklenen "Bu sohbete
    /// Mac'te devam et" eylemi. Mac arşivi aktif backend'e yükler (mevcut
    /// aktif sohbet arşivlenir, hedef arşiv yeni aktif olur).
    ///
    /// `clientAction` envelope'unu reuse — yeni envelope type'a gerek yok.
    /// `actionType: "loadArchive"`, `targetID:` arşivin URL string'i.
    /// Mac side `onClientActionReceived` handler'da branch eklendi.
    func requestArchiveLoadIntoActive(id: String) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.clientAction(type: "loadArchive", targetID: id)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Arşiv yükleme isteği gönderilemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 10 (v0.2.35):** iOS → Mac. Bir arşivi yeniden adlandır.
    /// `newTitle` nil veya whitespace-only → custom title kaldırılır
    /// (Mac side `ConversationStore.renameArchive` whitespace-only'i
    /// kaldırma olarak yorumlar). Mac handler işlem sonrası otomatik
    /// `archiveListResponse` döner — `archiveEntries` güncel görünür.
    func renameArchive(id: String, newTitle: String?) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.archiveRename(archiveID: id, newTitle: newTitle)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Yeniden adlandırma gönderilemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 10 (v0.2.35):** iOS → Mac. Bir arşivin tag listesini ayarla.
    /// `tags` nil veya boş → tüm tag'ler kaldırılır. Caller normalize
    /// edilmiş liste göndermeli (TagNormalizer karşılığı iOS'ta yok —
    /// Mac side ek normalize uygulamıyor, iOS girdi disiplinli olmalı).
    /// Mac handler işlem sonrası otomatik `archiveListResponse` döner.
    func setArchiveTags(id: String, tags: [String]?) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.archiveSetTags(archiveID: id, tags: tags)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Etiket güncellenmesi gönderilemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 12 (v0.2.37):** iOS → Mac. Bir arşivi kalıcı olarak sil
    /// (JSONL + sidecar). Geri alınamaz; UI confirmation alert göstermeli.
    /// Mac handler işlem sonrası otomatik `archiveListResponse` döner —
    /// entry list'ten kaybolur.
    func deleteArchive(id: String) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.archiveDelete(archiveID: id)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
        } catch {
            lastError = "Arşiv silme isteği gönderilemedi: \(error.localizedDescription)"
        }
    }

    /// **Sprint 15 (v0.2.40):** iOS → Mac. Continuous screenshot stream
    /// başlat. Mac her `intervalMs`'de bir screenshot çekip
    /// `screenshotPayload` envelope push'lar; `latestScreenshot` her tick'te
    /// güncellenir. UI toggle aktiflerken bu çağrı yapılır, `isStreaming-
    /// Screenshots` optimistic true set'lenir.
    ///
    /// `intervalMs` 250-5000 arası clamp edilir (envelope decoder + Mac
    /// coordinator). Default 1000ms (1Hz, bandwidth-friendly).
    func startScreenshotStream(intervalMs: Int = 1000) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.screenshotStreamStart(intervalMs: intervalMs)
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
            isStreamingScreenshots = true
        } catch {
            lastError = "Screenshot stream başlatılamadı: \(error.localizedDescription)"
        }
    }

    /// **Sprint 15 (v0.2.40):** iOS → Mac. Aktif stream'i durdur. Mac
    /// coordinator task'i cancel eder, push akışı biter.
    /// **Sprint 23 (v0.2.48):** `screenshotWireLatencyMs` da reset — bir
    /// sonraki başlangıçta stale değer briefly görünmesin.
    /// **Sprint 25 (v0.2.50):** `wireLatencyHistory` ring buffer da temizlenir
    /// — sparkline boş başlasın.
    func stopScreenshotStream() async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.screenshotStreamStop()
        do {
            let signed = try EnvelopeSigner.sign(envelope, with: signingKey)
            try await transport.send(signed)
            isStreamingScreenshots = false
            screenshotWireLatencyMs = nil
            wireLatencyHistory.removeAll()
        } catch {
            lastError = "Screenshot stream durdurulamadı: \(error.localizedDescription)"
        }
    }

    /// **Sprint 22 (v0.2.47):** iOS → Mac. Bir `screenshotPayload` frame'ini
    /// frameID ile ACK'le. Mac coordinator round-trip latency'sini hesaplar.
    /// Best-effort: imzalama / send hatası sessizce yutulur (bir frame
    /// kaybı adaptive rate için minor; local latency fallback'i devreye
    /// girer).
    private func sendScreenshotFrameAck(frameID: String) async {
        guard let transport else { return }
        let envelope = RemoteEnvelope.screenshotFrameAck(frameID: frameID)
        guard let signed = try? EnvelopeSigner.sign(envelope, with: signingKey) else { return }
        try? await transport.send(signed)
    }

    func disconnect(forget: Bool = true) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        
        await cleanActiveConnection()
        
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

                // Sprint 11 (A): Banner countdown için reconnection denemesinin
                // hedef anını publish et. Sleep tamamlanınca nil — "şu an
                // bağlanıyor" görsel feedback ek devirde set'lenir.
                let attemptAt = Date().addingTimeInterval(delaySeconds)
                await MainActor.run { [weak self] in
                    self?.nextReconnectAt = attemptAt
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                } catch {
                    break // Task cancelled
                }

                if Task.isCancelled { break }

                await MainActor.run { [weak self] in
                    self?.nextReconnectAt = nil
                }

                await self.establishConnection(pairing: pairing)

                if await self.isConnected {
                    break
                } else {
                    delaySeconds = min(delaySeconds * 2, maxDelaySeconds)
                }
            }

            await MainActor.run { [weak self] in
                self?.reconnectTask = nil
                self?.nextReconnectAt = nil
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
            // **Sprint 35 (v0.2.62):** Verify fail = Mac signing key
            // değişmiş olabilir. Counter artır; threshold aşılırsa UI
            // prominent banner gösterir.
            attemptTracker.recordVerifyFailure()
            pairingStaleSuspected = attemptTracker.isPairingStaleSuspected
            return
        }

        // **Sprint 35 (v0.2.62):** İlk verify-passed envelope —
        // bağlantı sağlıklı. Ready timeout iptal et, tracker reset.
        if !hasReceivedVerifiedEnvelope {
            hasReceivedVerifiedEnvelope = true
            readyTimeoutTask?.cancel()
            readyTimeoutTask = nil
            attemptTracker.recordSuccess()
            pairingStaleSuspected = false
        }

        switch envelope.type {
        case .userMessage:
            // **Sprint 33 (v0.2.59):** Mac kullanıcısının composer'a yazdığı
            // mesaj. iOS'a yansıt. UUID dedup ile iOS-originated mesajların
            // Mac echo'su tekrar append edilmez (iOS zaten send(text:)'te
            // local messages array'ine eklemişti).
            if let text = envelope.payload?.text, !text.isEmpty,
               let msgIDString = envelope.payload?.messageID,
               let msgID = UUID(uuidString: msgIDString) {
                let alreadyExists = messages.contains(where: { $0.id == msgID })
                if !alreadyExists {
                    let userMsg = Message(id: msgID, role: .user, text: text)
                    messages.append(userMsg)
                }
            }
        case .conversationSync:
            // **Sprint 33 (v0.2.60):** Mac aktif conversation snapshot.
            // iOS messages array'ini bu liste ile **replace** et — Mac
            // backend (claude/codex/gemini) değiştiğinde aktif sohbete
            // senkron olur. Tek-yön replace; iOS local optimistic mesajlar
            // (mac henüz işlememişse) bu replace ile kaybolabilir — kullanıcı
            // yeniden gönderebilir.
            if let snapshot = envelope.payload?.conversationMessages {
                self.messages = snapshot
                self.mascotState = .idle
            }
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
        case .hostStatus, .hostStatusDelta:
            // Sprint 19 (v0.2.44): hostStatusDelta aynı field-by-field merge
            // pattern'i kullanır — handler zaten delta-aware (her field için
            // `if let` guard). Aynı switch arm: hostStatus full snapshot tüm
            // field'ları doldurur; hostStatusDelta sadece değişenleri.
            if let payload = envelope.payload {
                if let backend = payload.selectedBackend {
                    self.selectedBackend = backend
                }
                if let model = payload.selectedModel {
                    self.selectedModel = model
                }
                if let plan = payload.planMode {
                    self.planMode = plan
                }
                if let backends = payload.availableBackends {
                    self.availableBackends = backends
                }
                if let models = payload.availableModels {
                    self.availableModels = models
                }
                if let subagents = payload.activeSubagents {
                    self.activeSubagents = subagents
                }
                if let metrics = payload.systemMetrics {
                    self.cpuUsage = metrics.cpuUsage
                    self.ramUsage = metrics.ramUsage
                    self.activeWindow = metrics.activeWindow
                }
                // Sprint 23 (v0.2.48): wire latency badge field. Delta nil =
                // "değişmedi" — guard `if let` ile sadece dolu değerler merge,
                // önceki ölçüm korunur. Stream durduğunda Mac'in nil'lemesi
                // delta'da nil olarak gelir ("unchanged" semantiği); iOS UI
                // badge'i `isStreamingScreenshots`'a göre gizler.
                if let latency = payload.screenshotWireLatencyMs {
                    self.screenshotWireLatencyMs = latency
                }
            }
        case .screenshotPayload:
            if let base64 = envelope.payload?.base64Image,
               let data = Data(base64Encoded: base64),
               let image = UIImage(data: data) {
                self.latestScreenshot = image
            }
            // Sprint 22 (v0.2.47): frameID varsa ACK gönder. Mac coordinator
            // round-trip latency'sini ölçer. Eski Mac frameID göndermez →
            // ACK loop'u devreye girmez (graceful degradation).
            if let frameID = envelope.payload?.screenshotFrameID, !frameID.isEmpty {
                Task { [weak self] in
                    await self?.sendScreenshotFrameAck(frameID: frameID)
                }
            }
            // Sprint 24 (v0.2.49): per-frame wire latency embed. Bu envelope
            // önceki frame'in ACK round-trip ölçümünü taşır — Mac Paneli badge
            // 3sn hostStatus lag yerine ~1Hz güncellenir. Sprint 23'ün
            // hostStatus path'i de hâlâ çalışıyor (fallback); en güncel
            // değer kazanır — bu envelope per-frame geldiği için çoğu zaman
            // o.
            // Sprint 25 (v0.2.50): ring buffer'a da push — sparkline trendi.
            if let latency = envelope.payload?.screenshotWireLatencyMs {
                self.screenshotWireLatencyMs = latency
                LatencySparkline.push(
                    latency,
                    into: &self.wireLatencyHistory,
                    maxCount: Self.wireLatencyHistoryMax
                )
            }
        case .toolCallEvent:
            // C12: Mac MCP bridge bir tool çağırdı — ring buffer'ı en yeni
            // ilk olacak şekilde güncelle, 30 kayıttan fazlasını at.
            if let event = envelope.payload?.toolCallEvent {
                recentToolCalls.insert(event, at: 0)
                if recentToolCalls.count > 30 {
                    recentToolCalls = Array(recentToolCalls.prefix(30))
                }
            }
        case .archiveListResponse:
            // Sprint 5: Mac'in arşiv listesi cevabı.
            if let entries = envelope.payload?.archiveEntries {
                archiveEntries = entries
            }
            isLoadingArchives = false
        case .archiveLoadResponse:
            // Sprint 5: belirli arşivin mesajları.
            if let messages = envelope.payload?.archiveMessages {
                loadedArchiveMessages = messages
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
