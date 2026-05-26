import XCTest
@testable import PixelVoice

/// **Sprint 42 (v0.2.69):** MockVoiceProvider state machine + stream tests.
final class MockVoiceProviderTests: XCTestCase {

    func testStartSetsRunningState() async throws {
        let provider = MockVoiceProvider()
        try await provider.start()
        let isStarted = await provider.snapshotIsStarted()
        XCTAssertTrue(isStarted)
    }

    func testStopClearsState() async throws {
        let provider = MockVoiceProvider()
        try await provider.start()
        await provider.stop()
        let isStarted = await provider.snapshotIsStarted()
        XCTAssertFalse(isStarted)
    }

    func testSpeakRecordsText() async {
        let provider = MockVoiceProvider()
        await provider.speak("Merhaba dünya")
        await provider.speak("İkinci mesaj")
        let texts = await provider.snapshotSpokenTexts()
        XCTAssertEqual(texts.count, 2)
        XCTAssertEqual(texts[0], "Merhaba dünya")
        XCTAssertEqual(texts[1], "İkinci mesaj")
    }

    func testAuthorizedReturnsTrue() async {
        let provider = MockVoiceProvider()
        let authed = await provider.isAuthorized()
        XCTAssertTrue(authed)
    }

    func testProviderName() {
        let provider = MockVoiceProvider()
        XCTAssertEqual(provider.providerName, "Mock")
    }

    func testTranscriptStreamReceivesEvents() async throws {
        let provider = MockVoiceProvider()
        let stream = provider.transcriptEvents
        try await provider.start()

        await provider.enqueue(.interim(text: "Mer"))
        await provider.enqueue(.interim(text: "Merhaba"))
        await provider.enqueue(.final(text: "Merhaba dünya"))

        // Sendable closure — actor stream'i alır, sync olarak iterate eder
        let collector: Task<[TranscriptEvent], Never> = Task {
            var received: [TranscriptEvent] = []
            for await event in stream {
                received.append(event)
                if received.count >= 3 { break }
            }
            return received
        }
        // Allow yields to flush
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        await provider.finishStream()
        let receivedEvents = await collector.value

        XCTAssertEqual(receivedEvents.count, 3)
        XCTAssertEqual(receivedEvents[0], .interim(text: "Mer"))
        XCTAssertEqual(receivedEvents[2].isFinal, true)
    }

    func testCancelSpeechNoOp() async {
        let provider = MockVoiceProvider()
        await provider.cancelSpeech()
        // Mock'ta no-op, sadece crash etmediğini doğrula
        XCTAssertTrue(true)
    }
}
