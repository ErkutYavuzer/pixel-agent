import Darwin
import PixelBackends
import PixelComputerUse
import PixelCore
import PixelLAN
import PixelMemory
import PixelRemote
import PixelSubagent
import PixelTools
import SwiftUI

@main
struct PixelMacApp: App {
    var body: some Scene {
        WindowGroup("pixel-agent") {
            RootView()
                .frame(minWidth: 520, minHeight: 400)
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
    @State private var initErrorMessage: String?

    init() {
        _backends = State(initialValue: Self.resolveBackends())
        do {
            var stores: [CLIKind: ConversationStore] = [:]
            for kind in CLIKind.allCases {
                stores[kind] = try ConversationStore(fileName: "conversation-\(kind.rawValue).jsonl")
            }
            _conversationStores = State(initialValue: stores)
            _initErrorMessage = State(initialValue: nil)
        } catch {
            _conversationStores = State(initialValue: [:])
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
                ChatHost(backends: backends, conversationStores: conversationStores)
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
            await Self.startControlBridge()
        }
    }

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
    @State private var selectedKind: CLIKind
    @State private var secondaryKind: CLIKind
    @State private var mode: ChatMode = .single
    @State private var showPairing: Bool = false
    @State private var showAbout: Bool = false
    @State private var showPermissions: Bool = false
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

    /// **v0.2.22:** Model seçimi UserDefaults'a yazılır; boş ise
    /// `CLIBackend.defaultModelID` (env > hardcoded) devreye girer.
    @AppStorage("pixel.model.claude") private var claudeModel: String = ""
    @AppStorage("pixel.model.codex") private var codexModel: String = ""
    @AppStorage("pixel.model.gemini") private var geminiModel: String = ""

    /// Custom model giriş sheet'i için aktif kind. Identifiable → `.sheet(item:)`.
    @State private var customModelKind: CLIKind?
    @State private var customModelDraft: String = ""

    /// `PIXEL_RELAY_URL` env var varsa onu kullan; yoksa LAN IP (en0/en1) ile WebSocket URL üret;
    /// hiçbiri yoksa `ws://localhost:8787` (sadece Mac-local test için).
    static var defaultRelayURL: String {
        if let envURL = ProcessInfo.processInfo.environment["PIXEL_RELAY_URL"], !envURL.isEmpty {
            return envURL
        }
        if let lanIP = detectLANIPv4() {
            return "ws://\(lanIP):8787"
        }
        return "ws://localhost:8787"
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

    init(backends: [CLIKind: CLIBackend], conversationStores: [CLIKind: ConversationStore]) {
        self.backends = backends
        self.conversationStores = conversationStores
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
                    subagentManager: subagentManager,
                    incomingRemoteText: $incomingFromRemote,
                    planMode: planMode,
                    onAssistantChunk: { chunk, messageID in
                        Task { await remoteHost.sendAssistantChunk(chunk, messageID: messageID) }
                    },
                    onAssistantComplete: { text, messageID in
                        Task { await remoteHost.sendAssistantMessage(text, messageID: messageID) }
                    }
                )
                // Backend veya model değişiminde ChatViewModel @StateObject
                // sıfırlansın diye .id'yi (kind, model) çiftine bağla.
                .id("\(selectedKind.rawValue):\(currentModel(for: selectedKind))")
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
                    subagentManager: subagentManager,
                    planMode: planMode
                )
                .id("\(selectedKind.rawValue):\(currentModel(for: selectedKind))-\(secondaryKind.rawValue):\(currentModel(for: secondaryKind))")
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
                    state: ConnectionPillState.from(
                        isPaired: remoteHost.isPaired,
                        isConnected: remoteHost.isConnected
                    ),
                    onTap: { showPairing = true }
                )

                Button { showPermissions = true } label: {
                    Image(systemName: permissionsStatus.allGranted ? "lock.shield.fill" : "lock.shield")
                        .foregroundStyle(permissionsStatus.allGranted ? .green : .orange)
                }
                .buttonStyle(.borderless)
                .help(permissionsStatus.allGranted
                      ? "Computer Use izinleri tamam"
                      : "Computer Use izinleri eksik — tıkla")

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
                }
            }
        }
        .task {
            for await text in remoteHost.inboundTexts {
                incomingFromRemote = text
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
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break
                }
                guard remoteHost.isConnected && remoteHost.isPaired else { continue }

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

                await remoteHost.sendHostStatus(
                    selectedBackend: selectedBackendRaw,
                    selectedModel: selectedModelID,
                    planMode: isPlan,
                    availableBackends: backendsList,
                    availableModels: modelsMap,
                    activeSubagents: activeSubs,
                    systemMetrics: metrics
                )
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
