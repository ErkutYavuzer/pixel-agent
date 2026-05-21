import XCTest

@testable import PixelBackends
@testable import PixelCore

final class CodexJSONParserTests: XCTestCase {
    func testItemCompletedAgentMessageProducesTextChunk() {
        let line = #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"OK"}}"#
        XCTAssertEqual(CodexJSONParser.parse(line), .textChunk("OK"))
    }

    func testTurkishCharsPreserved() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"agent_message","text":"çığ üşür"}}"#
        XCTAssertEqual(CodexJSONParser.parse(line), .textChunk("çığ üşür"))
    }

    func testTurnCompletedProducesDone() {
        let line = #"{"type":"turn.completed","usage":{"input_tokens":10}}"#
        XCTAssertEqual(CodexJSONParser.parse(line), .done)
    }

    func testThreadStartedIsIgnored() {
        let line = #"{"type":"thread.started","thread_id":"abc"}"#
        XCTAssertNil(CodexJSONParser.parse(line))
    }

    func testTurnStartedIsIgnored() {
        let line = #"{"type":"turn.started"}"#
        XCTAssertNil(CodexJSONParser.parse(line))
    }

    func testNonAgentMessageItemIsIgnored() {
        let line = #"{"type":"item.completed","item":{"id":"i","type":"tool_call","name":"Bash"}}"#
        XCTAssertNil(CodexJSONParser.parse(line))
    }

    func testEmptyTextIsIgnored() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":""}}"#
        XCTAssertNil(CodexJSONParser.parse(line))
    }

    func testEmptyLineReturnsNil() {
        XCTAssertNil(CodexJSONParser.parse(""))
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(CodexJSONParser.parse("not-json"))
    }

    func testOutputModeForCodex() {
        XCTAssertEqual(CLIBackend.outputMode(for: .codex), .codexJSON)
        XCTAssertEqual(CLIBackend.outputMode(for: .claude), .streamJSON)
        XCTAssertEqual(CLIBackend.outputMode(for: .gemini), .text)
    }

    func testUsesStdinForPromptOnlyForCodex() {
        XCTAssertTrue(CLIBackend.usesStdinForPrompt(for: .codex))
        XCTAssertFalse(CLIBackend.usesStdinForPrompt(for: .claude))
        XCTAssertFalse(CLIBackend.usesStdinForPrompt(for: .gemini))
    }
}
