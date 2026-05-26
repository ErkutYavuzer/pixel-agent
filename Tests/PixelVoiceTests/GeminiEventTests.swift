import XCTest
@testable import PixelVoice

/// **Sprint 45 (v0.2.72):** Gemini Live BidiGenerateContent event tests.
final class GeminiEventTests: XCTestCase {

    // MARK: - Setup encode

    func testSetupEncodesModelField() throws {
        let config = GeminiSetupConfig()
        let event = GeminiClientEvent.setup(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(json["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-2.0-flash-exp")
    }

    func testSetupEncodesGenerationConfigAudioModality() throws {
        let config = GeminiSetupConfig()
        let event = GeminiClientEvent.setup(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(json["setup"] as? [String: Any])
        let gen = try XCTUnwrap(setup["generation_config"] as? [String: Any])
        let modalities = try XCTUnwrap(gen["response_modalities"] as? [String])
        XCTAssertEqual(modalities, ["AUDIO"])
    }

    func testSetupEncodesSystemInstruction() throws {
        let config = GeminiSetupConfig(systemInstruction: .init(text: "Test instruction"))
        let event = GeminiClientEvent.setup(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(json["setup"] as? [String: Any])
        let sysInst = try XCTUnwrap(setup["system_instruction"] as? [String: Any])
        let parts = try XCTUnwrap(sysInst["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "Test instruction")
    }

    func testSetupEncodesToolsWhenProvided() throws {
        let decl = GeminiFunctionDeclaration(
            name: "get_time",
            description: "Get current time",
            parameters: AnyEncodable(["type": "object"])
        )
        let tools = GeminiTools(functionDeclarations: [decl])
        let config = GeminiSetupConfig(tools: [tools])
        let event = GeminiClientEvent.setup(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(json["setup"] as? [String: Any])
        let toolsArray = try XCTUnwrap(setup["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(toolsArray.first?["function_declarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.first?["name"] as? String, "get_time")
    }

    func testSetupOmitsToolsWhenNil() throws {
        let config = GeminiSetupConfig(tools: nil)
        let event = GeminiClientEvent.setup(config: config)
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let setup = try XCTUnwrap(json["setup"] as? [String: Any])
        XCTAssertNil(setup["tools"])
    }

    // MARK: - Realtime input encode

    func testRealtimeInputEncodesAs16kHzPCM() throws {
        let event = GeminiClientEvent.realtimeInput(audioBase64: "AAAB")
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rt = try XCTUnwrap(json["realtime_input"] as? [String: Any])
        let chunks = try XCTUnwrap(rt["media_chunks"] as? [[String: Any]])
        let chunk = try XCTUnwrap(chunks.first)
        XCTAssertEqual(chunk["mime_type"] as? String, "audio/pcm;rate=16000")
        XCTAssertEqual(chunk["data"] as? String, "AAAB")
    }

    // MARK: - Tool response encode

    func testToolResponseEncode() throws {
        let response = GeminiFunctionResponse(
            id: "call_xyz",
            name: "get_time",
            response: AnyEncodable(["result": "18:30"])
        )
        let event = GeminiClientEvent.toolResponse(functionResponses: [response])
        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tr = try XCTUnwrap(json["tool_response"] as? [String: Any])
        let frs = try XCTUnwrap(tr["function_responses"] as? [[String: Any]])
        XCTAssertEqual(frs.first?["id"] as? String, "call_xyz")
        XCTAssertEqual(frs.first?["name"] as? String, "get_time")
    }

    // MARK: - Server decode

    func testDecodeSetupComplete() {
        let json = #"{"setupComplete":{}}"#
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .setupComplete)
    }

    func testDecodeAudioChunkPart() {
        let json = """
        {"serverContent":{"modelTurn":{"parts":[{"inlineData":{"mimeType":"audio/pcm","data":"AAAB"}}]}}}
        """
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .audioChunk(base64: "AAAB"))
    }

    func testDecodeTextChunkWhenNoAudio() {
        let json = """
        {"serverContent":{"modelTurn":{"parts":[{"text":"Merhaba"}]}}}
        """
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .textChunk(text: "Merhaba"))
    }

    func testDecodeAudioOverTextPriority() {
        // Hem audio hem text varsa audio öncelik
        let json = """
        {"serverContent":{"modelTurn":{"parts":[{"text":"hi"},{"inlineData":{"mimeType":"audio/pcm","data":"AAAB"}}]}}}
        """
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .audioChunk(base64: "AAAB"))
    }

    func testDecodeInterrupted() {
        let json = #"{"serverContent":{"interrupted":true}}"#
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .interrupted)
    }

    func testDecodeTurnComplete() {
        let json = #"{"serverContent":{"turnComplete":true}}"#
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .turnComplete)
    }

    func testDecodeToolCall() {
        let json = """
        {"toolCall":{"functionCalls":[{"id":"call_1","name":"get_time","args":{}}]}}
        """
        let event = GeminiServerEvent.decode(Data(json.utf8))
        switch event {
        case .toolCall(let calls):
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].id, "call_1")
            XCTAssertEqual(calls[0].name, "get_time")
        default:
            XCTFail("Expected .toolCall, got \(String(describing: event))")
        }
    }

    func testDecodeError() {
        let json = #"{"error":{"message":"Invalid API key","code":403}}"#
        let event = GeminiServerEvent.decode(Data(json.utf8))
        XCTAssertEqual(event, .error(message: "Invalid API key"))
    }

    func testDecodeCorruptJSONReturnsNil() {
        let event = GeminiServerEvent.decode(Data("not json".utf8))
        XCTAssertNil(event)
    }

    func testDecodeUnknownTypeReturnsUnknownCase() {
        let json = #"{"someFutureField":{"data":"x"}}"#
        let event = GeminiServerEvent.decode(Data(json.utf8))
        if case .unknown = event { return }
        XCTFail("Expected .unknown")
    }

    // MARK: - GeminiToolCallRequest argsJSON

    func testToolCallRequestArgsJSONFromDict() {
        let request = GeminiToolCallRequest(id: "1", name: "x", args: ["key": "value"])
        let parsed = try? JSONSerialization.jsonObject(with: request.argsJSON) as? [String: String]
        XCTAssertEqual(parsed?["key"], "value")
    }

    func testToolCallRequestEquatable() {
        let a = GeminiToolCallRequest(id: "1", name: "x", args: ["k": "v"])
        let b = GeminiToolCallRequest(id: "1", name: "x", args: ["k": "v"])
        XCTAssertEqual(a, b)
        let c = GeminiToolCallRequest(id: "2", name: "x", args: ["k": "v"])
        XCTAssertNotEqual(a, c)
    }
}
