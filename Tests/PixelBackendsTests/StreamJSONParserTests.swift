import XCTest

@testable import PixelBackends
@testable import PixelCore

final class StreamJSONParserTests: XCTestCase {
    func testTextDeltaProducesTextChunk() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Merhaba"}}}"#
        XCTAssertEqual(StreamJSONParser.parse(line), .textChunk("Merhaba"))
    }

    func testTurkishCharsPreserved() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"çığ üşür İnşallah"}}}"#
        XCTAssertEqual(StreamJSONParser.parse(line), .textChunk("çığ üşür İnşallah"))
    }

    func testResultEventProducesDone() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"OK"}"#
        XCTAssertEqual(StreamJSONParser.parse(line), .done)
    }

    func testMessageStartIsIgnored() {
        let line = #"{"type":"stream_event","event":{"type":"message_start","message":{"id":"x","role":"assistant"}}}"#
        XCTAssertNil(StreamJSONParser.parse(line))
    }

    func testMessageStopIsIgnoredInFavorOfResult() {
        let line = #"{"type":"stream_event","event":{"type":"message_stop"}}"#
        XCTAssertNil(StreamJSONParser.parse(line))
    }

    func testContentBlockStartIsIgnored() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
        XCTAssertNil(StreamJSONParser.parse(line))
    }

    func testSystemEventsAreIgnored() {
        XCTAssertNil(StreamJSONParser.parse(#"{"type":"system","subtype":"init","cwd":"/tmp"}"#))
        XCTAssertNil(StreamJSONParser.parse(#"{"type":"system","subtype":"status","status":"requesting"}"#))
        XCTAssertNil(StreamJSONParser.parse(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#))
    }

    func testEmptyLineReturnsNil() {
        XCTAssertNil(StreamJSONParser.parse(""))
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(StreamJSONParser.parse("not-json"))
        XCTAssertNil(StreamJSONParser.parse("{ unclosed"))
    }

    func testInputJSONDeltaIsIgnoredOnlyTextDelta() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{"}}}"#
        XCTAssertNil(StreamJSONParser.parse(line))
    }

    func testUsesStreamJSONOnlyForClaude() {
        XCTAssertTrue(CLIBackend.usesStreamJSON(for: .claude))
        XCTAssertFalse(CLIBackend.usesStreamJSON(for: .codex))
        XCTAssertFalse(CLIBackend.usesStreamJSON(for: .gemini))
    }
}
