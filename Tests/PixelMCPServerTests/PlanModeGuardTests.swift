import XCTest

@testable import PixelMCPServer

/// `BuiltInTools.planModeGuard` — `PIXEL_PLAN_MODE` env var'a göre destructive
/// tool'ları (ui_click/ui_type) bloklar. ADR-0017 (Plan Mode) + ADR-0026
/// (Computer Use Faz 2).
final class PlanModeGuardTests: XCTestCase {

    override func setUp() {
        super.setUp()
        unsetenv("PIXEL_PLAN_MODE")
    }

    override func tearDown() {
        unsetenv("PIXEL_PLAN_MODE")
        super.tearDown()
    }

    func testGuardReturnsNilWhenEnvUnset() {
        let result = BuiltInTools.planModeGuard("ui_click")
        XCTAssertNil(result, "Env set değilken guard pas geçmeli")
    }

    func testGuardReturnsErrorWhenEnvIsOne() {
        setenv("PIXEL_PLAN_MODE", "1", 1)
        let result = BuiltInTools.planModeGuard("ui_click")
        XCTAssertNotNil(result, "PIXEL_PLAN_MODE=1 iken guard hata döndürmeli")
        guard let result else { return }

        // MCP error shape: { content: [{ type: text, text: ... }], isError: true }
        XCTAssertEqual(result["isError"]?.boolValue, true)
        if let content = result["content"]?.arrayValue,
           case .object(let block) = content.first,
           case .string(let text) = block["text"] {
            XCTAssertTrue(text.contains("ui_click"), "Hata mesaj\u{131} tool ad\u{131}n\u{131} i\u{e7}ermeli")
            XCTAssertTrue(text.contains("Plan modunda"), "Hata mesaj\u{131} Plan modu kelimesini i\u{e7}ermeli")
        } else {
            XCTFail("Beklenmedik error shape: \(result)")
        }
    }

    func testGuardReturnsNilWhenEnvIsZero() {
        setenv("PIXEL_PLAN_MODE", "0", 1)
        let result = BuiltInTools.planModeGuard("ui_click")
        XCTAssertNil(result, "PIXEL_PLAN_MODE=0 guard'\u{131} tetiklememeli — sadece '1' aktif eder")
    }

    func testGuardReturnsNilWhenEnvIsTrue() {
        // Sadece exact "1" kabul edilir — "true", "yes" vb. değil
        setenv("PIXEL_PLAN_MODE", "true", 1)
        let result = BuiltInTools.planModeGuard("ui_click")
        XCTAssertNil(result, "Sadece '1' aktif etmeli — 'true' string'i hayır")
    }

    func testGuardErrorMentionsAllowedReadOnlyTools() {
        setenv("PIXEL_PLAN_MODE", "1", 1)
        guard let result = BuiltInTools.planModeGuard("ui_type") else {
            XCTFail("Guard hata d\u{f6}ndürmedi")
            return
        }
        if let content = result["content"]?.arrayValue,
           case .object(let block) = content.first,
           case .string(let text) = block["text"] {
            XCTAssertTrue(text.contains("ui_query"))
            XCTAssertTrue(text.contains("ui_screenshot"))
        }
    }
}
