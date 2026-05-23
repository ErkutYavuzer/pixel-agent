import Foundation
import PixelCore

/// Bir subagent çalışması sırasında dış dünyaya yayınlanan olaylar.
///
/// `runStreaming` AsyncStream'inde sırasıyla yayınlanır:
/// 1. Sıfır veya daha fazla `.chunk(String)` — backend'den gelen partial output.
/// 2. Tek bir terminal `.finished(SubagentResult)` — completed/budgetExceeded/cancelled/failed.
public enum SubagentEvent: Sendable, Equatable {
    case chunk(String)
    case finished(SubagentResult)
}

/// Tek-turlu (one-shot) subagent çalıştırıcısı.
///
/// İki API:
/// - `run(prompt:)` — sadece final `SubagentResult` döndürür (backwards compat).
/// - `runStreaming(prompt:)` — AsyncStream<SubagentEvent>; UI'ya canlı partial output
///   akıtmak için.
///
/// **Mimari notlar:**
/// - Backend ve watchdog `withTaskGroup` ile yarışır; ilk biten kazanır.
/// - Çıktı paylaşılan `OutputBuffer` actor'ında biriktirilir — watchdog süre
///   dolduğunda partialOutput'a erişebilir.
/// - `AgentContext.currentSubagentID` TaskLocal binding ile bu çalışma süresince
///   set edilir; backend / tool zinciri kim ID'sini sorgularsa öğrenir.
/// - `Task.cancel()` çağrısı `cancelled` ile sonuçlanır (cooperative).
public actor SubagentRunner {
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

    /// Backwards-compatible API. İçeride streaming çalışır ama sadece final sonuç döner.
    public func run(
        prompt: String,
        system: String? = nil,
        options: ChatOptions = ChatOptions()
    ) async -> SubagentResult {
        await runInternal(prompt: prompt, system: system, options: options, onChunk: nil)
    }

    /// Streaming API — caller her chunk için event alır, terminal event'te
    /// `SubagentResult` gömülü olarak gelir. Stream her zaman tam olarak bir
    /// `.finished` event ile biter.
    ///
    /// `nonisolated` — caller actor await'i olmadan stream döndürür; gerçek iş
    /// içeride Task spawn edip `runInternal`'ı çağırır.
    public nonisolated func runStreaming(
        prompt: String,
        system: String? = nil,
        options: ChatOptions = ChatOptions()
    ) -> AsyncStream<SubagentEvent> {
        AsyncStream(SubagentEvent.self) { continuation in
            let task = Task {
                let result = await self.runInternal(
                    prompt: prompt,
                    system: system,
                    options: options,
                    onChunk: { chunk in
                        continuation.yield(.chunk(chunk))
                    }
                )
                continuation.yield(.finished(result))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Hem `run` hem `runStreaming` için ortak çalıştırıcı. `onChunk` `nil` ise
    /// chunk'lar yalnız OutputBuffer'a yazılır; `runStreaming` durumunda her
    /// chunk için event yayını yapar.
    private func runInternal(
        prompt: String,
        system: String?,
        options: ChatOptions,
        onChunk: (@Sendable (String) -> Void)?
    ) async -> SubagentResult {
        let start = Date()
        let buffer = OutputBuffer()
        let budget = self.budget
        let id = self.id
        let backend = self.backend

        return await AgentContext.$currentSubagentID.withValue(id) {
            await withTaskGroup(of: SubagentResult.self) { group in
                // 1) Worker — backend stream'i tüket
                group.addTask {
                    await Self.runWorker(
                        backend: backend,
                        prompt: prompt,
                        system: system,
                        options: options,
                        budget: budget,
                        buffer: buffer,
                        start: start,
                        onChunk: onChunk
                    )
                }

                // 2) Watchdog — budget.maxDuration sonra .budgetExceeded
                group.addTask {
                    let ns = UInt64(max(0, budget.maxDuration) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    if Task.isCancelled {
                        // Worker önce bitti, watchdog cancel edildi — değer kullanılmayacak
                        return .cancelled(
                            partialOutput: await buffer.snapshot().text,
                            durationSeconds: Date().timeIntervalSince(start)
                        )
                    }
                    let snap = await buffer.snapshot()
                    return .budgetExceeded(
                        reason: .duration,
                        partialOutput: snap.text,
                        durationSeconds: budget.maxDuration
                    )
                }

                // İlk biten kazansın
                guard let first = await group.next() else {
                    let snap = await buffer.snapshot()
                    return .failed(
                        error: "task-group boş döndü",
                        partialOutput: snap.text,
                        durationSeconds: Date().timeIntervalSince(start)
                    )
                }
                group.cancelAll()
                // Kalan task'in ürettiği değeri yutmamız gerek (otherwise
                // task-group implicit await sonrası value drop edilir, OK).
                return first
            }
        }
    }

    private static func runWorker(
        backend: any ChatBackend,
        prompt: String,
        system: String?,
        options: ChatOptions,
        budget: Budget,
        buffer: OutputBuffer,
        start: Date,
        onChunk: (@Sendable (String) -> Void)?
    ) async -> SubagentResult {
        let userMessage = Message(role: .user, text: prompt)
        do {
            let stream = backend.send(messages: [userMessage], system: system, options: options)
            for try await delta in stream {
                if Task.isCancelled {
                    let snap = await buffer.snapshot()
                    return .cancelled(
                        partialOutput: snap.text,
                        durationSeconds: Date().timeIntervalSince(start)
                    )
                }
                switch delta {
                case .textChunk(let chunk):
                    await buffer.append(chunk)
                    onChunk?(chunk)
                    if let maxBytes = budget.maxOutputBytes {
                        let snap = await buffer.snapshot()
                        if snap.bytes > maxBytes {
                            return .budgetExceeded(
                                reason: .outputBytes,
                                partialOutput: snap.text,
                                durationSeconds: Date().timeIntervalSince(start)
                            )
                        }
                    }
                case .done:
                    let snap = await buffer.snapshot()
                    return .completed(
                        output: snap.text,
                        durationSeconds: Date().timeIntervalSince(start)
                    )
                }
            }
            // Stream `.done` vermeden bitti. İki olası neden:
            //  - Outer Task cancel olduğu için AsyncSequence iteration sonlandı → `.cancelled`
            //  - CLI subprocess `.done` yield etmeden graceful exit etti → `.completed`
            let snap = await buffer.snapshot()
            if Task.isCancelled {
                return .cancelled(
                    partialOutput: snap.text,
                    durationSeconds: Date().timeIntervalSince(start)
                )
            }
            return .completed(
                output: snap.text,
                durationSeconds: Date().timeIntervalSince(start)
            )
        } catch is CancellationError {
            let snap = await buffer.snapshot()
            return .cancelled(
                partialOutput: snap.text,
                durationSeconds: Date().timeIntervalSince(start)
            )
        } catch {
            let snap = await buffer.snapshot()
            return .failed(
                error: (error as? LocalizedError)?.errorDescription ?? "\(error)",
                partialOutput: snap.text,
                durationSeconds: Date().timeIntervalSince(start)
            )
        }
    }
}

/// Paylaşılan biriktirici — worker ve watchdog aynı çıktı parçacıklarını okur.
private actor OutputBuffer {
    private var text: String = ""
    private var bytes: Int = 0

    func append(_ chunk: String) {
        text.append(chunk)
        bytes += chunk.utf8.count
    }

    func snapshot() -> (text: String, bytes: Int) {
        (text, bytes)
    }
}
