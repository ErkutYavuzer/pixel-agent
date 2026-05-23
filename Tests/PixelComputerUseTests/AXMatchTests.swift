import XCTest

@testable import PixelComputerUse

/// `AXBridge.matches(_:query:)` saf fonksiyon — AX C API ihtiyacı yok.
/// Tüm matching kuralları için exhaustive case'ler.
final class AXMatchTests: XCTestCase {

    private func makeElement(
        role: String = "AXButton",
        title: String? = nil,
        label: String? = nil,
        identifier: String? = nil
    ) -> UIElement {
        UIElement(
            role: role,
            title: title,
            label: label,
            identifier: identifier,
            frame: CGRectBox(x: 0, y: 0, width: 100, height: 30),
            bundleID: "com.example.App",
            path: ["AXApplication", role],
            opaqueID: "test/\(identifier ?? title ?? role)"
        )
    }

    // MARK: - identifier short-circuit

    func testIdentifierMatchOverridesOtherFields() {
        let element = makeElement(role: "AXButton", title: "Wrong", identifier: "doneBtn")
        let query = UIQuery(role: .textField, title: "DoesNotMatter", identifier: "doneBtn")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testIdentifierMismatchFailsEvenIfOtherFieldsMatch() {
        let element = makeElement(role: "AXButton", title: "Done", identifier: "wrongID")
        let query = UIQuery(role: .button, title: "Done", identifier: "doneBtn")
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    // MARK: - role

    func testRoleAnyMatchesEverything() {
        let element = makeElement(role: "AXTextField")
        let query = UIQuery(role: .any)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testRoleMismatchFails() {
        let element = makeElement(role: "AXButton")
        let query = UIQuery(role: .textField)
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    func testRoleNilMatchesAnyRole() {
        let element = makeElement(role: "AXLink")
        let query = UIQuery()
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    // MARK: - title

    func testTitleExactMatch() {
        let element = makeElement(title: "Sign In")
        let query = UIQuery(title: "Sign In")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testTitleExactMismatchCaseSensitive() {
        let element = makeElement(title: "Sign In")
        let query = UIQuery(title: "sign in")
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    func testTitleFuzzyMatchCaseInsensitive() {
        let element = makeElement(title: "Sign In Button")
        let query = UIQuery(title: "sign in", matchMode: .fuzzy)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testTitleFuzzyMatchPartial() {
        let element = makeElement(title: "Settings & Privacy")
        let query = UIQuery(title: "privacy", matchMode: .fuzzy)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testTitleRegexMatch() {
        let element = makeElement(title: "Item 42")
        let query = UIQuery(title: "Item \\d+", matchMode: .regex)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testTitleRegexBadPatternFails() {
        let element = makeElement(title: "Anything")
        let query = UIQuery(title: "[unterminated", matchMode: .regex)
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    func testTitleAbsentFailsMatch() {
        let element = makeElement(title: nil, label: "no title")
        let query = UIQuery(title: "Anything")
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    // MARK: - label

    func testLabelExactMatch() {
        let element = makeElement(label: "Done button")
        let query = UIQuery(label: "Done button")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testLabelFuzzyMatch() {
        let element = makeElement(label: "The button to confirm")
        let query = UIQuery(label: "confirm", matchMode: .fuzzy)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    // MARK: - composite AND

    func testRoleAndTitleAllMustMatch() {
        let element = makeElement(role: "AXButton", title: "OK")
        XCTAssertTrue(AXBridge.matches(element, query: UIQuery(role: .button, title: "OK")))
        XCTAssertFalse(AXBridge.matches(element, query: UIQuery(role: .button, title: "Cancel")))
        XCTAssertFalse(AXBridge.matches(element, query: UIQuery(role: .textField, title: "OK")))
    }

    func testEmptyQueryMatchesEverything() {
        let element = makeElement()
        XCTAssertTrue(AXBridge.matches(element, query: UIQuery()))
    }
}
