import Foundation
import PixelCore

/// Bir subagent çalışmasının dört olası bitiş durumu.
public enum SubagentResult: Sendable, Equatable {
    /// Backend `done` deltası geldi ve budget aşılmadı.
    case completed(output: String, durationSeconds: Double)

    /// Budget (süre veya byte) aşıldı; mevcut çıktı `partialOutput`'ta.
    case budgetExceeded(reason: BudgetReason, partialOutput: String, durationSeconds: Double)

    /// Task'i çağıran cancel etti (`Task.cancel()`).
    case cancelled(partialOutput: String, durationSeconds: Double)

    /// Backend hata fırlattı (subprocess crash, parse hatası, vs.).
    case failed(error: String, partialOutput: String, durationSeconds: Double)

    public enum BudgetReason: String, Sendable, Equatable {
        case duration   // wallclock aşıldı
        case outputBytes  // maxOutputBytes aşıldı
    }
}

extension SubagentResult {
    /// Tam çıktı (completed) veya partial çıktı (diğer üç vaka).
    public var output: String {
        switch self {
        case .completed(let o, _): return o
        case .budgetExceeded(_, let o, _): return o
        case .cancelled(let o, _): return o
        case .failed(_, let o, _): return o
        }
    }

    public var durationSeconds: Double {
        switch self {
        case .completed(_, let d): return d
        case .budgetExceeded(_, _, let d): return d
        case .cancelled(_, let d): return d
        case .failed(_, _, let d): return d
        }
    }

    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}
