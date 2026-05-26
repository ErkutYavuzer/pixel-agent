import AppKit
import PixelBackends
import PixelComputerUse
import PixelMCPServer
import PixelMemory
import PixelVoice
import SwiftUI

/// macOS Settings scene — `⌘,` ile açılan standart "Preferences" penceresi
/// (B1). 4 tab: Genel / Modeller / Bağlantı / İzinler.
///
/// Settings scene `App.body` içinde `Settings { SettingsView() }` olarak
/// declare edilir; macOS otomatik olarak menu bar'a "pixel-agent ›
/// Settings…" ekler ve ⌘, shortcut'unu bağlar.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .frame(width: 540, height: 380)
    }

    @ViewBuilder
    private func tabContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .models: ModelsSettingsTab()
        case .connection: ConnectionSettingsTab()
        case .subagent: SubagentSettingsTab()
        case .memory: MemorySettingsTab()
        case .proactive: ProactiveSettingsTab()
        case .voice: VoiceSettingsTab()
        case .permissions: PermissionsSettingsTab()
        }
    }
}

// MARK: - Tab enum (testable)

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, models, connection, subagent, memory, proactive, voice, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Genel"
        case .models: return "Modeller"
        case .connection: return "Bağlantı"
        case .subagent: return "Subagent"
        case .memory: return "Hafıza"
        case .proactive: return "Proaktif"
        case .voice: return "Sesli Mod"
        case .permissions: return "İzinler"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .models: return "cpu"
        case .connection: return "wifi"
        case .subagent: return "person.2.crop.square.stack"
        case .memory: return "brain.head.profile"
        case .proactive: return "bell.badge"
        case .voice: return "mic"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @AppStorage("pixel.model.claude") private var claudeModel: String = ""
    @AppStorage("pixel.model.codex") private var codexModel: String = ""
    @AppStorage("pixel.model.gemini") private var geminiModel: String = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Sürüm", value: Self.appVersion)
                LabeledContent("Test sayısı", value: "586")
                LabeledContent("Lisans", value: "MIT")
            } header: {
                Text("Hakkında")
            }

            Section {
                LabeledContent("Depo dizini") {
                    HStack {
                        Text(Self.storageDirectory)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Aç") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: Self.storageDirectoryAbsolute)]
                            )
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Saklama")
            } footer: {
                Text("Conversation history JSONL append-only formatında bu dizinde tutulur. Arşivlemek için \"Yeni sohbet\" butonunu veya ⌘N kullan.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Tüm model tercihlerini sıfırla") {
                    claudeModel = ""
                    codexModel = ""
                    geminiModel = ""
                }
                .controlSize(.small)
            } header: {
                Text("Sıfırla")
            } footer: {
                Text("UserDefaults'taki backend model tercihleri silinir; defaultModelID (env > hardcoded) zincirine düşer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.2.x"
    }

    private static var storageDirectoryAbsolute: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("pixel-agent", isDirectory: true).path
    }

    private static var storageDirectory: String {
        let path = storageDirectoryAbsolute
        // ~/Library/... formuyla göster (kısaltılmış)
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Models tab

private struct ModelsSettingsTab: View {
    var body: some View {
        Form {
            ForEach(CLIKind.allCases) { kind in
                Section {
                    BackendModelRow(kind: kind)
                } header: {
                    Text(kind.displayName)
                }
            }
            Section {
                Text("Toolbar'daki model picker ile aynı state'i değiştirir. Boş bırakırsan default (env > hardcoded) zincirine düşer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Bilgi")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }
}

private struct BackendModelRow: View {
    let kind: CLIKind

    @AppStorage("pixel.model.claude") private var claudeModel: String = ""
    @AppStorage("pixel.model.codex") private var codexModel: String = ""
    @AppStorage("pixel.model.gemini") private var geminiModel: String = ""

    private var current: String {
        switch kind {
        case .claude: return claudeModel
        case .codex: return codexModel
        case .gemini: return geminiModel
        }
    }

    private func setCurrent(_ value: String) {
        switch kind {
        case .claude: claudeModel = value
        case .codex: codexModel = value
        case .gemini: geminiModel = value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Aktif", selection: Binding(
                get: { current.isEmpty ? "__default" : current },
                set: { setCurrent($0 == "__default" ? "" : $0) }
            )) {
                Text("Varsayılan (\(CLIBackend.defaultModelID(for: kind)))").tag("__default")
                Divider()
                ForEach(ModelCatalog.knownModels(for: kind), id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }
}

// MARK: - Connection tab

private struct ConnectionSettingsTab: View {
    @AppStorage(RelayURLResolver.customURLDefaultsKey) private var customURL: String = ""
    @AppStorage(RelayLauncher.autoStartEnabledDefaultsKey) private var autoStartEnabled: Bool = true
    @ObservedObject private var launcher = RootView.relayLauncher

    private var resolvedSource: RelayURLResolver.Source {
        RelayURLResolver.resolveSource()
    }

    var body: some View {
        Form {
            // Sprint 47 (v0.2.75): Relay launcher status
            Section {
                Toggle(isOn: $autoStartEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wrangler'ı Otomatik Başlat")
                        Text("App açıldığında `npx wrangler dev` subprocess'i otomatik tetiklenir; kapanırken SIGTERM. Production Cloudflare URL kullanıyorsanız kapatın.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    statusIcon
                    Text(statusLabel)
                        .font(.callout)
                    Spacer()
                    Button("Yeniden Başlat") {
                        launcher.manualRestart()
                    }
                    .controlSize(.small)
                    .disabled(!autoStartEnabled)
                }
                if let error = launcher.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Yerel Relay (Wrangler)")
            } footer: {
                Text("`brew install node` gerekli. Bundle'daki veya `~/Projects/pixel-agent/relay/` repo dizinindeki `wrangler.toml`'i kullanır. Subprocess 5sn cooldown ile max 3 kez restart eder.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Aktif URL") {
                    HStack {
                        Text(resolvedSource.url)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(resolvedSource.url, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .controlSize(.small)
                    }
                }
                LabeledContent("Kaynak", value: resolvedSource.displayName)

                HStack {
                    TextField("Özel URL (örn wss://my-relay.workers.dev)", text: $customURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    Button("Temizle") {
                        customURL = ""
                    }
                    .controlSize(.small)
                    .disabled(customURL.isEmpty)
                }
            } header: {
                Text("Relay URL")
            } footer: {
                Text("Öncelik: Özel URL > PIXEL_RELAY_URL env > Production Cloudflare > LAN IP > localhost. Production deploy için: `cd relay && npx wrangler deploy` (Cloudflare hesabı gerekir).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("LAN service type", value: "_pixel-agent._tcp")
                LabeledContent("Protokol versiyonu", value: "v2 (ed25519 signed)")
            } header: {
                Text("LAN")
            } footer: {
                Text("iOS otomatik olarak LAN'ı dener; başarısızsa relay'e düşer (ADR-0025 FallbackTransport).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !autoStartEnabled {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        } else if launcher.isInstallingDependencies {
            ProgressView().controlSize(.small)
        } else if launcher.isRunning {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if launcher.lastError != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        if !autoStartEnabled { return "Devre dışı" }
        if launcher.isInstallingDependencies { return "İlk kurulum: npm install çalışıyor (~30 sn)" }
        if launcher.isRunning { return "Çalışıyor (port 8787)" }
        if launcher.lastError != nil { return "Hata" }
        return "Başlatılmamış"
    }

    private static func defaultRelayURL() -> String {
        // Same logic as ChatHost.defaultRelayURL — simplified for display.
        "ws://localhost:8787"
    }
}

// MARK: - Permissions tab

private struct PermissionsSettingsTab: View {
    @State private var status: ComputerUsePermissions.Status = ComputerUsePermissions.status()

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Accessibility",
                    description: "ui_query / ui_click / ui_type için gerekli.",
                    granted: status.accessibility,
                    openAction: {
                        _ = ComputerUsePermissions.requestAccessibility()
                        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                )

                permissionRow(
                    title: "Screen Recording",
                    description: "ui_screenshot ve Mac chat ekran görüntüsü butonu için gerekli.",
                    granted: status.screenRecording,
                    openAction: {
                        _ = ComputerUsePermissions.requestScreenRecording()
                        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                    }
                )
            } header: {
                Text("Computer Use")
            }

            Section {
                Button {
                    status = ComputerUsePermissions.status()
                } label: {
                    Label("Durumu yenile", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        openAction: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(granted ? .green : .orange)
                if !granted {
                    Button("Aç") { openAction() }
                        .controlSize(.small)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}


// MARK: - Subagent tab (Faz 4 / v0.2.39)

private struct SubagentSettingsTab: View {
    @State private var settings: SubagentSettings = SubagentSettingsStore.load()

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Maks. süre: \(Int(settings.maxDurationSeconds)) sn",
                    value: $settings.maxDurationSeconds,
                    in: 5...600,
                    step: 5
                )
                Picker("Çıktı limiti", selection: outputLimitBinding) {
                    Text("Limit yok").tag(Optional<Int>.none)
                    Text("4 KB").tag(Optional<Int>(4096))
                    Text("16 KB").tag(Optional<Int>(16384))
                    Text("64 KB").tag(Optional<Int>(65536))
                    Text("256 KB").tag(Optional<Int>(262144))
                }
                Stepper(
                    "Paralel cap: \(settings.maxParallelCap)",
                    value: $settings.maxParallelCap,
                    in: 1...10
                )
            } header: {
                Text("Bütçe")
            } footer: {
                Text("dispatch_subagent MCP tool'unda default değerler. Çıktı limit aşılırsa subagent .budgetExceeded ile sonlanır; süre aşılırsa watchdog kestiririr.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default backend", selection: $settings.defaultBackend) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                    Text("Gemini").tag("gemini")
                }
            } header: {
                Text("Backend")
            } footer: {
                Text("dispatch_subagent çağrıları backend belirtmediyse kullanılır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Sıfırla") {
                        SubagentSettingsStore.reset()
                        settings = SubagentSettings.default
                    }
                    Spacer()
                    Button("Kaydet") {
                        SubagentSettingsStore.save(settings)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var outputLimitBinding: Binding<Int?> {
        Binding(
            get: { settings.maxOutputBytes },
            set: { settings.maxOutputBytes = $0 }
        )
    }
}

// MARK: - Memory tab (Sprint 36 / v0.2.63)

private struct MemorySettingsTab: View {
    @State private var entries: [MemoryEntry] = []
    @State private var loadError: String?
    @State private var isLoading: Bool = true
    @State private var isOptimizing: Bool = false
    @State private var optimizeMessage: String?
    /// **Sprint 37 (v0.2.64):** Semantic matching (NLEmbedding + char n-gram)
    /// toggle. Default ON. Kapatıldığında PlaybookLearner Sprint 36 word
    /// Jaccard davranışına döner.
    @AppStorage(EmbeddingScorer.enabledDefaultsKey) private var semanticMatching: Bool = true
    /// **Sprint 41 (v0.2.68):** Otomatik memory capture talimatı. Default ON.
    /// Kapatılırsa system prompt'a capture instruction inject edilmez —
    /// agent sadece kullanıcı `save_memory` aracını explicit isteyince çağırır.
    @AppStorage(MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey) private var autoCaptureEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $semanticMatching) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anlamsal Eşleştirme")
                        Text("İngilizce için NLEmbedding sentence vektör, diğer diller için karakter n-gram morfoloji. Kapatılırsa Sprint 36 word Jaccard'a düşer.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Eşleştirme")
            }

            Section {
                Toggle(isOn: $autoCaptureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Otomatik Öğrenme")
                        Text("Profil, tercih, recipe veya proje bilgisi yakaladığında agent kendi `save_memory` aracını çağırır (sessizce, sormadan). Kapatılırsa sadece kullanıcının explicit isteğiyle kaydeder.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Otomatik Capture")
            }

            Section {
                if isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Yükleniyor…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Text("Yüklenemedi: \(loadError)").foregroundStyle(.red).font(.caption)
                } else if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Henüz hafıza kaydı yok.")
                            .font(.callout)
                        Text("Claude / Codex / Gemini CLI MCP integration üzerinden `save_memory` aracı ile entry ekleyebilir, veya gelecekte bu sekmeye manuel ekleme arayüzü gelecek.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(entries) { entry in
                        memoryRow(entry)
                    }
                }
            } header: {
                HStack {
                    Text("Kayıtlar (\(entries.count))")
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Listeyi yenile")
                }
            } footer: {
                Text("Her kullanıcı mesajı öncesi PlaybookLearner ilgili entry'leri otomatik olarak system prompt'una ekler. JSONL append-only formatında \(Self.storagePath) konumunda saklanır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        Task { await optimize() }
                    } label: {
                        if isOptimizing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Optimize Et", systemImage: "wand.and.sparkles")
                        }
                    }
                    .disabled(isOptimizing || entries.isEmpty)
                    Spacer()
                    if let optimizeMessage {
                        Text(optimizeMessage).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Bakım")
            } footer: {
                Text("Optimize: duplicate entry'leri (Jaccard ≥ 0.85) birleştirir + tombstone'ları fiziksel olarak siler. MemoryConsolidator çalıştırır.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .task { await load() }
    }

    private func memoryRow(_ entry: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.category.displayName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.18), in: Capsule())
                    if !entry.tags.isEmpty {
                        Text("#" + entry.tags.joined(separator: " #"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(entry.content)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(role: .destructive) {
                Task { await delete(entry.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Bu entry'i sil")
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let store = try MemoryStore()
            let loaded = try await store.loadAll()
            entries = loaded
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func delete(_ id: UUID) async {
        do {
            let store = try MemoryStore()
            try await store.delete(id: id)
            await load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func optimize() async {
        isOptimizing = true
        defer { isOptimizing = false }
        do {
            let store = try MemoryStore()
            let before = try await store.entryCount()
            // Duplicate consolidation
            let all = try await store.loadAll()
            let pairs = MemoryConsolidator.findDuplicates(in: all)
            for (older, newer) in pairs {
                let merged = MemoryConsolidator.merge(older: older, newer: newer)
                try await store.add(merged)
                try await store.delete(id: older.id)
            }
            // Physical compact
            try await store.compact()
            let after = try await store.entryCount()
            optimizeMessage = "Önce: \(before) · Sonra: \(after) · Birleşen: \(pairs.count)"
            await load()
        } catch {
            optimizeMessage = "Hata: \(error.localizedDescription)"
        }
    }

    private static var storagePath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let path = support.appendingPathComponent("pixel-agent/memory.jsonl").path
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

// MARK: - Proactive tab (Sprint 38 / v0.2.65)

private struct ProactiveSettingsTab: View {
    @AppStorage(ProactiveEngine.masterEnabledDefaultsKey) private var masterEnabled: Bool = true
    @AppStorage(ProactiveEngine.idleThresholdDefaultsKey) private var idleThresholdMinutes: Int = ProactiveEngine.defaultIdleThresholdMinutes

    @State private var suppressedKinds: Set<TriggerKind> = []
    @State private var suppressedBundles: [String] = []
    @State private var newBundleDraft: String = ""
    @State private var accessibilityGranted: Bool = false
    @State private var calendarGranted: Bool = false
    /// **Sprint 40 (v0.2.67):** Notification tap → ChatView draft inject.
    /// Default ON. UserDefaults nil-safe.
    @AppStorage(NotificationActionDispatcher.enabledDefaultsKey) private var notificationInjectEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $masterEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proaktif Tetikleyiciler")
                        Text("Boş kaldığınızda veya uygulama değiştiğinizde sistem bildirimiyle Pixel Agent'a yönlendiriliyorsunuz. Kapatılırsa hiçbir tetikleyici çalışmaz. Etkili olması için uygulamayı yeniden başlatın.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $notificationInjectEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bildirimi tıklayınca sohbete prompt aktar")
                        Text("Proaktif bildirime tıkladığında ChatView composer'ına trigger-spesifik bir hazır prompt yazılır. Düzenleyip Enter ile gönderebilirsin (otomatik gönderme YOK).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Ana Anahtar")
            }

            Section {
                ForEach(TriggerKind.allCases, id: \.self) { kind in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle(isOn: kindSuppressedBinding(for: kind)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(kind.displayName)
                                    permissionBadge(for: kind)
                                }
                                Text(kind.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            } header: {
                Text("Aktif Tetikleyiciler")
            } footer: {
                Text("İşaretli kalanlar çalışır; kaldırılanlar suspend edilir. İzin gerektiren trigger'lar için aşağıdaki bölüme bakın.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                // Accessibility (windowDwell için)
                permissionRow(
                    title: "Accessibility",
                    description: "Pencere başlığı okuma — windowDwell trigger için.",
                    granted: accessibilityGranted,
                    openAction: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                // Calendar (upcomingEvent için)
                permissionRow(
                    title: "Calendar",
                    description: "Yaklaşan toplantı bildirimi — upcomingEvent trigger için.",
                    granted: calendarGranted,
                    openAction: {
                        Task {
                            _ = await CalendarEventDetector.requestAccessIfNeeded()
                            await refreshPermissionStatuses()
                        }
                    }
                )

                Button("Durumu Yenile") {
                    Task { await refreshPermissionStatuses() }
                }
                .controlSize(.small)
            } header: {
                Text("İzinler")
            } footer: {
                Text("İzin verilmemiş trigger'lar uygulama içinde no-op olur (hata yok).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(
                    "Boşta kalma eşiği: \(idleThresholdMinutes) dakika",
                    value: $idleThresholdMinutes,
                    in: 5...120,
                    step: 5
                )
            } header: {
                Text("Boşta Kalma")
            } footer: {
                Text("CGEventSource ile herhangi bir input event'in üzerinden geçen süre. Değişiklik için uygulamayı yeniden başlatın.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                if suppressedBundles.isEmpty {
                    Text("Sustrululan uygulama yok.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(suppressedBundles, id: \.self) { bundle in
                        HStack {
                            Text(bundle).font(.caption.monospaced())
                            Spacer()
                            Button(role: .destructive) {
                                removeBundle(bundle)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
                HStack {
                    TextField("com.apple.Safari", text: $newBundleDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                    Button("Ekle") {
                        addBundle()
                    }
                    .disabled(newBundleDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .controlSize(.small)
                }
            } header: {
                Text("Sustrulan Uygulamalar (appChange için)")
            } footer: {
                Text("Bundle ID'leri (örn com.apple.Safari) için 'Uygulama değişimi' bildirimi gösterilmez. Eklemek için bundle ID yazıp Ekle'ye basın.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .task {
            await reloadSuppression()
            await refreshPermissionStatuses()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func permissionBadge(for kind: TriggerKind) -> some View {
        switch kind.permissionRequirement {
        case .none:
            EmptyView()
        case .accessibility:
            Image(systemName: accessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(accessibilityGranted ? .green : .orange)
                .font(.caption2)
                .help(accessibilityGranted ? "Accessibility izni var" : "Accessibility izni gerek")
        case .calendar:
            Image(systemName: calendarGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(calendarGranted ? .green : .orange)
                .font(.caption2)
                .help(calendarGranted ? "Calendar izni var" : "Calendar izni gerek")
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        openAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.seal.fill" : "xmark.seal.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(description).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Aç") { openAction() }
                    .controlSize(.small)
            }
        }
    }

    private func refreshPermissionStatuses() async {
        // Accessibility — AXIsProcessTrusted (sync API)
        accessibilityGranted = AXIsProcessTrusted()
        // Calendar — EKEventStore status (MainActor)
        calendarGranted = await MainActor.run {
            CalendarEventDetector.isCalendarAuthorized()
        }
    }

    private func kindSuppressedBinding(for kind: TriggerKind) -> Binding<Bool> {
        Binding(
            get: { !suppressedKinds.contains(kind) },
            set: { active in
                if active {
                    suppressedKinds.remove(kind)
                } else {
                    suppressedKinds.insert(kind)
                }
                Task { await applySuppression() }
            }
        )
    }

    private func reloadSuppression() async {
        let store = SuppressionStore.load()
        suppressedKinds = store.suppressedKinds
        suppressedBundles = Array(store.suppressedBundles).sorted()
    }

    private func applySuppression() async {
        var store = SuppressionStore()
        store = SuppressionStore.load()
        for kind in TriggerKind.allCases {
            store.setKind(kind, suppressed: suppressedKinds.contains(kind))
        }
        // Bundles aktif state üzerinden update
        let activeBundles = Set(suppressedBundles)
        // Remove all then add — basit, atomik
        for existing in store.suppressedBundles where !activeBundles.contains(existing) {
            store.setBundle(existing, suppressed: false)
        }
        for active in activeBundles {
            store.setBundle(active, suppressed: true)
        }
        store.save()
        await RootView.proactiveEngine.updateSuppression(store)
    }

    private func addBundle() {
        let normalized = newBundleDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        if !suppressedBundles.contains(normalized) {
            suppressedBundles.append(normalized)
            suppressedBundles.sort()
        }
        newBundleDraft = ""
        Task { await applySuppression() }
    }

    private func removeBundle(_ bundle: String) {
        suppressedBundles.removeAll { $0 == bundle }
        Task { await applySuppression() }
    }
}

// MARK: - Voice tab (Sprint 42 / v0.2.69)

private struct VoiceSettingsTab: View {
    @AppStorage(VoiceProviderKind.activeProviderDefaultsKey) private var activeProviderRaw: String = VoiceProviderKind.apple.rawValue
    @State private var openaiKey: String = ""
    @State private var geminiKey: String = ""
    @State private var openaiKeyMasked: Bool = true
    @State private var geminiKeyMasked: Bool = true
    @State private var loadedKeys: Bool = false

    private var selectedProvider: VoiceProviderKind {
        VoiceProviderKind(rawValue: activeProviderRaw) ?? .apple
    }

    var body: some View {
        Form {
            Section {
                Picker("Sağlayıcı", selection: $activeProviderRaw) {
                    ForEach(VoiceProviderKind.allCases, id: \.self) { provider in
                        HStack {
                            Text(provider.displayName)
                            if !provider.isAvailable {
                                Text("(yakında)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(provider.rawValue)
                    }
                }
                Text(selectedProvider.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Provider değişikliği için uygulamayı yeniden başlatın.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } header: {
                Text("Voice Provider")
            } footer: {
                Text("ChatComposer'da mikrofon butonuna tıklayınca aktif olur. Apple Speech lokal ve ücretsiz; OpenAI Realtime API key + cüzdan gerek.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // API key fields — şimdilik display-only (Sprint 43+'da aktif olacak).
            Section {
                apiKeyField(
                    title: "OpenAI Realtime API Key",
                    text: $openaiKey,
                    masked: $openaiKeyMasked,
                    placeholder: "sk-proj-...",
                    onSave: { saveOpenAIKey() }
                )
                apiKeyField(
                    title: "Gemini Live API Key",
                    text: $geminiKey,
                    masked: $geminiKeyMasked,
                    placeholder: "AIza...",
                    onSave: { saveGeminiKey() }
                )
            } header: {
                Text("API Anahtarları")
            } footer: {
                Text("Sprint 43-44'te aktif edilecek. Şimdi kaydedebilirsin — ilgili provider geldiğinde otomatik kullanılır. UserDefaults'a kaydedilir (v0.3+ Keychain'e taşınacak).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Mikrofon ve Konuşma Tanıma İzinleri") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            } header: {
                Text("İzinler")
            } footer: {
                Text("Apple Speech için Microphone + Speech Recognition izinleri gerekir. İlk mic butonu tıklandığında macOS sorar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Sprint 46 (v0.2.74): Voice tools opt-in.
            VoiceToolsSection()
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
        .task {
            if !loadedKeys {
                await loadKeys()
                loadedKeys = true
            }
        }
    }

    @ViewBuilder
    private func apiKeyField(
        title: String,
        text: Binding<String>,
        masked: Binding<Bool>,
        placeholder: String,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.bold())
            HStack(spacing: 6) {
                Group {
                    if masked.wrappedValue {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                Button {
                    masked.wrappedValue.toggle()
                } label: {
                    Image(systemName: masked.wrappedValue ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                Button("Kaydet", action: onSave)
                    .controlSize(.small)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @MainActor
    private func loadKeys() async {
        let store = VoiceCredentialsStore()
        openaiKey = await store.openaiKey() ?? ""
        geminiKey = await store.geminiKey() ?? ""
    }

    private func saveOpenAIKey() {
        let value = openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await VoiceCredentialsStore().setOpenAIKey(value.isEmpty ? nil : value)
        }
    }

    private func saveGeminiKey() {
        let value = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await VoiceCredentialsStore().setGeminiKey(value.isEmpty ? nil : value)
        }
    }
}

// MARK: - Voice Tools (Sprint 46 / v0.2.74)

/// **Sprint 46:** Per-tool opt-in section — Sesli Mod tab altında.
/// Tüm BuiltInTools listele, her tool için Toggle. Risky kategori turuncu
/// uyarı badge ile gösterilir.
private struct VoiceToolsSection: View {
    @State private var allTools: [ToolDefinition] = []
    @State private var toggles: [String: Bool] = [:]
    @State private var dirty: Bool = false
    @State private var hasReset: Bool = false

    var body: some View {
        Section {
            if allTools.isEmpty {
                ProgressView()
            } else {
                ForEach(allTools, id: \.name) { tool in
                    toolRow(tool)
                }

                HStack {
                    Button("Önerilen Ayarlara Dön") {
                        resetToDefaults()
                    }
                    .controlSize(.small)
                    Spacer()
                    if dirty {
                        Text("Değişiklikler bir sonraki Sesli Mod başlatmada etkili.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if hasReset {
                        Text("Sıfırlandı")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
        } header: {
            Text("Voice Tools (Agent Aracı İzinleri)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice modunda agent'ın hangi MCP araçlarını çağırabileceğini buradan kontrol et. **Önerilen** (yeşil) yan etkisiz veya geri alınabilir tool'lardır; varsayılan açıktır. **Riskli** (turuncu) UI manipulation veya uzun süreli iş yapanlar; default kapalı, bilinçli açabilirsin.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Voice modu başlatıldıktan sonra değişiklik etkili olmaz — restart gerek.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadTools() }
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolDefinition) -> some View {
        Toggle(isOn: toggleBinding(for: tool.name)) {
            HStack(spacing: 6) {
                Text(tool.name).font(.callout.monospaced())
                badgeFor(tool.name)
            }
            Text(tool.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func badgeFor(_ toolName: String) -> some View {
        if VoiceToolPreferences.isDefaultEnabled(toolName) {
            Text("önerilen")
                .font(.caption2.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.green.opacity(0.15), in: Capsule())
        } else if VoiceToolPreferences.isRisky(toolName) {
            Text("riskli")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.orange.opacity(0.18), in: Capsule())
        }
    }

    private func toggleBinding(for toolName: String) -> Binding<Bool> {
        Binding(
            get: { toggles[toolName] ?? false },
            set: { newValue in
                toggles[toolName] = newValue
                VoiceToolPreferences().setEnabled(toolName, newValue)
                dirty = true
                hasReset = false
            }
        )
    }

    private func loadTools() {
        let registry = BuiltInTools.makeRegistry()
        allTools = registry.all().sorted { $0.name < $1.name }
        let prefs = VoiceToolPreferences()
        var current: [String: Bool] = [:]
        for tool in allTools {
            current[tool.name] = prefs.isEnabled(tool.name)
        }
        toggles = current
    }

    private func resetToDefaults() {
        VoiceToolPreferences().resetAllOverrides()
        loadTools()
        dirty = false
        hasReset = true
    }
}
