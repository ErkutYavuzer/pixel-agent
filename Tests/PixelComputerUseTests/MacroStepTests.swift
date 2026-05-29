import XCTest

@testable import PixelComputerUse

final class MacroStepTests: XCTestCase {
    private func roundTrip(_ step: MacroStep) throws -> MacroStep {
        let data = try JSONEncoder().encode(step)
        return try JSONDecoder().decode(MacroStep.self, from: data)
    }

    func testClickWithQueryAndModifiersRoundTrip() throws {
        let step = MacroStep.click(
            query: UIQuery(role: .button, title: "Sign In"),
            opaqueID: "com.apple.Safari|AXButton:0",
            count: 2,
            modifiers: [.command, .shift]
        )
        XCTAssertEqual(try roundTrip(step), step)
    }

    func testClickOpaqueIDOnlyRoundTrip() throws {
        let step = MacroStep.click(query: nil, opaqueID: "app|AXButton:1", count: 1, modifiers: [])
        XCTAssertEqual(try roundTrip(step), step)
    }

    func testTypeRoundTrip() throws {
        let step = MacroStep.type(text: "merhaba dünya", into: UIQuery(role: .textField))
        XCTAssertEqual(try roundTrip(step), step)
    }

    func testScreenshotAndWaitRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.screenshot(target: .activeDisplay)), .screenshot(target: .activeDisplay))
        XCTAssertEqual(try roundTrip(.wait(milliseconds: 500)), .wait(milliseconds: 500))
    }

    func testSummary() {
        XCTAssertTrue(MacroStep.click(query: UIQuery(role: .button, title: "Kaydet"), opaqueID: nil, count: 1, modifiers: []).summary.contains("Kaydet"))
        XCTAssertTrue(MacroStep.click(query: nil, opaqueID: "x", count: 2, modifiers: []).summary.contains("×2"))
        XCTAssertTrue(MacroStep.type(text: "selam", into: nil).summary.contains("selam"))
        XCTAssertTrue(MacroStep.wait(milliseconds: 300).summary.contains("300"))
        XCTAssertFalse(MacroStep.screenshot(target: .activeDisplay).summary.isEmpty)
    }

    func testSummaryTruncatesLongType() {
        let long = String(repeating: "a", count: 50)
        XCTAssertTrue(MacroStep.type(text: long, into: nil).summary.contains("…"))
    }

    func testIsDestructive() {
        XCTAssertTrue(MacroStep.click(query: nil, opaqueID: "x", count: 1, modifiers: []).isDestructive)
        XCTAssertTrue(MacroStep.type(text: "a", into: nil).isDestructive)
        XCTAssertFalse(MacroStep.screenshot(target: .activeDisplay).isDestructive)
        XCTAssertFalse(MacroStep.wait(milliseconds: 1).isDestructive)
    }
}
