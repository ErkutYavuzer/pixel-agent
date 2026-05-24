import AppKit
import SwiftUI

/// MCP otomatik kurulum sihirbazı (Sprint 6).
///
/// Her IDE için config dosyasını okur, durumu badge ile gösterir, kullanıcı
/// "Uygula" tıklayınca dosyayı geri yazar. Backup `.backup-<timestamp>`
/// suffix'iyle yan yana tutulur — kullanıcı kontrolünden çıkmasın diye
/// otomatik silme yok.
///
/// Mimari: JSON merge `MCPConfigMerger`'da (saf, test edilebilir); dosya
/// I/O bu view'da side-effect.
struct MCPSetupWizardView: View {
    @Environment(\.dismiss) private var dismiss

    private var resolution: MCPIntegrationConfig.Resolution {
        MCPIntegrationConfig.resolveBinaryPath()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                binaryPathSection
                Divider()
                ForEach(IntegrationView.ClientID.allCases) { client in
                    MCPWizardCard(
                        client: client,
                        binaryPath: resolution.path,
                        isBundled: resolution.isBundled
                    )
                }
                Divider()
                footerNotes
                HStack {
                    Spacer()
                    Button("Kapat") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 600, idealHeight: 700)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("MCP Kurulum Sihirbazı")
                    .font(.title2.bold())
                Text("pixel-agent'ı destekli IDE'lere otomatik kurar — kopya-yapıştır yerine tek tık.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var binaryPathSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("pixel-mcp-server konumu")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(resolution.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
            if !resolution.isBundled {
                Label("Bundle içinde bulunamadı. `swift build -c release` çalıştırın, yeniden açın.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var footerNotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• Yedek: her uygulama, mevcut config'i `.backup-<timestamp>` suffix'iyle yan yana saklar — sihirbazdan etkilenmez.")
            Text("• IDE'yi config değiştikten sonra yeniden başlat.")
            Text("• Diğer MCP server'ların korunur; sadece `pixel-agent` entry'si eklenir/güncellenir.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// Per-IDE kart — status detect + Apply button + Finder.
private struct MCPWizardCard: View {
    let client: IntegrationView.ClientID
    let binaryPath: String
    let isBundled: Bool

    @State private var status: MCPConfigStatus = .notConfigured
    @State private var lastError: String?
    @State private var lastApplyAt: Date?
    @State private var didRefresh: Bool = false

    private var configURL: URL {
        let expanded = (client.configPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(client.displayName)
                    .font(.subheadline.bold())
                Spacer()
                statusBadge
            }
            Text("Config: `\(client.configPath)`")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            if case .configuredWithDifferentPath(let currentPath) = status {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mevcut path:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(currentPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            if let lastError {
                Label(lastError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let lastApplyAt {
                Text("Son uygulama: \(Self.timeFormatter.string(from: lastApplyAt))")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            HStack(spacing: 8) {
                Button(action: refresh) {
                    Label("Yenile", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: apply) {
                    Label(status.actionLabel, systemImage: "wand.and.stars")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isBundled)
                .help(isBundled
                      ? "Config dosyasını oku, pixel-agent entry'sini ekle/güncelle, kaydet"
                      : "Önce `swift build -c release` çalıştır")

                Spacer()

                Button(action: showInFinder) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Config dizinini Finder'da göster")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.08))
        )
        .onAppear {
            if !didRefresh {
                refresh()
                didRefresh = true
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            Text(status.displayName)
                .font(.caption.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.18), in: Capsule())
        .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch status {
        case .notConfigured: return .secondary
        case .configuredCorrectly: return .green
        case .configuredWithDifferentPath: return .orange
        }
    }

    // MARK: - Actions

    private func refresh() {
        lastError = nil
        let existing = try? String(contentsOf: configURL, encoding: .utf8)
        status = MCPConfigMerger.currentStatus(
            existingJSON: existing,
            binaryPath: binaryPath
        )
    }

    private func apply() {
        lastError = nil
        do {
            // Read existing (may not exist).
            let existing = try? String(contentsOf: configURL, encoding: .utf8)
            // Merge.
            let merged = try MCPConfigMerger.mergePixelAgent(
                binaryPath: binaryPath,
                intoExistingJSON: existing
            )
            // Backup existing if non-empty.
            if let existing, !existing.isEmpty {
                let backupURL = configURL.appendingPathExtension(
                    "backup-\(Self.timestampForFile())"
                )
                try existing.write(to: backupURL, atomically: true, encoding: .utf8)
            }
            // Ensure parent dir.
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Write merged.
            try merged.write(to: configURL, atomically: true, encoding: .utf8)
            lastApplyAt = Date()
            refresh()
        } catch {
            lastError = "Uygulanamadı: \(error.localizedDescription)"
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(
            [configURL.deletingLastPathComponent()]
        )
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    private static func timestampForFile() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
