import XCTest
import PixelMCPServer
@testable import PixelVoice

/// **Sprint 45 (v0.2.72):** GeminiToolBridge tests — MCP → Gemini function
/// declaration conversion + voice-safe whitelist reuse.
final class GeminiToolBridgeTests: XCTestCase {

    func testConvertPreservesNameAndDescription() {
        let tool = ToolDefinition(
            name: "get_time",
            description: "Returns current time",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            handler: { _ in JSONValue.object([:]) }
        )
        let converted = GeminiToolBridge.convert(tool)
        XCTAssertEqual(converted.name, "get_time")
        XCTAssertEqual(converted.description, "Returns current time")
    }

    func testConvertEncodesGeminiFormat() throws {
        let tool = ToolDefinition(
            name: "echo",
            description: "Echo back",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")])
                ])
            ]),
            handler: { _ in JSONValue.object([:]) }
        )
        let converted = GeminiToolBridge.convert(tool)
        let data = try JSONEncoder().encode(converted)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Gemini'de "type":"function" YOK (OpenAI'den fark)
        XCTAssertNil(json["type"])
        XCTAssertEqual(json["name"] as? String, "echo")
        XCTAssertEqual(json["description"] as? String, "Echo back")
        XCTAssertNotNil(json["parameters"])
    }

    func testVoiceToolsRegistryWhitelistFilter() {
        let registry = BuiltInTools.makeRegistry()
        let tools = GeminiToolBridge.voiceTools(from: registry)
        XCTAssertEqual(tools.count, 1, "Tek `functionDeclarations` grubu döner")
        let names = Set(tools[0].functionDeclarations.map { $0.name })
        // OpenAIToolBridge whitelist'i ile aynı
        XCTAssertTrue(names.isSubset(of: OpenAIToolBridge.voiceSafeToolNames))
        XCTAssertFalse(names.contains("ui_click"))
        XCTAssertFalse(names.contains("ui_screenshot"))
    }

    func testVoiceToolsRegistryIncludeAll() {
        let registry = BuiltInTools.makeRegistry()
        let safe = GeminiToolBridge.voiceTools(from: registry, includeAll: false)
        let all = GeminiToolBridge.voiceTools(from: registry, includeAll: true)
        XCTAssertEqual(safe.count, 1)
        XCTAssertEqual(all.count, 1)
        XCTAssertGreaterThanOrEqual(
            all[0].functionDeclarations.count,
            safe[0].functionDeclarations.count
        )
        let allNames = Set(all[0].functionDeclarations.map { $0.name })
        XCTAssertTrue(allNames.contains("ui_click"), "includeAll UI tools'ı dahil")
    }

    func testEmptyRegistryReturnsEmptyArray() {
        let registry = ToolRegistry()  // boş
        let tools = GeminiToolBridge.voiceTools(from: registry)
        XCTAssertTrue(tools.isEmpty, "Boş registry → boş tools[] (setup'ta omit)")
    }

    func testToolsArrayShapeMatchesGeminiSpec() throws {
        // Gemini setup'ta tools[] her item bir functionDeclarations grubu:
        // tools: [{"functionDeclarations": [...]}, ...]
        let registry = BuiltInTools.makeRegistry()
        let tools = GeminiToolBridge.voiceTools(from: registry)
        let data = try JSONEncoder().encode(tools)
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertNotNil(array[0]["function_declarations"])
    }
}
