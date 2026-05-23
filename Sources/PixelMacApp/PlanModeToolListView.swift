import PixelBackends
import SwiftUI

/// Plan Mode aktif iken sağ tarafta görünen read-only tool list paneli (C4).
///
/// Kullanıcıya "bu turda hangi tool'lar bloklandı / erişilebilir" bilgisini
/// görsel olarak gösterir. Catalog Claude Code'un `--permission-mode plan`
/// davranışıyla hizalı: yazma/komut yürütme bloklanır, okuma/araştırma serbest.
///
/// Codex/Gemini Plan Mode'u native desteklemediği için panel yine içeriği
/// gösterir ama altta uyarı satırı çıkar — toolbar tooltip ile aynı mesaj.
struct PlanModeToolListView: View {
    /// Aktif (sol) backend. `nil` ise (dual mode'da Claude yoksa) uyarı satırı
    /// her zaman gösterilir.
    let backendKind: CLIKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(
                        title: "Erişilebilir",
                        tools: PlanModeToolCatalog.allowedTools,
                        accent: .green
                    )
                    section(
                        title: "Bloklandı",
                        tools: PlanModeToolCatalog.blockedTools,
                        accent: .red
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .foregroundStyle(.orange)
            Text("Plan Modu")
                .font(.caption.bold())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func section(title: String, tools: [PlanModeTool], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tools) { tool in
                    PlanModeToolRow(tool: tool, accent: accent)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let kind = backendKind, PlanModeToolCatalog.supportsPlanMode(kind: kind) {
                Label("Claude `--permission-mode plan` bayrağına eşlenir.",
                      systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label(unsupportedMessage,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unsupportedMessage: String {
        guard let kind = backendKind else {
            return "Plan modu yalnızca Claude için aktif — diğer backend'ler bu bayrağı yoksayar."
        }
        return "\(kind.displayName) Plan modunu yoksayar; tool kısıtlaması uygulanmaz."
    }
}

private struct PlanModeToolRow: View {
    let tool: PlanModeTool
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tool.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(accent)
                .font(.system(size: 13))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(tool.allowed ? .primary : .secondary)
                Text(tool.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(tool.allowed ? 1.0 : 0.78)
    }
}

// MARK: - Catalog (pure helpers)

/// Plan Mode panelinde gösterilen tool kaydı. Saf-data; SwiftUI'a bağımlı değil.
struct PlanModeTool: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let allowed: Bool
}

/// Plan Mode tool kataloğu — view'dan ayrı, test edilebilir.
///
/// Kaynak: Claude Code'un plan modu davranışı (`--permission-mode plan`):
/// dosya/komut mutasyonu yapan tool'lar bloklanır; okuma ve araştırma serbest.
enum PlanModeToolCatalog {
    static let tools: [PlanModeTool] = [
        // Read-only — erişilebilir
        PlanModeTool(id: "read", name: "Read",
                     summary: "Dosya içeriğini oku",
                     allowed: true),
        PlanModeTool(id: "glob", name: "Glob",
                     summary: "Dosya yolu örüntüsüyle ara",
                     allowed: true),
        PlanModeTool(id: "grep", name: "Grep",
                     summary: "Kod içinde metin/regex ara",
                     allowed: true),
        PlanModeTool(id: "webfetch", name: "WebFetch",
                     summary: "URL'den içerik getir",
                     allowed: true),
        PlanModeTool(id: "websearch", name: "WebSearch",
                     summary: "Web'de sorgula",
                     allowed: true),

        // Mutating — bloklanmış
        PlanModeTool(id: "edit", name: "Edit",
                     summary: "Dosyada string değiştir",
                     allowed: false),
        PlanModeTool(id: "write", name: "Write",
                     summary: "Yeni dosya yaz / üzerine yaz",
                     allowed: false),
        PlanModeTool(id: "bash", name: "Bash",
                     summary: "Shell komutu çalıştır",
                     allowed: false),
        PlanModeTool(id: "notebook-edit", name: "NotebookEdit",
                     summary: "Jupyter hücresi düzenle",
                     allowed: false),
    ]

    static var allowedTools: [PlanModeTool] {
        tools.filter { $0.allowed }
    }

    static var blockedTools: [PlanModeTool] {
        tools.filter { !$0.allowed }
    }

    /// Plan modu native desteği: yalnızca Claude. ADR-0017'de açıklandığı gibi
    /// Codex/Gemini için flag no-op (CLI'larda karşılığı yok).
    static func supportsPlanMode(kind: CLIKind) -> Bool {
        switch kind {
        case .claude: return true
        case .codex, .gemini: return false
        }
    }
}
