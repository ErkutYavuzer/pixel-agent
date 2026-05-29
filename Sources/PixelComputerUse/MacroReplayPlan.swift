import Foundation

/// **Sprint 52 (v0.2.81) — F1.** Replay motorunun **saf (AX-bağımsız)** karar
/// katmanı. `MacroReplayer` (actor) bu fonksiyonları çağırır; böylece replay
/// mantığı hermetic test edilebilir — gerçek Accessibility/CGEvent gerekmez.
public enum MacroReplayPlan {
    /// Replay öncesi doğrulama: boş kayıt + runaway cap. Başarılıysa adımları
    /// (sırası korunarak) döndürür.
    public static func validate(_ steps: [MacroStep], maxSteps: Int) -> Result<[MacroStep], MacroReplayError> {
        guard !steps.isEmpty else { return .failure(.emptyRecording) }
        guard steps.count <= maxSteps else {
            return .failure(.tooManySteps(count: steps.count, max: maxSteps))
        }
        return .success(steps)
    }

    /// Element bulunamadığında verilecek karar. `attempt` = o ana dek yapılan
    /// retry sayısı (0-based). `retry` politikasında `attempt < maxRetries`
    /// iken tekrar dener, tükenince abort eder.
    public static func decideOnNotFound(policy: NotFoundPolicy, attempt: Int) -> NotFoundAction {
        switch policy {
        case .abort:
            return .abort
        case .skip:
            return .skip
        case .retry(let maxRetries, let backoffMs):
            return attempt < maxRetries ? .retry(afterMs: max(0, backoffMs)) : .abort
        }
    }

    /// Replay başlamadan Plan Mode guard kararı: destructive adım içeren bir
    /// kayıt, `allowDestructive == false` iken bloklanır.
    public static func isBlockedByPlanMode(_ steps: [MacroStep], allowDestructive: Bool) -> Bool {
        guard !allowDestructive else { return false }
        return steps.contains { $0.isDestructive }
    }
}
