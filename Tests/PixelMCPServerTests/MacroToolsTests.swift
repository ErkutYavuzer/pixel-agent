import XCTest

@testable import PixelMCPServer

/// Hermetic: tool isimleri + `replay_macro` parametre-validasyon error path'i.
/// `list_macros` happy-path MacroStore'a (default dir) dokunduğu için burada
/// test edilmez — store davranışı `MacroStoreTests`'te kapsanır.
final class MacroToolsTests: XCTestCase {
    private func isError(_ result: JSONValue) -> Bool {
        result["isError"]?.boolValue ?? false
    }

    func testToolNamesStable() {
        XCTAssertEqual(MacroTools.listMacros.name, "list_macros")
        XCTAssertEqual(BuiltInTools.replayMacro.name, "replay_macro")
    }

    func testReplayMacroMissingIDErrors() async {
        // macro_id yok → callBridge'e gitmeden error döner (plan-guard ya da
        // eksik-param guard'ı; her iki durumda isError true).
        let r = await BuiltInTools.replayMacro.handler(.object([:]))
        XCTAssertTrue(isError(r))
    }

    func testReplayMacroRegisteredAsBridge() {
        // replay_macro registry'de mevcut + required param macro_id.
        let registry = BuiltInTools.makeRegistry()
        XCTAssertNotNil(registry.find("replay_macro"))
        XCTAssertNotNil(registry.find("list_macros"))
    }
}
