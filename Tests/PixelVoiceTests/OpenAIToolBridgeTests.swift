import XCTest
import PixelMCPServer
@testable import PixelVoice

/// **Sprint 44 (v0.2.71):** OpenAIToolBridge tests — voice-safe whitelist
/// + conversion.
final class OpenAIToolBridgeTests: XCTestCase {

    // MARK: - voice-safe whitelist

    func testWhitelistContainsSafeTools() {
        // Sprint 44 voice-safe seti — agent voice modunda çağırabilir.
        XCTAssertTrue(OpenAIToolBridge.voiceSafeToolNames.contains("get_current_time"))
        XCTAssertTrue(OpenAIToolBridge.voiceSafeToolNames.contains("save_memory"))
        XCTAssertTrue(OpenAIToolBridge.voiceSafeToolNames.contains("search_memory"))
        XCTAssertTrue(OpenAIToolBridge.voiceSafeToolNames.contains("notify"))
    }

    func testWhitelistExcludesUITools() {
        // ui_click, ui_type voice'da risk — ekranı görmeden tıklama yanlış
        // yere gidebilir. Sprint 44'te whitelist dışı.
        XCTAssertFalse(OpenAIToolBridge.voiceSafeToolNames.contains("ui_click"))
        XCTAssertFalse(OpenAIToolBridge.voiceSafeToolNames.contains("ui_type"))
        XCTAssertFalse(OpenAIToolBridge.voiceSafeToolNames.contains("ui_screenshot"))
        XCTAssertFalse(OpenAIToolBridge.voiceSafeToolNames.contains("dispatch_subagent"))
    }

    func testWhitelistCount() {
        // Sabit set — regression koruması.
        XCTAssertEqual(OpenAIToolBridge.voiceSafeToolNames.count, 9)
    }

    // MARK: - convert

    func testConvertPreservesNameAndDescription() {
        let tool = ToolDefinition(
            name: "get_current_time",
            description: "Saati ISO 8601 formatında döner.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            handler: { _ in JSONValue.object([:]) }
        )
        let converted = OpenAIToolBridge.convert(tool)
        XCTAssertEqual(converted.name, "get_current_time")
        XCTAssertEqual(converted.description, "Saati ISO 8601 formatında döner.")
        XCTAssertEqual(converted.type, "function")
    }

    func testConvertEncodesToOpenAIFormat() throws {
        let tool = ToolDefinition(
            name: "echo",
            description: "Test",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")])
                ])
            ]),
            handler: { _ in JSONValue.object([:]) }
        )
        let converted = OpenAIToolBridge.convert(tool)
        let data = try JSONEncoder().encode(converted)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "function")
        XCTAssertEqual(json["name"] as? String, "echo")
        XCTAssertEqual(json["description"] as? String, "Test")
        XCTAssertNotNil(json["parameters"])
    }

    // MARK: - voiceTools registry filter

    func testVoiceToolsFiltersByWhitelist() {
        let registry = BuiltInTools.makeRegistry()
        let tools = OpenAIToolBridge.voiceTools(from: registry)
        let names = Set(tools.map { $0.name })
        // Voice-safe set'in subseti olmalı (registry'de hepsi varsa eşit)
        XCTAssertTrue(names.isSubset(of: OpenAIToolBridge.voiceSafeToolNames))
        // UI tools registry'de var ama whitelist dışı — filter doğru
        XCTAssertFalse(names.contains("ui_click"))
        XCTAssertFalse(names.contains("ui_screenshot"))
    }

    func testVoiceToolsIncludeAllBypassesWhitelist() {
        let registry = BuiltInTools.makeRegistry()
        let allTools = OpenAIToolBridge.voiceTools(from: registry, includeAll: true)
        let safeTools = OpenAIToolBridge.voiceTools(from: registry, includeAll: false)
        // includeAll daha geniş olmalı
        XCTAssertGreaterThanOrEqual(allTools.count, safeTools.count)
        let allNames = Set(allTools.map { $0.name })
        XCTAssertTrue(allNames.contains("ui_click"), "includeAll=true UI tools'ı da içerir")
    }
}
