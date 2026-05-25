import XCTest

@testable import PixelBackends
@testable import PixelCore
@testable import PixelMacApp
@testable import PixelSubagent

@MainActor
final class SubagentMultiTurnManagerTests: XCTestCase {

    // MARK: - combinedOutput helper

    func testCombinedOutputEmptyTurns() {
        XCTAssertEqual(SubagentManager.combinedOutput(from: []), "")
    }

    func testCombinedOutputSingleTurn() {
        let turn = TurnResult(output: "İlk cevap", durationSeconds: 1.5, outcome: .completed)
        let combined = SubagentManager.combinedOutput(from: [turn])
        XCTAssertTrue(combined.contains("[Turn 1]"))
        XCTAssertTrue(combined.contains("1.5s"))
        XCTAssertTrue(combined.contains("İlk cevap"))
    }

    func testCombinedOutputMultipleTurnsNumberedAndSeparated() {
        let t1 = TurnResult(output: "A", durationSeconds: 1.0, outcome: .completed)
        let t2 = TurnResult(output: "B", durationSeconds: 2.0, outcome: .completed)
        let t3 = TurnResult(output: "C", durationSeconds: 3.0, outcome: .failed(error: "x"))
        let combined = SubagentManager.combinedOutput(from: [t1, t2, t3])
        XCTAssertTrue(combined.contains("[Turn 1]"))
        XCTAssertTrue(combined.contains("[Turn 2]"))
        XCTAssertTrue(combined.contains("[Turn 3]"))
        // Boş satır separator
        XCTAssertTrue(combined.contains("\n\n"))
    }

    // MARK: - dispatchMultiTurnAndWait happy path

    func testDispatchMultiTurnSuccessPopulatesSessionTurns() async {
        let backend = ScriptedMockBackend(scripts: ["t1 out", "t2 out", "t3 out"])
        let manager = SubagentManager(maxConcurrent: 3) { _ in backend }

        let outcome = await manager.dispatchMultiTurnAndWait(
            turns: ["İlk", "İkinci", "Üçüncü"],
            backend: .claude
        )

        guard case .success(let result) = outcome else {
            XCTFail("expected .success")
            return
        }
        XCTAssertTrue(result.isFullySucceeded)

        // Session UI'da görünür ve multiTurnTurns dolu olmalı.
        XCTAssertEqual(manager.sessions.count, 1)
        let session = manager.sessions[0]
        XCTAssertEqual(session.multiTurnTurns?.count, 3)
        XCTAssertTrue(session.status.isTerminal)
        XCTAssertEqual(session.multiTurnTurns?[0].output, "t1 out")
        // partialOutput combined format'ında olmalı
        XCTAssertTrue(session.partialOutput.contains("[Turn 1]"))
        XCTAssertTrue(session.partialOutput.contains("[Turn 3]"))
    }

    func testDispatchMultiTurnEmptyTurnsCompletesImmediately() async {
        let backend = ScriptedMockBackend(scripts: [])
        let manager = SubagentManager(maxConcurrent: 3) { _ in backend }

        let outcome = await manager.dispatchMultiTurnAndWait(turns: [], backend: .claude)

        guard case .success(let result) = outcome else {
            XCTFail("expected .success")
            return
        }
        XCTAssertTrue(result.completedTurns.isEmpty)
        // Session yaratılmaz (boş turn list early-out).
        XCTAssertTrue(manager.sessions.isEmpty)
    }

    // MARK: - Error paths

    func testDispatchMultiTurnBackendUnavailableFails() async {
        let manager = SubagentManager(maxConcurrent: 3) { _ in nil }
        let outcome = await manager.dispatchMultiTurnAndWait(
            turns: ["x"],
            backend: .claude
        )
        if case .failure(.backendUnavailable) = outcome {
            // expected
        } else {
            XCTFail("expected .backendUnavailable")
        }
    }

    func testDispatchMultiTurnCapReachedFails() async {
        let backend = SlowMockBackend()
        let manager = SubagentManager(maxConcurrent: 1) { _ in backend }

        // Cap doldur — one-shot dispatch ile fill et (await yapma, async devam etsin).
        _ = manager.dispatch(prompt: "filling", backend: .claude)
        XCTAssertEqual(manager.activeCount, 1)

        let outcome = await manager.dispatchMultiTurnAndWait(
            turns: ["second"],
            backend: .claude
        )
        if case .failure(.capReached) = outcome {
            // expected
        } else {
            XCTFail("expected .capReached")
        }
    }

    // MARK: - Prompt preview annotation

    func testDispatchMultiTurnPromptPreviewIncludesTurnCount() async {
        let backend = ScriptedMockBackend(scripts: ["a", "b"])
        let manager = SubagentManager(maxConcurrent: 3) { _ in backend }
        _ = await manager.dispatchMultiTurnAndWait(
            turns: ["İlk prompt", "İkinci"],
            backend: .claude
        )
        XCTAssertTrue(manager.sessions[0].prompt.contains("(+1 turn)"))
    }

    func testDispatchSingleTurnPromptPreviewNoAnnotation() async {
        let backend = ScriptedMockBackend(scripts: ["a"])
        let manager = SubagentManager(maxConcurrent: 3) { _ in backend }
        _ = await manager.dispatchMultiTurnAndWait(turns: ["tek"], backend: .claude)
        // Tek turn ise annotation yok.
        XCTAssertFalse(manager.sessions[0].prompt.contains("(+"))
        XCTAssertEqual(manager.sessions[0].prompt, "tek")
    }
}

// MARK: - Mock backends

private actor ScriptedMockBackend: ChatBackend {
    nonisolated var modelID: String { "mock-multi-turn" }
    private var scripts: [String]
    private var index: Int = 0

    init(scripts: [String]) {
        self.scripts = scripts
    }

    nonisolated func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                if let next = await self.popNext() {
                    continuation.yield(.textChunk(next))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private func popNext() -> String? {
        guard index < scripts.count else { return nil }
        let s = scripts[index]
        index += 1
        return s
    }
}

/// Cap-reached test için — uzun süre çalışır, .done yield etmez.
private actor SlowMockBackend: ChatBackend {
    nonisolated var modelID: String { "mock-slow" }

    nonisolated func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s — testin süresinden uzun
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}
