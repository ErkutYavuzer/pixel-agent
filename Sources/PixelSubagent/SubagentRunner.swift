import Foundation
import PixelCore

/// Tek-turlu (one-shot) subagent çalıştırıcısı.
///
/// Bir prompt'u verilen `ChatBackend`'e gönderir, budget içinde tamamlanırsa
/// `.completed`, aksi halde `.budgetExceeded` / `.cancelled` / `.failed` döner.
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

    public func run(
        prompt: String,
        system: String? = nil,
        options: ChatOptions = ChatOptions()
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
                        start: start
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
        start: Date
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
