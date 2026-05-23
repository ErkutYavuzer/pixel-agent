import XCTest

@testable import PixelComputerUse

final class UITypesTests: XCTestCase {

    // MARK: - UIQuery roundtrip

    func testUIQueryRoundtrip_emptyQuery() throws {
        let original = UIQuery()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIQuery.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUIQueryRoundtrip_fullQuery() throws {
        let original = UIQuery(
            bundleID: "com.apple.Safari",
            role: .button,
            title: "Done",
            label: "Done button",
            identifier: "doneButton",
            matchMode: .fuzzy,
            maxDepth: 8,
            timeout: 5.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIQuery.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testUIQueryDebugSummary_emptyShowsBoş() {
        XCTAssertEqual(UIQuery().debugSummary, "(boş)")
    }

    func testUIQueryDebugSummary_includesSetFields() {
        let q = UIQuery(
            bundleID: "com.apple.Safari",
            role: .button,
            title: "Done"
        )
        let summary = q.debugSummary
        XCTAssertTrue(summary.contains("bundle=com.apple.Safari"))
        XCTAssertTrue(summary.contains("role=AXButton"))
        XCTAssertTrue(summary.contains("title=\"Done\""))
    }

    // MARK: - AXRole

    func testAXRole_rawValuesMatchAXConstants() {
        XCTAssertEqual(AXRole.button.rawValue, "AXButton")
        XCTAssertEqual(AXRole.textField.rawValue, "AXTextField")
        XCTAssertEqual(AXRole.any.rawValue, "*")
    }

    func testAXRole_allCases() {
        XCTAssertGreaterThanOrEqual(AXRole.allCases.count, 18)
    }

    // MARK: - CGRectBox

    func testCGRectBox_centerCalculation() {
        let box = CGRectBox(x: 100, y: 200, width: 50, height: 40)
        XCTAssertEqual(box.center.x, 125)
        XCTAssertEqual(box.center.y, 220)
    }

    func testCGRectBox_cgRectRoundtrip() {
        let original = CGRect(x: 10.5, y: 20.5, width: 30.0, height: 40.0)
        let box = CGRectBox(original)
        XCTAssertEqual(box.cgRect, original)
    }

    func testCGRectBox_zero() {
        XCTAssertEqual(CGRectBox.zero.x, 0)
        XCTAssertEqual(CGRectBox.zero.width, 0)
        XCTAssertEqual(CGRectBox.zero.center.x, 0)
    }

    // MARK: - UIElement roundtrip

    func testUIElementRoundtrip() throws {
        let original = UIElement(
            role: "AXButton",
            title: "Sign In",
            label: "Sign In button",
            identifier: "signInBtn",
            frame: CGRectBox(x: 100, y: 200, width: 80, height: 30),
            bundleID: "com.example.App",
            path: ["AXApplication", "AXWindow", "AXButton"],
            opaqueID: "AXApplication/AXWindow/signInBtn"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIElement.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - ScreenshotTarget

    func testScreenshotTargetRoundtrip_window() throws {
        let original = ScreenshotTarget.window(bundleID: "com.apple.Safari")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenshotTarget.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScreenshotTargetRoundtrip_activeDisplay() throws {
        let original = ScreenshotTarget.activeDisplay
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenshotTarget.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
