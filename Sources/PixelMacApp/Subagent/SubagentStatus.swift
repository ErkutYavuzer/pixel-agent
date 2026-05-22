import PixelSubagent

/// Bir `SubagentSession`'ın yaşam döngüsündeki durumlardan biri.
///
/// State machine: `pending → running → (completed | budgetExceeded | cancelled | failed)`.
/// Terminal durumlardan sonra `Session` `dismiss(_:)` çağrısı ile listeden silinebilir.
enum SubagentStatus: Equatable, Sendable {
    case pending
    case running
    case completed
    case budgetExceeded(SubagentResult.BudgetReason)
    case cancelled
    case failed(error: String)

    var isTerminal: Bool {
        switch self {
        case .pending, .running: return false
        case .completed, .budgetExceeded, .cancelled, .failed: return true
        }
    }

    /// SF Symbol adı — kart üstündeki durum ikonu için.
    var symbolName: String {
        switch self {
        case .pending: return "hourglass"
        case .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .budgetExceeded: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    /// Kısa, kullanıcıya gösterilen başlık.
    var displayLabel: String {
        switch self {
        case .pending: return "Bekliyor"
        case .running: return "Çalışıyor"
        case .completed: return "Tamamlandı"
        case .budgetExceeded(let reason):
            switch reason {
            case .duration: return "Süre aşıldı"
            case .outputBytes: return "Çıktı aşıldı"
            }
        case .cancelled: return "İptal edildi"
        case .failed: return "Hata"
        }
    }
}
