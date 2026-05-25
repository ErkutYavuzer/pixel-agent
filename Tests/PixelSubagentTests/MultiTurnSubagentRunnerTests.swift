import Foundation
import XCTest

@testable import PixelCore
@testable import PixelSubagent

final class MultiTurnSubagentRunnerTests: XCTestCase {

    // MARK: - Multi-turn happy paths

    func testCompletesAllTurnsAccumulatesHistory() async {
        let backend = ScriptedMockBackend(scripts: [
            "Turn 1 cevap",
            "Turn 2 cevap",
            "Turn 3 cevap",
        ])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)
        let result = await runner.runConversation(turns: ["İlk", "İkinci", "Üçüncü"])

        guard case .completedAllTurns(let turns, _) = result else {
            XCTFail("expected .completedAllTurns")
            return
        }
        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(turns.map(\.output), ["Turn 1 cevap", "Turn 2 cevap", "Turn 3 cevap"])
        XCTAssertTrue(turns.allSatisfy { $0.outcome == .completed })
    }

    func testHistoryGrowsAcrossTurns() async {
        let backend = HistoryCapturingBackend()
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)
        _ = await runner.runConversation(turns: ["A", "B", "C"])

        // 1. turn: 1 user mesajı; 2. turn: 1 user + 1 assistant + 1 user; 3. turn: önceki + 1 user.
        let capturedSizes = await backend.callHistorySizes
        XCTAssertEqual(capturedSizes, [1, 3, 5])
    }

    func testEmptyTurnsCompletesImmediately() async {
        let backend = ScriptedMockBackend(scripts: [])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)
        let result = await runner.runConversation(turns: [])

        guard case .completedAllTurns(let turns, _) = result else {
            XCTFail("expected .completedAllTurns")
            return
        }
        XCTAssertTrue(turns.isEmpty)
    }

    // MARK: - Result type

    func testResultIsFullySucceededOnlyForCompletedAllTurns() {
        let allCompleted: MultiTurnSubagentResult = .completedAllTurns(turns: [], totalDurationSeconds: 0)
        let budgetExceeded: MultiTurnSubagentResult = .budgetExceededAt(
            turnIndex: 1, reason: .duration, completedTurns: [], totalDurationSeconds: 0
        )
        let cancelled: MultiTurnSubagentResult = .cancelledAt(
            turnIndex: 0, completedTurns: [], totalDurationSeconds: 0
        )
        let failed: MultiTurnSubagentResult = .failedAt(
            turnIndex: 2, error: "x", completedTurns: [], totalDurationSeconds: 0
        )

        XCTAssertTrue(allCompleted.isFullySucceeded)
        XCTAssertFalse(budgetExceeded.isFullySucceeded)
        XCTAssertFalse(cancelled.isFullySucceeded)
        XCTAssertFalse(failed.isFullySucceeded)
    }

    func testCompletedTurnsGetterReturnsListForAllCases() {
        let turn = TurnResult(output: "x", durationSeconds: 1, outcome: .completed)
        XCTAssertEqual(
            (MultiTurnSubagentResult.completedAllTurns(turns: [turn], totalDurationSeconds: 1)).completedTurns,
            [turn]
        )
        XCTAssertEqual(
            (MultiTurnSubagentResult.budgetExceededAt(turnIndex: 1, reason: .duration, completedTurns: [turn], totalDurationSeconds: 1)).completedTurns,
            [turn]
        )
        XCTAssertEqual(
            (MultiTurnSubagentResult.cancelledAt(turnIndex: 0, completedTurns: [turn], totalDurationSeconds: 1)).completedTurns,
            [turn]
        )
        XCTAssertEqual(
            (MultiTurnSubagentResult.failedAt(turnIndex: 1, error: "x", completedTurns: [turn], totalDurationSeconds: 1)).completedTurns,
            [turn]
        )
    }

    func testTotalDurationSecondsGetterForAllCases() {
        XCTAssertEqual(MultiTurnSubagentResult.completedAllTurns(turns: [], totalDurationSeconds: 1.5).totalDurationSeconds, 1.5)
        XCTAssertEqual(MultiTurnSubagentResult.budgetExceededAt(turnIndex: 0, reason: .duration, completedTurns: [], totalDurationSeconds: 2.0).totalDurationSeconds, 2.0)
        XCTAssertEqual(MultiTurnSubagentResult.cancelledAt(turnIndex: 0, completedTurns: [], totalDurationSeconds: 0.5).totalDurationSeconds, 0.5)
        XCTAssertEqual(MultiTurnSubagentResult.failedAt(turnIndex: 0, error: "x", completedTurns: [], totalDurationSeconds: 3.0).totalDurationSeconds, 3.0)
    }
}

// MARK: - Mock backends

/// Her turn için sırayla pre-scripted çıktı verir. Sequential test için.
private actor ScriptedMockBackend: ChatBackend {
    nonisolated var modelID: String { "mock-scripted" }
    private var scripts: [String]
    private var index: Int = 0

    init(scripts: [String]) {
        self.scripts = scripts
    }

    nonisolated func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let next = await self.popNext()
                if let chunk = next {
                    continuation.yield(.textChunk(chunk))
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

/// History.count'unu her send çağrısında kaydeder — accumulation test'i için.
private actor HistoryCapturingBackend: ChatBackend {
    nonisolated var modelID: String { "mock-history" }
    var callHistorySizes: [Int] = []

    nonisolated func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, Error> {
        let count = messages.count
        return AsyncThrowingStream { continuation in
            Task {
                await self.record(count)
                continuation.yield(.textChunk("ok"))
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private func record(_ count: Int) {
        callHistorySizes.append(count)
    }
}
