import Foundation
import PixelSubagent

/// Subagent terminal status'unu ana chat'e düşen `[subagent <backend>] …`
/// formatlı mesaja çevirir (C1).
///
/// Demo senaryosu bağı: "Subagent panelde çalışırken, bittiğinde ana chat'e
/// `[subagent gemini] sonuç:` mesajı düşer."
///
/// Saf — SwiftUI ve ChatViewModel'den bağımsız test edilebilir.
enum SubagentMessageFormatter {
    /// Bir terminal `SubagentSession`'ı kullanıcıya gösterilecek tek mesaj
    /// metnine çevirir. Status terminal değilse (defensive) ham prompt
    /// preview'ı döner.
    static func format(session: SubagentSession) -> String {
        let prefix = "[subagent \(session.backendKind.rawValue)]"
        guard let result = session.result else {
            return "\(prefix) durum: \(session.status.displayLabel)"
        }
        switch result {
        case .completed(let output, _):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(prefix) sonuç:\n\(trimmed)"
        case .budgetExceeded(let reason, let partial, _):
            let reasonLabel: String
            switch reason {
            case .duration: reasonLabel = "süre aşıldı"
            case .outputBytes: reasonLabel = "çıktı boyutu aşıldı"
            }
            let body = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                return "\(prefix) bütçe aşıldı (\(reasonLabel))."
            }
            return "\(prefix) bütçe aşıldı (\(reasonLabel)). Kısmi çıktı:\n\(body)"
        case .cancelled(let partial, _):
            let body = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                return "\(prefix) iptal edildi."
            }
            return "\(prefix) iptal edildi. Kısmi çıktı:\n\(body)"
        case .failed(let error, let partial, _):
            let body = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            let errMsg = error.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                return "\(prefix) hata: \(errMsg)"
            }
            return "\(prefix) hata: \(errMsg)\nKısmi çıktı:\n\(body)"
        }
    }
}
