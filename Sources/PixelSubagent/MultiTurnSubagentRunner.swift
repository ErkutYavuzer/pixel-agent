import Foundation
import PixelCore

/// **Faz 4 (v0.2.39):** Multi-turn subagent — N user prompt sequential
/// olarak çalıştırılır, her turn'ün assistant cevabı conversation history'ye
/// eklenir, sonraki turn full history ile backend'e gider. Tek shared budget
/// tüm turn'lere uygulanır (kümülatif elapsed time).
///
/// One-shot `SubagentRunner`'a alternatif; vision model "tıkla, sonra
/// screenshot al, sonra cevabı özetle" gibi multi-step workflow'larda
/// kullanılır.
///
/// **Mimari notlar:**
/// - Sequential — her turn önceki tamamlanana kadar beklenir (parallel turn yok).
/// - Shared budget — `budget.maxDuration` toplam süre limiti (turn'ler arasında
///   bölünmez); aşılırsa kalan turn'ler atlanır, `.budgetExceededAt` döner.
/// - History accumulation — `Message(role:.user)` + `Message(role:.assistant)`
///   her turn için eklenir; sonraki backend.send full history alır.
/// - Cancellation cooperative — outer `Task.cancel()` herhangi bir turn'i
///   `.cancelledAt` ile sonlandırır.
/// - TaskLocal `AgentContext.currentSubagentID` tüm turn'ler süresince bağlı.
public actor MultiTurnSubagentRunner {
    public let id: SubagentID
    public let backend: any ChatBackend
    public let budget: Budget

    public init(
        backend: any ChatBackend,
        budget: Budget = .default,
        id: SubagentID = SubagentID()
    ) {
        self.id = id
        self.backend = backend
        self.budget = budget
    }

    /// N turn sequential çalıştır + her turn için kısmi sonuç döner.
    /// İlk turn'ün cevabı history'ye eklenir, ikinci turn full history ile
    /// gönderilir, vb.
    public func runConversation(
        turns: [String],
        system: String? = nil,
        options: ChatOptions = ChatOptions()
    ) async -> MultiTurnSubagentResult {
        let start = Date()
        var history: [Message] = []
        var turnResults: [TurnResult] = []

        return await AgentContext.$currentSubagentID.withValue(id) {
            for (index, prompt) in turns.enumerated() {
                // Cancellation check turn başında.
                if Task.isCancelled {
                    return .cancelledAt(
                        turnIndex: index,
                        completedTurns: turnResults,
                        totalDurationSeconds: Date().timeIntervalSince(start)
                    )
                }

                // Remaining budget — total elapsed çıkarıldıktan sonra kalan.
                let elapsed = Date().timeIntervalSince(start)
                let remaining = budget.maxDuration - elapsed
                if remaining <= 0 {
                    return .budgetExceededAt(
                        turnIndex: index,
                        reason: .duration,
                        completedTurns: turnResults,
                        totalDurationSeconds: elapsed
                    )
                }

                let userMessage = Message(role: .user, text: prompt)
                history.append(userMessage)

                let turnStart = Date()
                let turnResult = await Self.runSingleTurn(
                    backend: backend,
                    history: history,
                    system: system,
                    options: options,
                    budget: budget,
                    deadline: turnStart.addingTimeInterval(remaining)
                )

                let assistant = Message(role: .assistant, text: turnResult.output)
                history.append(assistant)
                turnResults.append(turnResult)

                // Turn budget exceeded veya failed → kalanları atla.
                switch turnResult.outcome {
                case .completed:
                    continue
                case .budgetExceeded(let reason):
                    return .budgetExceededAt(
                        turnIndex: index,
                        reason: reason,
                        completedTurns: turnResults,
                        totalDurationSeconds: Date().timeIntervalSince(start)
                    )
                case .cancelled:
                    return .cancelledAt(
                        turnIndex: index,
                        completedTurns: turnResults,
                        totalDurationSeconds: Date().timeIntervalSince(start)
                    )
                case .failed(let err):
                    return .failedAt(
                        turnIndex: index,
                        error: err,
                        completedTurns: turnResults,
                        totalDurationSeconds: Date().timeIntervalSince(start)
                    )
                }
            }

            return .completedAllTurns(
                turns: turnResults,
                totalDurationSeconds: Date().timeIntervalSince(start)
            )
        }
    }

    /// Static — Swift 6 strict concurrency uyumu (actor self closure'a
    /// taşımaz). Caller actor'dan elindeki referansları geçer.
    private static func runSingleTurn(
        backend: any ChatBackend,
        history: [Message],
        system: String?,
        options: ChatOptions,
        budget: Budget,
        deadline: Date
    ) async -> TurnResult {
        let start = Date()
        let outputBuffer = TurnOutputBuffer()

        return await withTaskGroup(of: TurnResult.self) { group in
            group.addTask {
                do {
                    let stream = backend.send(messages: history, system: system, options: options)
                    for try await delta in stream {
                        if Task.isCancelled {
                            let snap = await outputBuffer.snapshot()
                            return TurnResult(output: snap, durationSeconds: Date().timeIntervalSince(start), outcome: .cancelled)
                        }
                        switch delta {
                        case .textChunk(let chunk):
                            await outputBuffer.append(chunk)
                            if let maxBytes = budget.maxOutputBytes,
                               await outputBuffer.byteCount() > maxBytes {
                                let snap = await outputBuffer.snapshot()
                                return TurnResult(
                                    output: snap,
                                    durationSeconds: Date().timeIntervalSince(start),
                                    outcome: .budgetExceeded(reason: .outputBytes)
                                )
                            }
                        case .done:
                            let snap = await outputBuffer.snapshot()
                            return TurnResult(
                                output: snap,
                                durationSeconds: Date().timeIntervalSince(start),
                                outcome: .completed
                            )
                        }
                    }
                    let snap = await outputBuffer.snapshot()
                    return TurnResult(
                        output: snap,
                        durationSeconds: Date().timeIntervalSince(start),
                        outcome: Task.isCancelled ? .cancelled : .completed
                    )
                } catch is CancellationError {
                    let snap = await outputBuffer.snapshot()
                    return TurnResult(output: snap, durationSeconds: Date().timeIntervalSince(start), outcome: .cancelled)
                } catch {
                    let snap = await outputBuffer.snapshot()
                    let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    return TurnResult(output: snap, durationSeconds: Date().timeIntervalSince(start), outcome: .failed(error: msg))
                }
            }

            group.addTask {
                let ns = UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                let snap = await outputBuffer.snapshot()
                if Task.isCancelled {
                    return TurnResult(output: snap, durationSeconds: Date().timeIntervalSince(start), outcome: .cancelled)
                }
                return TurnResult(
                    output: snap,
                    durationSeconds: Date().timeIntervalSince(start),
                    outcome: .budgetExceeded(reason: .duration)
                )
            }

            guard let first = await group.next() else {
                return TurnResult(output: "", durationSeconds: 0, outcome: .failed(error: "task-group boş"))
            }
            group.cancelAll()
            return first
        }
    }
}

/// Per-turn output biriktirici — worker ve watchdog Sendable-friendly paylaşır.
private actor TurnOutputBuffer {
    private var text: String = ""

    func append(_ chunk: String) {
        text.append(chunk)
    }

    func snapshot() -> String { text }
    func byteCount() -> Int { text.utf8.count }
}

/// Tek bir turn'ün sonucu — `MultiTurnSubagentResult.completedTurns` içinde toplanır.
public struct TurnResult: Sendable, Equatable {
    public let output: String
    public let durationSeconds: Double
    public let outcome: Outcome

    public init(output: String, durationSeconds: Double, outcome: Outcome) {
        self.output = output
        self.durationSeconds = durationSeconds
        self.outcome = outcome
    }

    public enum Outcome: Sendable, Equatable {
        case completed
        case budgetExceeded(reason: SubagentResult.BudgetReason)
        case cancelled
        case failed(error: String)
    }
}

/// Multi-turn run sonucu — completedAllTurns veya 3 erken çıkış vakasından biri.
public enum MultiTurnSubagentResult: Sendable, Equatable {
    case completedAllTurns(turns: [TurnResult], totalDurationSeconds: Double)
    case budgetExceededAt(
        turnIndex: Int,
        reason: SubagentResult.BudgetReason,
        completedTurns: [TurnResult],
        totalDurationSeconds: Double
    )
    case cancelledAt(
        turnIndex: Int,
        completedTurns: [TurnResult],
        totalDurationSeconds: Double
    )
    case failedAt(
        turnIndex: Int,
        error: String,
        completedTurns: [TurnResult],
        totalDurationSeconds: Double
    )

    /// Tüm tamamlanmış turn'leri döner (erken çıkışta da partial liste).
    public var completedTurns: [TurnResult] {
        switch self {
        case .completedAllTurns(let turns, _): return turns
        case .budgetExceededAt(_, _, let turns, _): return turns
        case .cancelledAt(_, let turns, _): return turns
        case .failedAt(_, _, let turns, _): return turns
        }
    }

    public var totalDurationSeconds: Double {
        switch self {
        case .completedAllTurns(_, let d): return d
        case .budgetExceededAt(_, _, _, let d): return d
        case .cancelledAt(_, _, let d): return d
        case .failedAt(_, _, _, let d): return d
        }
    }

    public var isFullySucceeded: Bool {
        if case .completedAllTurns = self { return true }
        return false
    }
}
