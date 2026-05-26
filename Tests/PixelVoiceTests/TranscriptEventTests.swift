import XCTest
@testable import PixelVoice

/// **Sprint 42 (v0.2.69):** TranscriptEvent tests.
final class TranscriptEventTests: XCTestCase {

    func testInterimTextAccess() {
        let event = TranscriptEvent.interim(text: "hello")
        XCTAssertEqual(event.text, "hello")
    }

    func testFinalTextAccess() {
        let event = TranscriptEvent.final(text: "complete")
        XCTAssertEqual(event.text, "complete")
    }

    func testErrorTextNil() {
        let event = TranscriptEvent.error(message: "failed")
        XCTAssertNil(event.text)
    }

    func testIsFinalTrue() {
        XCTAssertTrue(TranscriptEvent.final(text: "x").isFinal)
    }

    func testIsFinalFalseForInterim() {
        XCTAssertFalse(TranscriptEvent.interim(text: "x").isFinal)
    }

    func testIsFinalFalseForError() {
        XCTAssertFalse(TranscriptEvent.error(message: "x").isFinal)
    }

    func testEquatable() {
        XCTAssertEqual(
            TranscriptEvent.interim(text: "a"),
            TranscriptEvent.interim(text: "a")
        )
        XCTAssertNotEqual(
            TranscriptEvent.interim(text: "a"),
            TranscriptEvent.final(text: "a")
        )
        XCTAssertNotEqual(
            TranscriptEvent.interim(text: "a"),
            TranscriptEvent.interim(text: "b")
        )
    }
}
