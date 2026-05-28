import XCTest

import PixelMascot
@testable import PixelMacApp

final class VoiceMascotResolverTests: XCTestCase {

    // MARK: - Listening fazı

    func testCaptureStartedListens() {
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .captureStarted), .listening)
    }

    func testInterimListens() {
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .transcriptInterim), .listening)
    }

    func testInterruptedListens() {
        // İnterrupt feedback: kullanıcı agent'ı keserse mascot dinlemeye döner.
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .interrupted), .listening)
    }

    // MARK: - Handoff

    func testFinalLeavesMascotUntouched() {
        // .final → nil: ChatViewModel.send() .thinking sahipliğini devralır.
        XCTAssertNil(VoiceMascotResolver.mascotState(for: .transcriptFinal))
    }

    // MARK: - Nötr

    func testStoppedIsIdle() {
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .captureStopped), .idle)
    }

    func testFailedIsIdle() {
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .failed), .idle)
    }

    // MARK: - Demo akışı (regression guard)

    func testTypicalVoiceTurnSequence() {
        // tap mic → konuş → bitir: listening, listening, (handoff) nil.
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .captureStarted), .listening)
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .transcriptInterim), .listening)
        XCTAssertNil(VoiceMascotResolver.mascotState(for: .transcriptFinal))
        // mic kapat → idle
        XCTAssertEqual(VoiceMascotResolver.mascotState(for: .captureStopped), .idle)
    }
}
