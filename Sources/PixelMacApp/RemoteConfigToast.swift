import PixelBackends
import SwiftUI

/// iOS dashboard'dan gelen `clientConfig` envelope'u Mac state'ini değiştirdiğinde
/// üstte beliren ephemeral banner (C5).
///
/// Demo senaryosu bağı: "telefonundan iOS dashboard ile backend'i Codex'e
/// değiştirir; Mac üstte '📱 Telefon: Codex'e geçildi' toast belirir."
struct RemoteConfigToast: Identifiable, Equatable {
    let id: UUID
    let message: String

    init(message: String, id: UUID = UUID()) {
        self.id = id
        self.message = message
    }
}

/// Mac'in mevcut state'ini iOS'tan gelen yeni config ile karşılaştırıp en
/// görünür değişikliği insan-okur tek-satır mesaja çevirir. Hiçbir şey
/// değişmediyse `nil`.
///
/// Saf yardımcı — SwiftUI'a bağımlı değil, hermetik test edilebilir.
enum RemoteConfigToastBuilder {
    static func buildMessage(
        oldBackend: String,
        oldModel: String,
        oldPlanMode: Bool,
        newBackend: String,
        newModel: String,
        newPlanMode: Bool
    ) -> String? {
        var changes: [String] = []

        if newBackend != oldBackend {
            changes.append("\(displayName(forBackend: newBackend))'e geçildi")
        }

        // Model alanı yalnızca dolu ve farklıysa anlamlı — boş gelmesi "değişiklik
        // belirtme" işareti olarak yorumlanır (iOS bazen sadece backend gönderir).
        if !newModel.isEmpty && newModel != oldModel {
            changes.append("model: \(newModel)")
        }

        if newPlanMode != oldPlanMode {
            changes.append(newPlanMode ? "plan modu açıldı" : "plan modu kapatıldı")
        }

        guard !changes.isEmpty else { return nil }
        return "📱 Telefon: " + changes.joined(separator: " · ")
    }

    /// Bilinen CLIKind raw value'ları için kısa display name; bilinmeyen değer
    /// gelirse capitalized raw'ı döndür (forward-compat).
    private static func displayName(forBackend raw: String) -> String {
        CLIKind(rawValue: raw)?.displayName ?? raw.capitalized
    }
}

/// Üstten slide-in banner. ChatHost `.overlay(alignment: .top)` ile yerleştirir.
struct RemoteConfigToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.black.opacity(0.78))
            )
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .accessibilityAddTraits(.isStaticText)
    }
}
