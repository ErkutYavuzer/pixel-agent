import Foundation
import XCTest

@testable import PixelCore
@testable import PixelSubagent

final class MultiTurnSubagentStreamingTests: XCTestCase {

    // MARK: - Event sequencing

    func testStreamYieldsTurnBoundariesAndChunks() async {
        let backend = ChunkedMockBackend(scripts: [
            ["İlk ", "kısım ", "tamam."],
            ["İkinci ", "turn."],
        ])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)

        var events: [MultiTurnSubagentEvent] = []
        for await event in runner.runConversationStreaming(turns: ["a", "b"]) {
            events.append(event)
        }

        // İlk event turnStarted(0), son event allFinished, arada N chunk + turnFinished.
        guard case .turnStarted(let idx0, _) = events.first else {
            XCTFail("first event should be turnStarted")
            return
        }
        XCTAssertEqual(idx0, 0)

        guard case .allFinished = events.last else {
            XCTFail("last event should be allFinished")
            return
        }

        // 2 turn × 3+2 chunks + 2 turnStarted + 2 turnFinished + 1 allFinished
        let chunkCount = events.filter {
            if case .chunk = $0 { return true } else { return false }
        }.count
        XCTAssertEqual(chunkCount, 5, "3 chunk turn 1 + 2 chunk turn 2 = 5")

        let turnFinishedCount = events.filter {
            if case .turnFinished = $0 { return true } else { return false }
        }.count
        XCTAssertEqual(turnFinishedCount, 2)
    }

    func testStreamChunksTaggedWithCorrectTurnIndex() async {
        let backend = ChunkedMockBackend(scripts: [
            ["a1", "a2"],
            ["b1"],
        ])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)

        var chunkTurnIndices: [Int] = []
        for await event in runner.runConversationStreaming(turns: ["t1", "t2"]) {
            if case .chunk(let idx, _) = event {
                chunkTurnIndices.append(idx)
            }
        }
        // İlk 2 chunk turn 0; üçüncü chunk turn 1.
        XCTAssertEqual(chunkTurnIndices, [0, 0, 1])
    }

    func testStreamTerminatesWithAllFinishedExactlyOnce() async {
        let backend = ChunkedMockBackend(scripts: [["x"]])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)

        var allFinishedCount = 0
        for await event in runner.runConversationStreaming(turns: ["t"]) {
            if case .allFinished = event {
                allFinishedCount += 1
            }
        }
        XCTAssertEqual(allFinishedCount, 1)
    }

    // MARK: - Backwards compatibility

    func testRunConversationNonStreamingStillWorks() async {
        let backend = ChunkedMockBackend(scripts: [
            ["a"],
            ["b"],
        ])
        let runner = MultiTurnSubagentRunner(backend: backend, budget: .default)
        let result = await runner.runConversation(turns: ["t1", "t2"])

        guard case .completedAllTurns(let turns, _) = result else {
            XCTFail("expected .completedAllTurns")
            return
        }
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns.map(\.output), ["a", "b"])
    }

    // MARK: - Event Equatable

    func testEventsAreEquatable() {
        XCTAssertEqual(
            MultiTurnSubagentEvent.turnStarted(index: 1, prompt: "x"),
            .turnStarted(index: 1, prompt: "x")
        )
        XCTAssertNotEqual(
            MultiTurnSubagentEvent.chunk(turnIndex: 0, chunk: "a"),
            .chunk(turnIndex: 1, chunk: "a")
        )
    }
}

/// Per-turn script — her turn için chunk array. Backend.send sırayla bir turn'ün
/// tüm chunk'larını yield eder + .done.
private actor ChunkedMockBackend: ChatBackend {
    nonisolated var modelID: String { "mock-chunked" }
    private var scripts: [[String]]
    private var index: Int = 0

    init(scripts: [[String]]) {
        self.scripts = scripts
    }

    nonisolated func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                let chunks = await self.popNext()
                for chunk in chunks {
                    continuation.yield(.textChunk(chunk))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private func popNext() -> [String] {
        guard index < scripts.count else { return [] }
        let chunks = scripts[index]
        index += 1
        return chunks
    }
}
