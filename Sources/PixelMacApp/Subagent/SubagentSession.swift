import Foundation
import PixelBackends
import PixelCore
import PixelSubagent

/// UI'da görünür bir subagent çalışmasının state snapshot'ı.
///
/// Value-type — `SubagentManager` her status geçişinde struct'ı kopyalayıp yenisini
/// `@Published` array'e koyar. Cancel-task referansı `SubagentManager.runners` map'inde
/// tutulur (Session Sendable kalsın diye).
///
/// `id` aynı zamanda `SubagentRunner.id` olarak da kullanılır → `AgentContext.currentSubagentID`
/// TaskLocal binding ile log/tracing kaynak tutarlılığı.
struct SubagentSession: Identifiable, Equatable, Sendable {
    let id: SubagentID
    let prompt: String
    let backendKind: CLIKind
    let budget: Budget
    var status: SubagentStatus
    let startedAt: Date
    var finishedAt: Date?
    var result: SubagentResult?
    /// Streaming sırasında her chunk burada birikir. Terminal status'a geçildiğinde
    /// `result.output` ile aynı olur. UI canlı render için bunu okur.
    var partialOutput: String
    /// **Faz 5 (v0.2.41):** Multi-turn dispatch ise her turn'ün sonuçları.
    /// One-shot dispatch'te nil. UI detail sheet bunu görünce per-turn
    /// expanded list render eder; nil ise tek output bloğu (eski davranış).
    var multiTurnTurns: [TurnResult]?

    init(
        id: SubagentID = SubagentID(),
        prompt: String,
        backendKind: CLIKind,
        budget: Budget,
        status: SubagentStatus = .pending,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        result: SubagentResult? = nil,
        partialOutput: String = "",
        multiTurnTurns: [TurnResult]? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.backendKind = backendKind
        self.budget = budget
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.partialOutput = partialOutput
        self.multiTurnTurns = multiTurnTurns
    }

    /// Prompt'un kart üzerinde gösterilecek kısaltılmış hali (40 karakter).
    var promptPreview: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40 { return trimmed }
        return String(trimmed.prefix(40)) + "…"
    }

    /// Bitmemiş session'lar için `Date()` - startedAt; bitenler için finishedAt - startedAt.
    func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        let end = finishedAt ?? now
        return end.timeIntervalSince(startedAt)
    }
}
