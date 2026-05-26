import AppKit
import PixelBackends
import PixelComputerUse
import PixelMemory
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
        case .permissions: PermissionsSettingsTab()
        }
    }
}

// MARK: - Tab enum (testable)

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, models, connection, subagent, memory, proactive, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Genel"
        case .models: return "Modeller"
        case .connection: return "Bağlantı"
        case .subagent: return "Subagent"
        case .memory: return "Hafıza"
        case .proactive: return "Proaktif"
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
    private var relayURL: String {
        ProcessInfo.processInfo.environment["PIXEL_RELAY_URL"]
            ?? Self.defaultRelayURL()
    }

    private var isEnvOverride: Bool {
        ProcessInfo.processInfo.environment["PIXEL_RELAY_URL"] != nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Relay URL") {
                    HStack {
                        Text(relayURL)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(relayURL, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .help("Panoya kopyala")
                    }
                }
                if isEnvOverride {
                    Text("`PIXEL_RELAY_URL` env değişkeni aktif — bu değer UserDefaults yerine geçer.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Relay")
            } footer: {
                Text("LAN için relay gerek değildir; Bonjour discovery zaten paralel devrede (ADR-0023 MergeTransport).")
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
            } header: {
                Text("Ana Anahtar")
            }

            Section {
                ForEach(TriggerKind.allCases, id: \.self) { kind in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle(isOn: kindSuppressedBinding(for: kind)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.displayName)
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
                Text("İşaretli kalanlar çalışır; kaldırılanlar suspend edilir.")
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
        .task { await reloadSuppression() }
    }

    // MARK: - Helpers

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
