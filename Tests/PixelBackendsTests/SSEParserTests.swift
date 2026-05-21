import XCTest

@testable import PixelBackends
@testable import PixelCore

final class SSEParserTests: XCTestCase {
    func testParsesContentBlockDelta() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Merhaba"}}"#
        XCTAssertEqual(SSEParser.parseDataLine(line), .textChunk("Merhaba"))
    }

    func testParsesContentBlockDeltaWithUnicode() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"çığ üşür"}}"#
        XCTAssertEqual(SSEParser.parseDataLine(line), .textChunk("çığ üşür"))
    }

    func testParsesMessageStopAsDone() {
        let line = #"data: {"type":"message_stop"}"#
        XCTAssertEqual(SSEParser.parseDataLine(line), .done)
    }

    func testNonDataLineReturnsNil() {
        XCTAssertNil(SSEParser.parseDataLine("event: content_block_delta"))
        XCTAssertNil(SSEParser.parseDataLine(""))
        XCTAssertNil(SSEParser.parseDataLine(": ping"))
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(SSEParser.parseDataLine("data: not-json"))
        XCTAssertNil(SSEParser.parseDataLine(#"data: {"unclosed""#))
    }

    func testUnknownTypeReturnsNil() {
        let line = #"data: {"type":"message_start","message":{}}"#
        XCTAssertNil(SSEParser.parseDataLine(line))
    }

    func testContentBlockDeltaWithoutTextReturnsNil() {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{"}}"#
        XCTAssertNil(SSEParser.parseDataLine(line))
    }

    func testHandlesExtraWhitespaceAfterDataPrefix() {
        let line = #"data:   {"type":"message_stop"}  "#
        XCTAssertEqual(SSEParser.parseDataLine(line), .done)
    }
}
