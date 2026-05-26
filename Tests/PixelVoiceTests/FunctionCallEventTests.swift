import XCTest
@testable import PixelVoice

/// **Sprint 44 (v0.2.71):** Function call event encode/decode tests.
final class FunctionCallEventTests: XCTestCase {

    // MARK: - Server → Client decode

    func testDecodeFunctionCallStarted() {
        let json = """
        {
          "type": "response.output_item.added",
          "item": {
            "type": "function_call",
            "call_id": "call_abc123",
            "name": "get_current_time"
          }
        }
        """
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .functionCallStarted(callID: "call_abc123", name: "get_current_time"))
    }

    func testDecodeFunctionCallStartedNonFunctionItemReturnsUnknown() {
        // Item type "message" — function_call değil
        let json = """
        {"type":"response.output_item.added","item":{"type":"message","id":"msg_1"}}
        """
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        if case .unknown = event { return }
        XCTFail("Non-function item should map to .unknown")
    }

    func testDecodeFunctionCallArgumentsDelta() {
        let json = #"{"type":"response.function_call_arguments.delta","call_id":"call_xyz","delta":"{\"text\":\"hel"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .functionCallArgumentsDelta(callID: "call_xyz", delta: "{\"text\":\"hel"))
    }

    func testDecodeFunctionCallArgumentsDone() {
        let json = #"{"type":"response.function_call_arguments.done","call_id":"call_xyz","arguments":"{\"text\":\"hello\"}"}"#
        let event = RealtimeServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(
            event,
            .functionCallArgumentsDone(callID: "call_xyz", arguments: "{\"text\":\"hello\"}")
        )
    }

    // MARK: - Client → Server encode

    func testEncodeConversationItemCreateFunctionCallOutput() throws {
        let event = RealtimeClientEvent.conversationItemCreateFunctionCallOutput(
            callID: "call_abc",
            output: "{\"result\":\"ok\"}"
        )
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(json["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "function_call_output")
        XCTAssertEqual(item["call_id"] as? String, "call_abc")
        XCTAssertEqual(item["output"] as? String, "{\"result\":\"ok\"}")
    }

    func testFunctionCallOutputItemEncodingCallIDFieldName() throws {
        // OpenAI spec: snake_case `call_id`. Encoder Codable mapping doğru
        // çalışmalı.
        let item = FunctionCallOutputItem(callID: "test_123", output: "{}")
        let data = try JSONEncoder().encode(item)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"call_id\":\"test_123\""))
        XCTAssertFalse(str.contains("\"callID\""))  // camelCase olmamalı
    }

    // MARK: - SessionConfig with tools

    func testSessionConfigWithToolsEncodesToolsArray() throws {
        let tool = OpenAITool(
            name: "test_tool",
            description: "Test",
            parameters: AnyEncodable(["type": "object"])
        )
        let config = SessionConfig(tools: [tool])
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["name"] as? String, "test_tool")
        XCTAssertEqual(tools.first?["type"] as? String, "function")
    }

    func testSessionConfigWithoutToolsOmitsToolsField() throws {
        let config = SessionConfig(tools: nil)
        let data = try JSONEncoder().encode(config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["tools"])
    }

    // MARK: - responseCancel encode

    func testResponseCancelEvent() throws {
        // Sprint 43'te eklendi ama Sprint 44'te kullanılmaya başlandı —
        // regression sayılır.
        let event = RealtimeClientEvent.responseCancel
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "response.cancel")
    }
}
