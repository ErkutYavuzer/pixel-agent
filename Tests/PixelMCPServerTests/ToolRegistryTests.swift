import XCTest
@testable import PixelMCPServer

final class ToolRegistryTests: XCTestCase {
    func testRegisterAndFind() {
        let registry = ToolRegistry()
        let tool = ToolDefinition(
            name: "noop",
            description: "boş",
            inputSchema: .object([:]),
            handler: { _ in ToolResultBuilder.text("ok") }
        )
        registry.register(tool)
        XCTAssertNotNil(registry.find("noop"))
        XCTAssertNil(registry.find("ghost"))
    }

    func testListResultShape() {
        let registry = BuiltInTools.makeRegistry()
        let result = registry.listResult()
        let tools = result["tools"]?.arrayValue ?? []
        // Sprint 36: +2 memory tool. Sprint 51: +4 skill. Sprint 52: +2 macro.
        XCTAssertEqual(tools.count, 22)  // 5 saf-data + 4 bridge + 5 ui_* + 2 memory + 4 skill + 2 macro
        // alfabetik sıra
        let names = tools.compactMap { $0["name"]?.stringValue }
        XCTAssertEqual(names, names.sorted())
    }

    func testBuiltInRegistryHasExpectedTools() {
        let registry = BuiltInTools.makeRegistry()
        let expected = Set([
            "get_clipboard",
            "set_clipboard",
            "get_current_time",
            "get_active_app",
            "get_lan_ip",
            "dock_badge_set",
            "notify",
            "play_sound",
            "dispatch_subagent",
            "ui_query",
            "ui_click",
            "ui_type",
            "ui_screenshot",
            "ui_resolve",
            // Sprint 36 (v0.2.63) — cross-session memory tools.
            "save_memory",
            "search_memory",
            // Sprint 51 (v0.2.80) — skill tools.
            "create_skill",
            "update_skill",
            "list_skills",
            "apply_skill",
            // Sprint 52 (v0.2.81) — macro tools.
            "list_macros",
            "replay_macro",
        ])
        let actual = Set(registry.all().map { $0.name })
        XCTAssertEqual(actual, expected)
    }

    func testGetCurrentTimeReturnsISO8601() async {
        let result = await BuiltInTools.getCurrentTime.handler(nil)
        let text = result["content"]?.arrayValue?[0]["text"]?.stringValue ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(result["isError"]?.boolValue, false)
        // ISO 8601 ipucu: dört rakam yıl + tire
        XCTAssertTrue(text.contains("-"))
        XCTAssertTrue(text.contains("T"))
    }

    func testToolResultBuilderText() {
        let r = ToolResultBuilder.text("merhaba")
        XCTAssertEqual(r["content"]?.arrayValue?[0]["type"]?.stringValue, "text")
        XCTAssertEqual(r["content"]?.arrayValue?[0]["text"]?.stringValue, "merhaba")
        XCTAssertEqual(r["isError"]?.boolValue, false)
    }

    func testToolResultBuilderError() {
        let r = ToolResultBuilder.error("hata")
        XCTAssertEqual(r["isError"]?.boolValue, true)
        XCTAssertEqual(r["content"]?.arrayValue?[0]["text"]?.stringValue, "hata")
    }

    func testSetClipboardMissingTextReturnsError() async {
        let result = await BuiltInTools.setClipboard.handler(.object([:]))
        XCTAssertEqual(result["isError"]?.boolValue, true)
    }

    func testGetLANIPDoesNotCrash() async {
        // Sonuç ortam bağımlı; sadece çıktının yapısı + isError bool olduğu doğrulanır.
        let result = await BuiltInTools.getLANIP.handler(nil)
        XCTAssertNotNil(result["isError"]?.boolValue)
        XCTAssertNotNil(result["content"]?.arrayValue)
    }
}
