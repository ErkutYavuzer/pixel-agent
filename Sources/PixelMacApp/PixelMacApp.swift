import Darwin
import PixelBackends
import PixelComputerUse
import PixelCore
import PixelLAN
import PixelMemory
import PixelRemote
import PixelSubagent
import PixelTools
import PixelMCPServer
import PixelVoice
import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            RootView()
                .frame(minWidth: 520, minHeight: 400)
        }
        // B1: ⌘, ile açılan standart macOS Preferences penceresi.
        // 4 tab: Genel / Modeller / Bağlantı / İzinler.
        Settings {
            SettingsView()
        }
        .commands {
            // ⌘N standart "New Window" yerine yeni sohbet açar — pencere
            // çoğaltma desteklemiyoruz, single-window-multi-document mantığı
            // yerine aktif sütun(lar)ın conversationStore'unu sıfırlar.
            CommandGroup(replacing: .newItem) {
                Button("Yeni Sohbet") { AppCommand.newConversation.post() }
                    .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Sohbet") {
                Button("Plan Modunu Aç/Kapat") { AppCommand.togglePlanMode.post() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Tek/Çift Mod Değiştir") { AppCommand.toggleChatMode.post() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}

struct RootView: View {
    @State private var backends: [CLIKind: CLIBackend]
    @State private var conversationStores: [CLIKind: ConversationStore] = [:]
    /// **Sprint 36 (v0.2.63):** Cross-session persistent memory — tek
    /// instance, backend'den bağımsız (memory kullanıcıya ait). Init'te
    /// fail olursa nil → injection devre dışı, chat normal çalışır.
    @State private var memoryStore: MemoryStore?
    /// **Sprint 51 (v0.2.80):** Self-improving skill store — memoryStore gibi
    /// tek instance, backend'den bağımsız. Fail olursa nil → skill injection
    /// devre dışı, chat normal çalışır.
    @State private var skillStore: SkillStore?
    @State private var initErrorMessage: String?

    init() {
        _backends = State(initialValue: Self.resolveBackends())
        do {
            var stores: [CLIKind: ConversationStore] = [:]
            for kind in CLIKind.allCases {
                stores[kind] = try ConversationStore(fileName: "conversation-\(kind.rawValue).jsonl")
            }
            _conversationStores = State(initialValue: stores)
            // Sprint 36: Memory store opsiyonel — fail olursa chat çalışmaya devam.
            _memoryStore = State(initialValue: try? MemoryStore())
            // Sprint 51: Skill store opsiyonel — aynı şekilde best-effort.
            _skillStore = State(initialValue: try? SkillStore())
            _initErrorMessage = State(initialValue: nil)
        } catch {
            _conversationStores = State(initialValue: [:])
            _memoryStore = State(initialValue: nil)
            _skillStore = State(initialValue: nil)
            _initErrorMessage = State(initialValue: "Mesaj depoları açılamadı: \(error.localizedDescription)")
        }
    }

    var body: some View {
        Group {
            if let errorMessage = initErrorMessage {
                ErrorView(message: errorMessage, onRetry: retryStore)
            } else if backends.isEmpty {
                ErrorView(
                    message: BackendError.noBackendAvailable.errorDescription ?? "",
                    onRetry: rescan
                )
            } else if !conversationStores.isEmpty {
                ChatHost(backends: backends, conversationStores: conversationStores, memoryStore: memoryStore, skillStore: skillStore)
                    // Backends seti değişirse (rescan) ChatHost re-init → SubagentManager
                    // backendResolver closure'u yeni snapshot ile yakalanır. Trade-off:
                    // aktif subagent kartları kaybolur (rescan nadir bir event).
                    .id(Self.backendsKey(backends))
            } else {
                ErrorView(message: "Bilinmeyen başlatma hatası", onRetry: retryStore)
            }
        }
        .task {
            _ = await SystemNotifications.requestAuthorization()
            // Sprint 40 (v0.2.67): UNUserNotificationCenter delegate kayıt.
            // Bildirim tap'i yakalanıp ChatView draft inject edilir.
            NotificationActionDispatcher.shared.register()
            // Sprint 47 (v0.2.75): Relay launcher — npx wrangler dev otomatik.
            // UserDefaults toggle (default ON) kapalıysa no-op; production
            // Cloudflare URL kullanan kullanıcılar kapatabilir.
            await MainActor.run { Self.relayLauncher.start() }
            await Self.startControlBridge()
            // Sprint 38 (v0.2.65): Proaktif tetikleyiciler başlat.
            await Self.proactiveEngine.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // Sprint 47 (v0.2.75): App quit → wrangler subprocess SIGTERM.
            Self.relayLauncher.stop()
        }
    }

    /// **Sprint 38 (v0.2.65):** ProactiveEngine singleton — Mac app lifetime
    /// boyunca tek instance. App kapanışında implicit stop (process exit
    /// detector task'ları cancel eder).
    static let proactiveEngine = ProactiveEngine()

    /// **Sprint 47 (v0.2.75):** Relay launcher singleton — app launch'ta
    /// `npx wrangler dev` subprocess başlatır, app kapanırken kill eder.
    /// `@MainActor` ObservableObject — Settings UI binding için.
    @MainActor static let relayLauncher = RelayLauncher()

    /// **Sprint 42-45:** Voice provider factory — UserDefaults'tan aktif
    /// provider okur, runtime'da instance üretir. Apple (lokal), OpenAI
    /// Realtime (Sprint 43-44 full feature), Gemini Live (Sprint 45 full
    /// feature, ~10x ucuz alternatif).
    static func makeVoiceProvider() -> any PixelVoice.VoiceProvider {
        let raw = UserDefaults.standard.string(forKey: VoiceProviderKind.activeProviderDefaultsKey)
        let kind = raw.flatMap { VoiceProviderKind(rawValue: $0) } ?? .apple
        switch kind {
        case .apple:
            return AppleVoiceProvider(locale: Locale(identifier: "tr-TR"))
        case .openaiRealtime:
            // Sprint 44 (v0.2.71): MCP tool registry inject — voice-safe whitelist.
            let registry = BuiltInTools.makeRegistry()
            return OpenAIRealtimeProvider(toolRegistry: registry)
        case .geminiLive:
            // Sprint 45 (v0.2.72): Google Gemini Live WebSocket. Aynı
            // VoiceProvider abstraction, OpenAI'den ~10x ucuz. Aynı voice-safe
            // whitelist (GeminiToolBridge → OpenAIToolBridge.voiceSafeToolNames).
            let registry = BuiltInTools.makeRegistry()
            return GeminiLiveProvider(toolRegistry: registry)
        }
    }

    /// **Sprint 42:** Voice provider singleton — `makeVoiceProvider()`
    /// app launch'ta bir kez çağrılır. Provider değişince app restart
    /// gerekir (Settings'te uyarı).
    static let voiceProvider: any PixelVoice.VoiceProvider = makeVoiceProvider()

    /// MCP server'ın bundle-bağımlı tool isteklerini dinleyen Unix socket
    /// sunucusunu (`ControlSocketServer`) açılışta başlatır. Hata olursa
    /// sessizce yutulur — MCP server'ın saf-data tool'ları yine çalışır.
    private static func startControlBridge() async {
        do {
            try await Self.controlServer.start()
        } catch {
            // Hata olursa stderr'e bas; UI'ı bloke etmesin.
            FileHandle.standardError.write(
                Data("[pixel-agent] Control bridge başlatılamadı: \(error.localizedDescription)\n".utf8)
            )
        }
    }

    /// App lifetime boyunca tek instance — `WindowGroup` yeniden yaratılırsa
    /// `start()` idempotent (`running` flag).
    static let controlServer = ControlSocketServer()

    private func rescan() {
        backends = Self.resolveBackends()
    }

    private func retryStore() {
        do {
            var stores: [CLIKind: ConversationStore] = [:]
            for kind in CLIKind.allCases {
                stores[kind] = try ConversationStore(fileName: "conversation-\(kind.rawValue).jsonl")
            }
            conversationStores = stores
            initErrorMessage = nil
        } catch {
            conversationStores = [:]
            initErrorMessage = "Mesaj depoları açılamadı: \(error.localizedDescription)"
        }
    }

    private static func resolveBackends() -> [CLIKind: CLIBackend] {
        var resolved: [CLIKind: CLIBackend] = [:]
        let detector = CLIDetector()
        for (kind, path) in detector.available() {
            resolved[kind] = CLIBackend(kind: kind, executablePath: path)
        }
        return resolved
    }

    /// `.id(...)` modifier'ı için stabil key — backends key seti aynıysa string aynı,
    /// yeni/silinen CLI varsa string değişir → ChatHost re-init.
    private static func backendsKey(_ backends: [CLIKind: CLIBackend]) -> String {
        backends.keys.map(\.rawValue).sorted().joined(separator: ",")
    }
}

enum ChatMode: String, CaseIterable {
    case single
    case dual

    var displayName: String {
        switch self {
        case .single: return "Tek"
        case .dual: return "Çift"
        }
    }
}

struct ChatHost: View {
    let backends: [CLIKind: CLIBackend]
    let conversationStores: [CLIKind: ConversationStore]
    /// **Sprint 36 (v0.2.63):** Cross-session memory injection. nil ise chat
    /// normal çalışır, sadece `PlaybookLearner` prompt prefix atlanır.
    let memoryStore: MemoryStore?
    /// **Sprint 51 (v0.2.80):** Self-improving skill injection. nil ise skill
    /// section atlanır.
    let skillStore: SkillStore?
    @State private var selectedKind: CLIKind
    @State private var secondaryKind: CLIKind
    @State private var mode: ChatMode = .single
    @State private var showPairing: Bool = false
    @State private var showAbout: Bool = false
    @State private var showPermissions: Bool = false
    /// B2: Conversation history sidebar sheet.
    @State private var showHistory: Bool = false
    /// **Sprint 4 (B2 follow-up):** Archive yüklendiğinde aktif ChatView'ı
    /// force-recreate etmek için .id nonce'u. selectedKind aynı kalsa bile
    /// nonce değişince ChatViewModel @StateObject re-init olur ve
    /// `restoreIfNeeded()` JSONL'den yeni içeriği okur.
    @State private var archiveLoadNonce: Int = 0
    /// **Sprint 4 (connection-lost pulse):** Bağlantı düştüğünde set edilir.
    /// `ConnectionPillView.pulseTrigger`'a iletilir → ripple animasyonu.
    @State private var lastDisconnectAt: Date? = nil
    /// Önceki ConnectionPillState — transition detection için.
    @State private var previousPillState: ConnectionPillState = .notPaired
    @State private var permissionsStatus: ComputerUsePermissions.Status = ComputerUsePermissions.status()
    @State private var incomingFromRemote: String?
    @State private var planMode: Bool = false
    /// iOS dashboard'dan clientConfig geldiğinde 3.5s görünen banner. `nil`
    /// olduğunda gizli. Her yeni mesaj fresh UUID alır → SwiftUI transition
    /// re-trigger eder.
    @State private var configToast: RemoteConfigToast?
    @State private var configToastDismissTask: Task<Void, Never>?
    @StateObject private var remoteHost: RemoteHost
    @StateObject private var subagentManager: SubagentManager
    /// Sprint 15 (v0.2.40): iOS continuous screenshot stream task management.
    @StateObject private var screenshotStream = ScreenshotStreamCoordinator()

    /// **v0.2.22:** Model seçimi UserDefaults'a yazılır; boş ise
    /// `CLIBackend.defaultModelID` (env > hardcoded) devreye girer.
    @AppStorage("pixel.model.claude") private var claudeModel: String = ""
    @AppStorage("pixel.model.codex") private var codexModel: String = ""
    @AppStorage("pixel.model.gemini") private var geminiModel: String = ""

    /// Custom model giriş sheet'i için aktif kind. Identifiable → `.sheet(item:)`.
    @State private var customModelKind: CLIKind?
    @State private var customModelDraft: String = ""

    /// **Sprint 47 (v0.2.75):** Resolution chain → `RelayURLResolver`:
    /// 1. UserDefaults `pixel.relay.customURL` (Settings'ten kullanıcı override)
    /// 2. `PIXEL_RELAY_URL` env var (geriye uyumlu)
    /// 3. Production Cloudflare URL (`wrangler deploy` sonrası)
    /// 4. LAN IP (en0/en1 auto-detect)
    /// 5. localhost fallback
    static var defaultRelayURL: String {
        RelayURLResolver.resolve()
    }

    private static func detectLANIPv4() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let interface = current.pointee
            guard let addr = interface.ifa_addr else { continue }
            let family = addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count),
                        nil, 0, NI_NUMERICHOST)
            let ip = String(cString: hostname)
            if !ip.isEmpty, ip != "127.0.0.1" {
                address = ip
                break
            }
        }
        return address
    }

    init(backends: [CLIKind: CLIBackend], conversationStores: [CLIKind: ConversationStore], memoryStore: MemoryStore? = nil, skillStore: SkillStore? = nil) {
        self.backends = backends
        self.conversationStores = conversationStores
        self.memoryStore = memoryStore
        self.skillStore = skillStore
        let primary = CLIKind.allCases.first(where: { backends[$0] != nil }) ?? .gemini
        let secondary = CLIKind.allCases.first(where: { backends[$0] != nil && $0 != primary }) ?? primary
        _selectedKind = State(initialValue: primary)
        _secondaryKind = State(initialValue: secondary)
        // Mac LAN advertise + relay paralel — iOS hangisinden gelirse alırız.
        // Builder closure pairingCode/publicKey'i RemoteHost'tan alır (ADR-0023).
        let relayURL = Self.defaultRelayURL
        _remoteHost = StateObject(
            wrappedValue: RemoteHost(
                relayURL: relayURL,
                transportBuilder: { code, _ in
                    let lan = LANServerTransport(configuration: .init(serviceName: nil))
                    if let url = URL(string: relayURL) {
                        let relay = RelayTransport(relayURL: url, pairingCode: code, role: .mac)
                        return MergeTransport(transports: [lan, relay])
                    } else {
                        return MergeTransport(transports: [lan])
                    }
                }
            )
        )

        // Subagent havuzu — backendResolver closure backends snapshot'ını yakalar.
        // Rescan'da ChatHost re-init olunca (`.id(backendsKey)`) yeni snapshot ile yenilenir.
        _subagentManager = StateObject(
            wrappedValue: SubagentManager(
                maxConcurrent: 3,
                backendResolver: { [backends] kind in backends[kind] }
            )
        )
    }

    // MARK: - Model selection (v0.2.22)

    /// Verilen kind için aktif model ID. UserDefaults'tan okunan custom değer
    /// varsa onu döner; yoksa `CLIBackend.defaultModelID` zincirine (env >
    /// hardcoded) düşer.
    private func currentModel(for kind: CLIKind) -> String {
        let stored: String
        switch kind {
        case .claude: stored = claudeModel
        case .codex: stored = codexModel
        case .gemini: stored = geminiModel
        }
        if !stored.trimmingCharacters(in: .whitespaces).isEmpty {
            if kind == .gemini && (stored == "gemini-3.5-flash" || stored == "gemini-3.1-pro") {
                DispatchQueue.main.async {
                    self.geminiModel = ""
                }
                return CLIBackend.defaultModelID(for: kind)
            }
            return stored
        }
        return CLIBackend.defaultModelID(for: kind)
    }

    /// UserDefaults'a yeni model yazar. Boş string → varsayılana sıfırla
    /// (CLIBackend.defaultModelID env/hardcoded'a düşer).
    private func setModel(_ value: String, for kind: CLIKind) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .claude: claudeModel = trimmed
        case .codex: codexModel = trimmed
        case .gemini: geminiModel = trimmed
        }
    }

    /// ChatView/DualChatHost'a geçilecek dinamik backend — kind için executable
    /// path mevcut backends dict'inden, modelID UserDefaults/env/hardcoded
    /// zincirinden gelir. Model değişikliği `.id()` üzerinden ChatView'ı
    /// recreate eder, böylece `ChatViewModel` fresh backend ile yenilenir.
    private func currentBackend(for kind: CLIKind) -> CLIBackend? {
        guard let existing = backends[kind] else { return nil }
        return CLIBackend(
            kind: kind,
            executablePath: existing.executablePath,
            modelID: currentModel(for: kind)
        )
    }

    /// **Sprint 4 (connection-lost pulse):** Toolbar'daki pill'in current state'i.
    /// Hem render hem onChange(of:) için single source of truth.
    private var currentPillState: ConnectionPillState {
        ConnectionPillState.from(
            isPaired: remoteHost.isPaired,
            isConnected: remoteHost.isConnected
        )
    }

    /// **Sprint 4 (B2 follow-up):** ConversationHistoryView'dan "Yükle" çağrısı
    /// gelince çalışır. Mevcut backend'in store'unu archive ile değiştirir;
    /// gerekirse backend'i de switch eder. `archiveLoadNonce` artırılır →
    /// ChatView .id() değişir → ChatViewModel re-init → restoreIfNeeded()
    /// archive mesajlarını JSONL'den okur.
    private func loadArchive(_ entry: ArchivedConversationEntry) async {
        guard let kind = CLIKind(rawValue: entry.backendKind),
              let store = conversationStores[kind] else { return }
        do {
            try await store.replaceWithArchive(entry)
            await MainActor.run {
                selectedKind = kind
                archiveLoadNonce += 1
            }
        } catch {
            await MainActor.run {
                showConfigToast(message: "⚠️ Arşiv yüklenemedi: \(error.localizedDescription)")
            }
        }
    }

    /// **Sprint 6 (iOS → Mac archive load):** iOS'tan gelen "loadArchive"
    /// clientAction handler. URL string'i parse edip backend kind'ı çözer,
    /// mevcut `loadArchive(_:)` helper'ına delege eder. Persistence layer
    /// `replaceWithArchive` URL-only çağrı için sadece `entry.id` ve
    /// `entry.backendKind` kullanır; diğer field'lar dummy verilir.
    private func loadArchiveByURLString(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        let filename = url.lastPathComponent
        guard let parsed = ArchivedConversationParser.parseFilename(filename) else {
            await MainActor.run {
                showConfigToast(message: "⚠️ Arşiv adı parse edilemedi: \(filename)")
            }
            return
        }
        let entry = ArchivedConversationEntry(
            id: url,
            backendKind: parsed.kind,
            archivedAt: parsed.date,
            messageCount: 0,         // replaceWithArchive bu field'ı kullanmıyor
            firstUserSnippet: nil
        )
        await loadArchive(entry)
        // Kullanıcı bilgilendirmesi: iOS'tan tetiklenen yükleme görsel
        // olarak Mac top bar'da banner gösterir.
        await MainActor.run {
            showConfigToast(message: "📱 Telefon: bu sohbet aktif edildi (\(parsed.kind))")
        }
    }

    /// iOS clientConfig değişimlerinde 3.5s görünen banner. Yeni mesaj
    /// gelirse mevcut dismiss timer'ı iptal edilir → toast yenilenir.
    private func showConfigToast(message: String) {
        configToastDismissTask?.cancel()
        configToast = RemoteConfigToast(message: message)
        configToastDismissTask = Task { [toastID = configToast?.id] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Yarış: bu task uyurken yeni bir toast gelmiş olabilir;
                // o zaman aktif toast'un id'si değişir, eskiyi kapatmıyoruz.
                if configToast?.id == toastID {
                    configToast = nil
                }
            }
        }
    }

    /// `body`'nin chat alanı — Plan Mode panelinin yanına `HStack` ile
    /// yerleştirilen kısım. Tek/çift mode ayrımı burada yapılır.
    @ViewBuilder
    private var chatContent: some View {
        switch mode {
        case .single:
            if let backend = currentBackend(for: selectedKind),
               let store = conversationStores[selectedKind] {
                ChatView(
                    backend: backend,
                    backendKind: selectedKind,
                    conversationStore: store,
                    memoryStore: memoryStore,
                    skillStore: skillStore,
                    subagentManager: subagentManager,
                    incomingRemoteText: $incomingFromRemote,
                    planMode: planMode,
                    onAssistantChunk: { chunk, messageID in
                        Task { await remoteHost.sendAssistantChunk(chunk, messageID: messageID) }
                    },
                    onAssistantComplete: { text, messageID in
                        Task { await remoteHost.sendAssistantMessage(text, messageID: messageID) }
                    },
                    onUserMessage: { text, messageID in
                        // Sprint 33 (v0.2.59): Mac user mesajı iOS'a yansıt.
                        // ChatView incomingRemoteText path'ından gelen iOS-
                        // originated mesajlar broadcastToRemote=false ile bunu
                        // tetiklemez (loop önleme).
                        Task { await remoteHost.sendUserMessage(text, messageID: messageID) }
                    },
                    onSnapshotBroadcast: { messages in
                        // Sprint 33 (v0.2.60): Backend/model değişimi sonrası
                        // (.id rebuild → restoreIfNeeded), newConversation
                        // veya archive load → iOS'a aktif conversation snapshot.
                        Task { await remoteHost.sendConversationSync(messages) }
                    }
                )
                // Backend veya model değişiminde ChatViewModel @StateObject
                // sıfırlansın diye .id'yi (kind, model) çiftine bağla.
                .id("\(selectedKind.rawValue):\(currentModel(for: selectedKind)):n\(archiveLoadNonce)")
            } else {
                MissingBackendView(kind: selectedKind)
            }

        case .dual:
            if let leftBackend = currentBackend(for: selectedKind),
               let rightBackend = currentBackend(for: secondaryKind) {
                DualChatHost(
                    leftBackend: leftBackend,
                    rightBackend: rightBackend,
                    leftKind: selectedKind,
                    rightKind: secondaryKind,
                    leftTitle: selectedKind.displayName,
                    rightTitle: secondaryKind.displayName,
                    leftStoreFileName: "conversation-\(selectedKind.rawValue).jsonl",
                    rightStoreFileName: "conversation-\(secondaryKind.rawValue).jsonl",
                    memoryStore: memoryStore,
                    skillStore: skillStore,
                    subagentManager: subagentManager,
                    planMode: planMode
                )
                .id("\(selectedKind.rawValue):\(currentModel(for: selectedKind))-\(secondaryKind.rawValue):\(currentModel(for: secondaryKind)):n\(archiveLoadNonce)")
            } else {
                MissingBackendView(kind: backends[selectedKind] == nil ? selectedKind : secondaryKind)
            }
        }
    }

    @ViewBuilder
    private func modelPicker(for kind: CLIKind) -> some View {
        Menu {
            ForEach(ModelCatalog.knownModels(for: kind), id: \.self) { model in
                Button {
                    setModel(model, for: kind)
                } label: {
                    HStack {
                        Text(model)
                        if currentModel(for: kind) == model {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Özel ID…") {
                customModelDraft = currentModel(for: kind)
                customModelKind = kind
            }
            Button("Varsayılana sıfırla") {
                setModel("", for: kind)
            }
        } label: {
            Label(currentModel(for: kind), systemImage: "cpu")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(minWidth: 120, maxWidth: 220)
        .help("Model — \(kind.displayName)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Mod", selection: $mode) {
                    ForEach(ChatMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 110)

                Picker(mode == .single ? "Backend" : "Sol", selection: $selectedKind) {
                    ForEach(CLIKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                // v0.2.22: aktif (sol) backend için model picker.
                modelPicker(for: selectedKind)

                if mode == .dual {
                    Picker("Sağ", selection: $secondaryKind) {
                        ForEach(CLIKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    // v0.2.22: sağ backend için model picker.
                    modelPicker(for: secondaryKind)
                }

                Spacer()

                Toggle(isOn: $planMode) {
                    Label("Plan", systemImage: "list.bullet.clipboard")
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.button)
                .help(
                    selectedKind == .claude
                        ? "Plan modu — sadece okuma/araştırma tool'ları (Claude --permission-mode plan)"
                        : "Plan modu yalnızca Claude için aktif; \(selectedKind.displayName) bu bayrağı yoksayar"
                )

                ConnectionPillView(
                    state: currentPillState,
                    pulseTrigger: lastDisconnectAt,
                    onTap: { showPairing = true }
                )
                .onChange(of: currentPillState) { oldState, newState in
                    // Sprint 4: .connected → .disconnected geçişinde pulse tetikle.
                    if ConnectionTransitionDetector.isLossEvent(from: oldState, to: newState) {
                        lastDisconnectAt = Date()
                    }
                    previousPillState = newState
                }

                Button { showPermissions = true } label: {
                    Image(systemName: permissionsStatus.allGranted ? "lock.shield.fill" : "lock.shield")
                        .foregroundStyle(permissionsStatus.allGranted ? .green : .orange)
                }
                .buttonStyle(.borderless)
                .help(permissionsStatus.allGranted
                      ? "Computer Use izinleri tamam"
                      : "Computer Use izinleri eksik — tıkla")

                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Sohbet geçmişi (arşiv)")

                Button { showAbout = true } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Hakkında")

                Button { showPairing = true } label: {
                    Image(systemName: "qrcode")
                }
                .buttonStyle(.borderless)
                .help("Telefonla eşle (QR kod)")
                .disabled(mode == .dual)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

            HStack(spacing: 0) {
                chatContent
                    .frame(maxWidth: .infinity)

                if planMode {
                    Divider()
                    PlanModeToolListView(backendKind: selectedKind)
                        .frame(width: 240)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: planMode)
        }
        .overlay(alignment: .top) {
            if let toast = configToast {
                RemoteConfigToastView(message: toast.message)
                    .id(toast.id)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: configToast)
        .sheet(isPresented: $showHistory) {
            ConversationHistoryView(onLoadArchive: { entry in
                Task { await loadArchive(entry) }
            })
        }
        .sheet(isPresented: $showPairing) {
            PairingView(remoteHost: remoteHost)
        }
        .sheet(isPresented: $showAbout) {
            AboutView(relayURL: remoteHost.relayURL)
        }
        .sheet(isPresented: $showPermissions, onDismiss: {
            // Kullanıcı System Settings'ten dönerken durum değişmiş olabilir.
            permissionsStatus = ComputerUsePermissions.status()
        }) {
            PermissionsView()
        }
        // v0.2.22: Özel model ID giriş sheet'i.
        .sheet(item: $customModelKind) { kind in
            CustomModelSheet(
                kind: kind,
                draft: $customModelDraft,
                onSave: { setModel(customModelDraft, for: kind) }
            )
        }
        .task {
            // MCP bridge'in dispatch_subagent çağrılarını UI havuzuna yönlendir.
            // Rescan'da ChatHost re-init olunca yeni Manager attach edilir (son
            // attach kazanır — actor field idempotent).
            await RootView.controlServer.attach(subagentManager)
            // C12: bridge tool çağrıldığında iOS dashboard'a duyur.
            await RootView.controlServer.attachToolCallListener { [weak remoteHost] tool, status, summary in
                Task { await remoteHost?.sendToolCallEvent(toolName: tool, status: status, summary: summary) }
            }
            // Sprint 52 (F1): başarılı ui_click/ui_type → makro recorder (aktif kayıttaysa).
            await RootView.controlServer.attachUIActionListener { step in
                Task { @MainActor in MacroRecorder.shared.record(step) }
            }

            // Sprint 5: iOS archive viewer — handler'lar Mac arşivlerini
            // listele / yükle, response envelope ile dön.
            remoteHost.onArchiveListRequested = {
                guard let entries = try? ConversationStore.listAllArchives() else {
                    return []
                }
                return entries.map { entry in
                    ArchiveEntryPayload(
                        id: entry.id.absoluteString,
                        backendKind: entry.backendKind,
                        archivedAt: entry.archivedAt.timeIntervalSince1970,
                        messageCount: entry.messageCount,
                        firstUserSnippet: entry.firstUserSnippet,
                        customTitle: entry.customTitle,
                        tags: entry.tags.isEmpty ? nil : entry.tags
                    )
                }
            }
            remoteHost.onArchiveLoadRequested = { idString in
                guard let url = URL(string: idString) else { return [] }
                // Inline okuma — store actor'a gerek yok, sadece dosya read.
                let decoder = JSONDecoder()
                let data = (try? Data(contentsOf: url)) ?? Data()
                let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
                var messages: [Message] = []
                for line in lines {
                    if let m = try? decoder.decode(Message.self, from: Data(line)) {
                        messages.append(m)
                    }
                }
                return messages
            }

            // Sprint 10 (v0.2.35): iOS rename/tag dispatch handler'ları.
            // ConversationStore.renameArchive/setTags static nonisolated — view
            // instance'ı olmadan çağırılabilir. Otomatik refresh
            // RemoteHost.handle içinde, archiveListRequested ile yapılır.
            remoteHost.onArchiveRenameRequested = { idString, newTitle in
                guard let url = URL(string: idString) else { return }
                try? ConversationStore.renameArchive(at: url, title: newTitle)
            }
            remoteHost.onArchiveSetTagsRequested = { idString, tags in
                guard let url = URL(string: idString) else { return }
                // Defense in depth: iOS gönderse de Mac normalize eder
                // (trim+lowercase+dedup+sorted+30 char max). Mac UI ile
                // tutarlı sonuç garantiler.
                let normalized = tags.map { TagNormalizer.normalize($0) }
                try? ConversationStore.setTags(
                    (normalized?.isEmpty ?? true) ? nil : normalized,
                    for: url
                )
            }

            // Sprint 12 (v0.2.37): iOS archive delete dispatch handler'ı.
            remoteHost.onArchiveDeleteRequested = { idString in
                guard let url = URL(string: idString) else { return }
                try? ConversationStore.deleteArchive(at: url)
            }

            // Sprint 15 (v0.2.40): iOS screenshot stream handler'ları.
            // Start: coordinator task spawn'lar; her frame için sendScreenshot.
            // Stop: task cancel + isActive false. Inner closure'ya strong
            // `host` let snapshot — Swift 6 concurrent capture sending uyumu
            // ('weak var' captured-in-concurrent-closure hatasından kaçınır).
            //
            // Sprint 22 (v0.2.47): sendImage callback (base64, frameID).
            // Sprint 24 (v0.2.49): callback artık (base64, frameID, wireLatencyMs?)
            // alıyor — önceki frame'in ACK round-trip ölçümü her envelope'a
            // embed edilir; iOS Mac Paneli badge per-frame güncellenir.
            remoteHost.onScreenshotStreamStartRequested = { intervalMs in
                let host = remoteHost
                self.screenshotStream.start(intervalMs: intervalMs) { base64, frameID, wireLatencyMs in
                    await host.sendScreenshot(
                        base64Image: base64,
                        frameID: frameID,
                        wireLatencyMs: wireLatencyMs
                    )
                }
            }
            remoteHost.onScreenshotStreamStopRequested = {
                self.screenshotStream.stop()
            }

            // Sprint 22 (v0.2.47): iOS ACK callback — coordinator pending
            // map'inde frameID arar, eşleşirse wire-level latency hesaplar
            // ve bir sonraki adaptive tick'te kullanır.
            remoteHost.onScreenshotFrameAckReceived = { frameID, receivedAt in
                self.screenshotStream.recordAck(frameID: frameID, at: receivedAt)
            }

            remoteHost.onClientConfigReceived = { backend, model, plan in
                guard let kind = CLIKind(rawValue: backend) else { return }
                let oldBackend = self.selectedKind.rawValue
                let oldModel = self.currentModel(for: self.selectedKind)
                let oldPlan = self.planMode

                self.selectedKind = kind
                self.planMode = plan
                self.setModel(model, for: kind)

                if let message = RemoteConfigToastBuilder.buildMessage(
                    oldBackend: oldBackend, oldModel: oldModel, oldPlanMode: oldPlan,
                    newBackend: backend, newModel: model, newPlanMode: plan
                ) {
                    self.showConfigToast(message: message)
                }
            }

            remoteHost.onClientActionReceived = { [weak remoteHost] action, targetID in
                if action == "cancelSubagent", let idString = targetID {
                    if let session = subagentManager.sessions.first(where: { $0.id.value == idString }) {
                        subagentManager.cancel(session.id)
                    }
                } else if action == "requestScreenshot" {
                    Task {
                        do {
                            let result = try await ScreenshotCapture.capture(target: .activeDisplay)
                            if let jpegData = ImageEncoding.compressPNGToJPEG(data: result.pngData, quality: 0.5) {
                                let base64 = jpegData.base64EncodedString()
                                await remoteHost?.sendScreenshot(base64Image: base64)
                            }
                        } catch {
                            // Ignored / Logged in Faz 2
                        }
                    }
                } else if action == "loadArchive", let urlString = targetID {
                    // Sprint 6 (iOS → Mac archive load): iOS'tan "Bu sohbete
                    // devam et" tetiklendi. URL'i parse et, mevcut Mac
                    // loadArchive(_:) helper'ını çağır.
                    Task { await self.loadArchiveByURLString(urlString) }
                }
            }
        }
        .task {
            for await text in remoteHost.inboundTexts {
                incomingFromRemote = text
            }
        }
        // **Sprint 34 (v0.2.61):** App launch'ında auto-connect — Mac
        // dinlemeye başlasın, iOS saved pairing ile auto-reconnect olabilsin.
        // Önceden user PairingView açıp manuel "Bağlan" tıklamak zorundaydı.
        // pairingCode UserDefaults'tan stable yüklenir; iOS saved pairing
        // aynı code'u beklediği için match eder.
        .task {
            if !remoteHost.isConnected {
                await remoteHost.connect()
            }
        }
        // B5: menü çubuğundan ⌘⇧P / ⌘⇧M — toolbar'daki Toggle/Picker ile aynı
        // state'i değiştirir, böylece UI senkron kalır.
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.togglePlanMode.notificationName)) { _ in
            planMode.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.toggleChatMode.notificationName)) { _ in
            mode = (mode == .single) ? .dual : .single
        }
        // C10: Subagent cap'e takıldığında transient banner — config toast
        // ile aynı overlay slot'unu paylaşır (en son fire eden kazanır).
        .onChange(of: subagentManager.lastCapReachedAt) { _, newValue in
            guard newValue != nil else { return }
            let max = subagentManager.maxConcurrent
            showConfigToast(message: "⚠️ Subagent havuzu dolu (\(max)/\(max) aktif). Bir tanesi bitince tekrar deneyin.")
        }
        // Sprint 17 (v0.2.42): Stream cancellation upstream — RemoteHost
        // transport disconnect olunca (iOS uygulamada arka plan, network
        // kopma, manuel disconnect) coordinator task'i hemen cancel.
        // Önceki davranış: send fail loop iterasyonunda ~1 interval gecikme.
        .onChange(of: remoteHost.isConnected) { _, isConnected in
            if !isConnected && screenshotStream.isActive {
                screenshotStream.stop()
            }
        }
        .task {
            // **Sprint 19 (v0.2.44):** Delta-only push. Bir önceki snapshot'ı
            // tut, her tick'te diff hesapla; fark yoksa skip (bandwidth ~700
            // B/s → 0 idle, sadece değişikliklerde küçük delta).
            var lastSnapshot: HostStatusContent? = nil
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break
                }
                guard remoteHost.isConnected && remoteHost.isPaired else {
                    // Disconnect → bir sonraki connect'te full bootstrap delta
                    // gönderilsin diye snapshot'ı sıfırla.
                    lastSnapshot = nil
                    continue
                }

                let selectedBackendRaw = selectedKind.rawValue
                let selectedModelID = currentModel(for: selectedKind)
                let isPlan = planMode

                let backendsList = CLIKind.allCases.filter { backends[$0] != nil }.map { $0.rawValue }
                var modelsMap: [String: [String]] = [:]
                for kind in CLIKind.allCases {
                    if backends[kind] != nil {
                        modelsMap[kind.rawValue] = ModelCatalog.knownModels(for: kind)
                    }
                }

                let activeSubs = subagentManager.sessions.map { session in
                    SubagentStatusPayload(
                        id: session.id.value,
                        prompt: session.prompt,
                        status: session.status.displayLabel,
                        partialOutput: session.partialOutput,
                        startedAt: session.startedAt.timeIntervalSince1970
                    )
                }

                let activeWindowName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Bilinmiyor"
                let cpu = await SystemStats.shared.cpuUsagePercent()
                let ram = SystemStats.memoryUsagePercent()
                let metrics = SystemMetricsPayload(cpuUsage: cpu, ramUsage: ram, activeWindow: activeWindowName)

                // Sprint 23 (v0.2.48): stream aktifken son ölçülen wire
                // latency'i de snapshot'a koy. Stream durunca nil → delta
                // calculator önceki değerle eşitse skip (önceki ölçüm iOS'ta
                // stale kalır ama UI gate isStreamingScreenshots'ta).
                let wireLatency: Int? = screenshotStream.isActive
                    ? screenshotStream.lastWireLatencyMs
                    : nil
                let newSnapshot = HostStatusContent(
                    selectedBackend: selectedBackendRaw,
                    selectedModel: selectedModelID,
                    planMode: isPlan,
                    availableBackends: backendsList,
                    availableModels: modelsMap,
                    activeSubagents: activeSubs,
                    systemMetrics: metrics,
                    screenshotWireLatencyMs: wireLatency
                )

                if let delta = HostStatusDeltaCalculator.delta(from: lastSnapshot, to: newSnapshot) {
                    await remoteHost.sendHostStatusDelta(delta)
                    lastSnapshot = newSnapshot
                }
                // Fark yoksa skip — bandwidth idle.
            }
        }
    }
}

struct MissingBackendView: View {
    let kind: CLIKind

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("\(kind.displayName) CLI yüklü değil")
                .font(.headline)
            Text("\(kind.executableName) PATH'te veya bilinen yollarda bulunamadı.\nYükleyip uygulamayı yeniden başlatın.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// **v0.2.22:** Listede olmayan bir model ID'yi elle girmek için modal.
/// Kullanıcı catalog dışında bir model isterse (örn. nightly bir Gemini sürümü)
/// buradan yazıp kaydeder; sonraki gönderilerde geçerli olur.
struct CustomModelSheet: View {
    let kind: CLIKind
    @Binding var draft: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(kind.displayName) için özel model ID")
                .font(.headline)
            Text("CLI'a `--model <id>` olarak geçirilir. Doğrulama yok — yanlış ID 'not found' döner.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("ör. claude-opus-4-7-20251101", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }
            HStack {
                Button("İptal", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Kaydet") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private func commit() {
        onSave()
        dismiss()
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Başlatılamadı")
                .font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Tekrar dene", action: onRetry)
                .keyboardShortcut(.return)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
