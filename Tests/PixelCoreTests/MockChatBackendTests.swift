import XCTest

@testable import PixelCore

struct MockChatBackend: ChatBackend {
    let modelID: String
    let chunks: [String]
    let delayNanoseconds: UInt64

    init(modelID: String = "mock-1", chunks: [String], delayNanoseconds: UInt64 = 0) {
        self.modelID = modelID
        self.chunks = chunks
        self.delayNanoseconds = delayNanoseconds
    }

    func send(
        messages: [Message],
        system: String?
    ) -> AsyncThrowingStream<StreamDelta, any Error> {
        let chunks = self.chunks
        let delay = self.delayNanoseconds
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    continuation.yield(.textChunk(chunk))
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

final class MockChatBackendTests: XCTestCase {
    func testStreamYieldsChunksThenDone() async throws {
        let backend = MockChatBackend(chunks: ["Merhaba", " dünya"])
        var collected: [StreamDelta] = []
        for try await delta in backend.send(messages: [], system: nil) {
            collected.append(delta)
        }
        XCTAssertEqual(collected, [.textChunk("Merhaba"), .textChunk(" dünya"), .done])
    }

    func testModelIDExposed() {
        let backend = MockChatBackend(modelID: "test-model-7", chunks: [])
        XCTAssertEqual(backend.modelID, "test-model-7")
    }

    func testEmptyChunksYieldsOnlyDone() async throws {
        let backend = MockChatBackend(chunks: [])
        var collected: [StreamDelta] = []
        for try await delta in backend.send(messages: [], system: nil) {
            collected.append(delta)
        }
        XCTAssertEqual(collected, [.done])
    }
}
