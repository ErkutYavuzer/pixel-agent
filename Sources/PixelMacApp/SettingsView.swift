import AppKit
import PixelBackends
import PixelComputerUse
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
        case .permissions: PermissionsSettingsTab()
        }
    }
}

// MARK: - Tab enum (testable)

enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, models, connection, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Genel"
        case .models: return "Modeller"
        case .connection: return "Bağlantı"
        case .permissions: return "İzinler"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .models: return "cpu"
        case .connection: return "wifi"
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
