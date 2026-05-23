import XCTest
import PixelBackends
import PixelCore
import PixelSubagent
@testable import PixelMacApp

/// Aynı MockBackend pattern PixelSubagentTests'tekiyle paralel. PixelMacAppTests target'ı
/// PixelSubagentTests'i import edemediği için local copy.
private struct MockBackend: ChatBackend {
    let modelID: String
    let chunks: [String]
    let chunkDelay: UInt64

    init(modelID: String = "mock", chunks: [String], chunkDelay: UInt64 = 0) {
        self.modelID = modelID
        self.chunks = chunks
        self.chunkDelay = chunkDelay
    }

    func send(
        messages: [Message],
        system: String?,
        options: ChatOptions
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let chunks = self.chunks
        let delay = self.chunkDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                    continuation.yield(.textChunk(chunk))
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
final class SubagentManagerTests: XCTestCase {
    /// Hızlı tamamlanan backend ile manager — basit happy path testleri için.
    private func makeManager(
        maxConcurrent: Int = 3,
        chunkDelay: UInt64 = 0
    ) -> SubagentManager {
        SubagentManager(maxConcurrent: maxConcurrent) { kind in
            MockBackend(
                modelID: kind.rawValue,
                chunks: ["sub-", "agent", " ok"],
                chunkDelay: chunkDelay
            )
        }
    }

    // MARK: - 1. Dispatch creates session

    func testDispatchCreatesPendingSession() async {
        let manager = makeManager()
        let result = manager.dispatch(prompt: "selam", backend: .claude)

        guard case .success(let id) = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].id, id)
        XCTAssertEqual(manager.sessions[0].prompt, "selam")
        XCTAssertEqual(manager.sessions[0].backendKind, .claude)
        // Task henüz hop etmedi — status pending veya running olabilir; ikisi de OK.
        XCTAssertTrue(manager.sessions[0].status == .pending
                      || manager.sessions[0].status == .running)
    }

    // MARK: - 2. Completion happy path

    func testDispatchAndWaitReturnsCompletedResult() async {
        let manager = makeManager()
        let result = await manager.dispatchAndWait(prompt: "x", backend: .gemini)

        guard case .success(let subResult) = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        guard case .completed(let output, _) = subResult else {
            return XCTFail("Expected .completed, got \(subResult)")
        }
        XCTAssertEqual(output, "sub-agent ok")

        // Session terminal'e geçti
        XCTAssertEqual(manager.sessions.count, 1)
        XCTAssertEqual(manager.sessions[0].status, .completed)
        XCTAssertNotNil(manager.sessions[0].finishedAt)
        XCTAssertNotNil(manager.sessions[0].result)
    }

    // MARK: - 3. Cancel transitions to .cancelled

    func testCancelTransitionsToCancelled() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in
            // 2s chunk delay × 5 chunk = 10s; cancel ile çok daha erken bitsin
            MockBackend(chunks: ["a", "b", "c", "d", "e"], chunkDelay: 2_000_000_000)
        }

        let waitTask = Task { await manager.dispatchAndWait(prompt: "long", backend: .codex) }

        // Task fire olsun, status .running'e geçsin
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let id = manager.sessions.first?.id else {
            return XCTFail("Session bulunamadı")
        }
        manager.cancel(id)

        let outerResult = await waitTask.value
        guard case .success(let subResult) = outerResult else {
            return XCTFail("Expected .success(.cancelled), got \(outerResult)")
        }
        guard case .cancelled = subResult else {
            return XCTFail("Expected .cancelled, got \(subResult)")
        }
        XCTAssertEqual(manager.sessions[0].status, .cancelled)
    }

    // MARK: - 4. Cap reached rejects 4th dispatch

    func testCapReachedRejectsFourthDispatch() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in
            // Hiç bitmeyecek kadar yavaş — testler bitince Task cancel olur
            MockBackend(chunks: ["x"], chunkDelay: 10_000_000_000)
        }

        for _ in 0..<3 {
            let r = manager.dispatch(prompt: "x", backend: .claude)
            guard case .success = r else {
                return XCTFail("İlk 3 dispatch başarılı olmalı, got \(r)")
            }
        }

        let fourth = manager.dispatch(prompt: "x", backend: .claude)
        guard case .failure(let err) = fourth else {
            return XCTFail("4. dispatch reddedilmeliydi, got \(fourth)")
        }
        XCTAssertEqual(err, .capReached(maxConcurrent: 3))
        XCTAssertEqual(manager.sessions.count, 3)
        XCTAssertTrue(manager.isCapReached)

        // Cleanup — başka türlü bekleyen Task'ler test sonrası leak olur
        manager.sessions.forEach { manager.cancel($0.id) }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - 5. Cap frees after completion

    func testCapFreesAfterCompletion() async {
        let manager = makeManager()

        // 3 hızlı dispatch (default delay=0)
        for _ in 0..<3 {
            _ = await manager.dispatchAndWait(prompt: "x", backend: .claude)
        }

        // Hepsi terminal — activeCount=0
        XCTAssertEqual(manager.activeCount, 0)
        XCTAssertFalse(manager.isCapReached)

        // 4. dispatch başarılı olmalı
        let fourth = await manager.dispatchAndWait(prompt: "fourth", backend: .claude)
        guard case .success = fourth else {
            return XCTFail("Cap free sonrası 4. dispatch başarılı olmalı, got \(fourth)")
        }
        XCTAssertEqual(manager.sessions.count, 4)
    }

    // MARK: - 6. dispatchAndWait returns to caller

    func testDispatchAndWaitWaitsForResult() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in
            MockBackend(chunks: ["hello"], chunkDelay: 80_000_000)  // 80ms — kısa ama ölçülebilir
        }

        let start = Date()
        let result = await manager.dispatchAndWait(prompt: "x", backend: .gemini)
        let elapsed = Date().timeIntervalSince(start)

        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
        XCTAssertGreaterThan(elapsed, 0.05)  // En azından mock delay'i bekledi
    }

    // MARK: - 7. Invalid backend resolver

    func testDispatchFailsWhenBackendUnavailable() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in nil }

        let result = manager.dispatch(prompt: "x", backend: .claude)
        guard case .failure(let err) = result else {
            return XCTFail("Expected .failure, got \(result)")
        }
        XCTAssertEqual(err, .backendUnavailable(.claude))
        XCTAssertEqual(manager.sessions.count, 0)
    }

    // MARK: - 8. Partial output build-up during streaming

    func testPartialOutputBuildsUpDuringStreaming() async {
        // Yavaş chunk akışı — chunk'lar arası 80ms; ilk chunk geldikten sonra
        // partialOutput dolu olmalı, terminal'e ulaşmadan önce.
        let manager = SubagentManager(maxConcurrent: 3) { _ in
            MockBackend(chunks: ["alpha", "-beta", "-gamma"], chunkDelay: 80_000_000)
        }
        let dispatchResult = manager.dispatch(prompt: "x", backend: .claude)
        guard case .success(let id) = dispatchResult else {
            return XCTFail("Expected success, got \(dispatchResult)")
        }

        // İlk chunk'tan sonra partial dolu olmalı, henüz terminal değil
        try? await Task.sleep(nanoseconds: 200_000_000)
        let mid = manager.sessions.first(where: { $0.id == id })
        XCTAssertNotNil(mid)
        XCTAssertFalse(mid?.partialOutput.isEmpty ?? true)
        XCTAssertEqual(mid?.status, .running)

        // Streaming bitince partialOutput == result.output
        try? await Task.sleep(nanoseconds: 400_000_000)
        let final = manager.sessions.first(where: { $0.id == id })
        XCTAssertEqual(final?.status, .completed)
        XCTAssertEqual(final?.partialOutput, "alpha-beta-gamma")
        XCTAssertEqual(final?.result?.output, "alpha-beta-gamma")
    }

    // MARK: - 9. Dismiss only removes terminal sessions

    func testDismissOnlyRemovesTerminal() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in
            MockBackend(chunks: ["x"], chunkDelay: 5_000_000_000)
        }
        let r = manager.dispatch(prompt: "x", backend: .claude)
        guard case .success(let id) = r else {
            return XCTFail("Expected .success")
        }

        // Hâlâ running, dismiss no-op olmalı
        manager.dismiss(id)
        XCTAssertEqual(manager.sessions.count, 1)

        // Cancel et, terminal'e geç
        manager.cancel(id)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(manager.sessions[0].status, .cancelled)

        // Şimdi dismiss çalışmalı
        manager.dismiss(id)
        XCTAssertEqual(manager.sessions.count, 0)
    }
}
