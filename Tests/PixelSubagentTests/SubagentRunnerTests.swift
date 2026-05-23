import XCTest
import PixelCore
@testable import PixelSubagent

/// Minimal mock backend — chunk listesi + opsiyonel chunk arası delay + throws option.
private struct MockBackend: ChatBackend {
    let modelID: String
    let chunks: [String]
    let chunkDelay: UInt64  // nanoseconds
    let endWithoutDone: Bool
    let throwAfter: Int?  // throw an error after N chunks (nil = never)

    init(
        modelID: String = "mock",
        chunks: [String],
        chunkDelay: UInt64 = 0,
        endWithoutDone: Bool = false,
        throwAfter: Int? = nil
    ) {
        self.modelID = modelID
        self.chunks = chunks
        self.chunkDelay = chunkDelay
        self.endWithoutDone = endWithoutDone
        self.throwAfter = throwAfter
    }

    func send(
        messages: [Message],
        system: String?,
        options: ChatOptions
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let chunks = self.chunks
        let delay = self.chunkDelay
        let endWithoutDone = self.endWithoutDone
        let throwAfter = self.throwAfter
        return AsyncThrowingStream { continuation in
            let task = Task {
                for (i, chunk) in chunks.enumerated() {
                    if Task.isCancelled { break }
                    if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                    if let throwAfter, i == throwAfter {
                        continuation.finish(throwing: NSError(
                            domain: "MockBackendError",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "mock failure"]
                        ))
                        return
                    }
                    continuation.yield(.textChunk(chunk))
                }
                if !endWithoutDone {
                    continuation.yield(.done)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

final class SubagentRunnerTests: XCTestCase {
    func testCompletedHappyPath() async {
        let backend = MockBackend(chunks: ["Merhaba", " dünya"])
        let runner = SubagentRunner(backend: backend, budget: Budget(maxDuration: 5))
        let result = await runner.run(prompt: "selam")
        guard case .completed(let output, let duration) = result else {
            return XCTFail("Expected .completed, got \(result)")
        }
        XCTAssertEqual(output, "Merhaba dünya")
        XCTAssertGreaterThan(duration, 0)
    }

    func testBudgetExceededByDuration() async {
        // 2s chunk delay × 5 chunk = 10s; budget 0.5s ile aşılır
        let backend = MockBackend(chunks: ["a", "b", "c", "d", "e"], chunkDelay: 2_000_000_000)
        let runner = SubagentRunner(backend: backend, budget: Budget(maxDuration: 0.5))
        let result = await runner.run(prompt: "x")
        guard case .budgetExceeded(let reason, _, let duration) = result else {
            return XCTFail("Expected .budgetExceeded, got \(result)")
        }
        XCTAssertEqual(reason, .duration)
        XCTAssertGreaterThanOrEqual(duration, 0.5)
        XCTAssertLessThan(duration, 1.5)
    }

    func testBudgetExceededByOutputBytes() async {
        let backend = MockBackend(chunks: ["aaaa", "bbbb", "cccc"])  // 12 byte
        let runner = SubagentRunner(
            backend: backend,
            budget: Budget(maxDuration: 5, maxOutputBytes: 8)
        )
        let result = await runner.run(prompt: "x")
        guard case .budgetExceeded(let reason, let partial, _) = result else {
            return XCTFail("Expected .budgetExceeded, got \(result)")
        }
        XCTAssertEqual(reason, .outputBytes)
        XCTAssertGreaterThan(partial.utf8.count, 8)  // İlk aşan chunk dahil
    }

    func testFailedWhenBackendThrows() async {
        let backend = MockBackend(chunks: ["a", "b", "c"], throwAfter: 1)
        let runner = SubagentRunner(backend: backend, budget: .default)
        let result = await runner.run(prompt: "x")
        guard case .failed(let error, let partial, _) = result else {
            return XCTFail("Expected .failed, got \(result)")
        }
        XCTAssertTrue(error.contains("mock failure"))
        XCTAssertEqual(partial, "a")  // ilk chunk geldi, ikinci hata
    }

    func testCompletesWhenStreamEndsWithoutDone() async {
        // CLI subprocess exit edebilir without explicit .done — yine completed sayılır
        let backend = MockBackend(chunks: ["foo"], endWithoutDone: true)
        let runner = SubagentRunner(backend: backend, budget: .default)
        let result = await runner.run(prompt: "x")
        guard case .completed(let output, _) = result else {
            return XCTFail("Expected .completed (graceful), got \(result)")
        }
        XCTAssertEqual(output, "foo")
    }

    func testSubagentIDIsTaskLocalDuringRun() async {
        // Backend.send() içinde TaskLocal değerini sorgulayalım
        struct ProbeBackend: ChatBackend {
            let modelID = "probe"
            let probe: @Sendable () -> Void
            func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error> {
                let probe = self.probe
                return AsyncThrowingStream { continuation in
                    probe()
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
        }

        let expectedID = SubagentID()
        let observed = LockedBox<SubagentID?>()
        let backend = ProbeBackend {
            observed.set(AgentContext.currentSubagentID)
        }
        let runner = SubagentRunner(backend: backend, budget: .default, id: expectedID)
        _ = await runner.run(prompt: "x")
        XCTAssertEqual(observed.get(), expectedID)
    }

    func testSubagentIDIsNilOutsideRun() async {
        XCTAssertNil(AgentContext.currentSubagentID)
        let backend = MockBackend(chunks: ["x"])
        _ = await SubagentRunner(backend: backend).run(prompt: "x")
        // run bittiğinde TaskLocal binding kapsamı dışında — yine nil
        XCTAssertNil(AgentContext.currentSubagentID)
    }

    // MARK: - runStreaming (Faz 4)

    func testRunStreamingEmitsChunksThenFinished() async {
        let backend = MockBackend(chunks: ["foo", "bar", "baz"])
        let runner = SubagentRunner(backend: backend)
        var events: [SubagentEvent] = []
        for await event in runner.runStreaming(prompt: "x") {
            events.append(event)
        }

        // 3 chunk + 1 finished beklenir
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0], .chunk("foo"))
        XCTAssertEqual(events[1], .chunk("bar"))
        XCTAssertEqual(events[2], .chunk("baz"))
        guard case .finished(let result) = events[3] else {
            return XCTFail("Son event finished olmalı, got \(events[3])")
        }
        guard case .completed(let output, _) = result else {
            return XCTFail("Result completed olmalı, got \(result)")
        }
        XCTAssertEqual(output, "foobarbaz")
    }

    func testRunStreamingEndsWithFinishedOnBudgetExceeded() async {
        // 2s chunk delay × 5 chunk = 10s; 0.3s budget ile duration aşılır
        let backend = MockBackend(chunks: ["a", "b", "c"], chunkDelay: 2_000_000_000)
        let runner = SubagentRunner(backend: backend, budget: Budget(maxDuration: 0.3))
        var finishedResult: SubagentResult?
        for await event in runner.runStreaming(prompt: "x") {
            if case .finished(let r) = event { finishedResult = r }
        }
        guard let result = finishedResult else {
            return XCTFail("finished event görülmedi")
        }
        guard case .budgetExceeded(let reason, _, _) = result else {
            return XCTFail("budgetExceeded bekleniyordu, got \(result)")
        }
        XCTAssertEqual(reason, .duration)
    }

    func testRunStreamingFinishedAsLastEventOnCLIExitWithoutDone() async {
        // CLI subprocess `.done` yield etmeden bitti senaryosu — graceful completed.
        let backend = MockBackend(chunks: ["partial"], endWithoutDone: true)
        let runner = SubagentRunner(backend: backend)
        var events: [SubagentEvent] = []
        for await event in runner.runStreaming(prompt: "x") {
            events.append(event)
        }
        XCTAssertEqual(events.count, 2)  // 1 chunk + 1 finished
        XCTAssertEqual(events[0], .chunk("partial"))
        guard case .finished(let result) = events.last,
              case .completed(let output, _) = result else {
            return XCTFail("Beklenen .finished(.completed), got \(events.last as Any)")
        }
        XCTAssertEqual(output, "partial")
    }
}

// MARK: - Test helpers

/// Minimal thread-safe value box.
private final class LockedBox<T>: @unchecked Sendable {
    private var value: T?
    private let lock = NSLock()
    func set(_ v: T?) { lock.lock(); value = v; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}
