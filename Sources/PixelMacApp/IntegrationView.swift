import AppKit
import SwiftUI

/// pixel-agent'ın MCP server'ını (`pixel-mcp-server`) dış IDE'lere (Claude Desktop,
/// Cursor, Codex CLI vb.) tanıtmak için config snippet'leri + binary path + kopya
/// butonları sunan kurulum yardımcısı.
///
/// Binary path resolution: PixelAgent.app bundle'ı içinde
/// `Contents/MacOS/pixel-mcp-server`. `scripts/build-app.sh` v0.2.26+ bunu da
/// paketler. Bundle'da yoksa kullanıcıya `swift build -c release` ve
/// `.build/release/pixel-mcp-server` fallback path'i gösterilir.
struct IntegrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedClientID: ClientID?
    /// Sprint 6: MCP otomatik kurulum sihirbazı sheet'i.
    @State private var showWizard: Bool = false

    enum ClientID: String, CaseIterable, Identifiable {
        case claudeDesktop = "claude-desktop"
        case cursor = "cursor"
        case codexCLI = "codex-cli"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claudeDesktop: return "Claude Desktop"
            case .cursor: return "Cursor"
            case .codexCLI: return "Codex CLI"
            }
        }

        /// Kullanıcıya gösterilen config dosyası path'i (literal — bundle'a
        /// bağlı değil).
        var configPath: String {
            switch self {
            case .claudeDesktop:
                return "~/Library/Application Support/Claude/claude_desktop_config.json"
            case .cursor:
                return "~/.cursor/mcp.json"
            case .codexCLI:
                return "~/.codex/config.json"
            }
        }
    }

    private var resolution: MCPIntegrationConfig.Resolution {
        MCPIntegrationConfig.resolveBinaryPath()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("MCP Entegrasyonu")
                    .font(.title2.bold())

                Text("pixel-agent kendi tool'larını [Model Context Protocol](https://modelcontextprotocol.io) standardı üzerinden expose eder. Aşağıdaki snippet'i seçili IDE'nin config dosyasına ekleyin; IDE'yi yeniden başlattıktan sonra Pixel'in 14 tool'u (`get_clipboard`, `notify`, `ui_query`, `dispatch_subagent`, vb.) IDE içinden kullanılabilir.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Sprint 6: Otomatik kurulum sihirbazı erişimi.
                Button {
                    showWizard = true
                } label: {
                    Label("🪄 Otomatik Kurulum…",
                          systemImage: "wand.and.stars")
                        .font(.callout.bold())
                }
                .buttonStyle(.borderedProminent)
                .help("Config dosyalarını otomatik düzenle — kopya-yapıştır gerek yok")

                Divider()

                binaryPathSection

                Divider()

                ForEach(ClientID.allCases) { client in
                    IntegrationSnippetCard(
                        client: client,
                        snippet: MCPIntegrationConfig.snippet(binaryPath: resolution.path),
                        copied: copiedClientID == client,
                        onCopy: { copy(for: client) }
                    )
                }

                Divider()

                Text("Daha fazla bilgi: [ADR-0016 (MCP server expose)](https://github.com/ErkutYavuzer/pixel-agent/blob/main/docs/adr/0016-mcp-server-expose.md) · [ADR-0018 (Unix socket bridge)](https://github.com/ErkutYavuzer/pixel-agent/blob/main/docs/adr/0018-mcp-bridge-unix-socket.md)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Kapat") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 640)
        .sheet(isPresented: $showWizard) {
            MCPSetupWizardView()
        }
    }

    private var binaryPathSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("pixel-mcp-server konumu")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 8) {
                Text(resolution.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if resolution.isBundled {
                    Button("Finder'da Göster") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: resolution.path)]
                        )
                    }
                    .controlSize(.small)
                }
            }
            if !resolution.isBundled {
                Label("Bundle içinde bulunamadı. `swift build -c release` çalıştırın ve yukarıdaki fallback path'i kullanın.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func copy(for client: ClientID) {
        let snippet = MCPIntegrationConfig.snippet(binaryPath: resolution.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        copiedClientID = client
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedClientID == client { copiedClientID = nil }
        }
    }
}

struct IntegrationSnippetCard: View {
    let client: IntegrationView.ClientID
    let snippet: String
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(client.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Button(action: onCopy) {
                    Label(copied ? "Kopyalandı" : "Kopyala",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption)
                }
                .controlSize(.small)
                .tint(copied ? .green : .accentColor)
            }
            Text("Config: `\(client.configPath)`")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Text(snippet)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// MCP integration helper'ının saf hesap kısmı — Bundle'dan bağımsız test edilebilir.
enum MCPIntegrationConfig {
    struct Resolution: Equatable, Sendable {
        let path: String
        let isBundled: Bool
    }

    /// Binary path resolution.
    /// - Önce `bundle.bundleURL/Contents/MacOS/pixel-mcp-server` denenir.
    /// - Bulunursa `(path, isBundled: true)`.
    /// - Bulunmazsa fallback `<repo>/.build/release/pixel-mcp-server`, `isBundled: false`.
    static func resolveBinaryPath(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Resolution {
        let candidate = bundle.bundleURL
            .appendingPathComponent("Contents/MacOS/pixel-mcp-server")
            .path
        if fileManager.isExecutableFile(atPath: candidate) {
            return Resolution(path: candidate, isBundled: true)
        }
        return Resolution(
            path: "<repo>/.build/release/pixel-mcp-server",
            isBundled: false
        )
    }

    /// MCP server config snippet (Claude Desktop / Cursor / Codex CLI hepsi aynı format).
    static func snippet(binaryPath: String) -> String {
        """
        {
          "mcpServers": {
            "pixel-agent": {
              "command": "\(binaryPath)",
              "args": []
            }
          }
        }
        """
    }
}
