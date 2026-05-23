import XCTest

@testable import PixelComputerUse

/// **Faz 3a:** UIQuery'in yeni `containsText` ve `within` alanları için
/// AX-bağımsız unit testleri.
///
/// `AXBridge.matches(_:query:)` saf fonksiyon — `containsText` mantığı
/// doğrudan test edilebilir. `within` ancestor walk AXBridge actor içinde
/// gerçekleşir (canlı AX gerekir) — bu test'lerde sadece pure match yüzeyi
/// kapsanır; AX-tree traversal entegrasyon testi gerçek macOS app gerektirir.
final class ChainedQueryTests: XCTestCase {

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

    // MARK: - containsText (title OR label substring, case-insensitive)

    func testContainsTextMatchesTitle() {
        let element = makeElement(title: "Sign In Button", label: nil)
        let query = UIQuery(containsText: "sign in")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testContainsTextMatchesLabel() {
        let element = makeElement(title: nil, label: "Privacy settings")
        let query = UIQuery(containsText: "settings")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testContainsTextCaseInsensitive() {
        let element = makeElement(title: "SAVE")
        let query = UIQuery(containsText: "save")
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testContainsTextNoMatchWhenAbsentInBoth() {
        let element = makeElement(title: "Open", label: "Open File")
        let query = UIQuery(containsText: "close")
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    func testContainsTextWorksWithNilTitleAndLabel() {
        let element = makeElement(title: nil, label: nil)
        let query = UIQuery(containsText: "anything")
        XCTAssertFalse(AXBridge.matches(element, query: query))
    }

    func testContainsTextCombinesWithRoleConstraint() {
        let element = makeElement(role: "AXButton", title: "Save Document")
        XCTAssertTrue(AXBridge.matches(
            element,
            query: UIQuery(role: .button, containsText: "save")
        ))
        XCTAssertFalse(AXBridge.matches(
            element,
            query: UIQuery(role: .textField, containsText: "save")
        ))
    }

    func testContainsTextNotAffectedByMatchMode() {
        // matchMode .exact olsa bile containsText her zaman case-insensitive.
        let element = makeElement(title: "Hello World")
        let query = UIQuery(containsText: "WORLD", matchMode: .exact)
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    func testIdentifierShortCircuitIgnoresContainsText() {
        let element = makeElement(title: "Wrong", identifier: "doneBtn")
        let query = UIQuery(identifier: "doneBtn", containsText: "irrelevant")
        // identifier match → diğer alanlar bypass
        XCTAssertTrue(AXBridge.matches(element, query: query))
    }

    // MARK: - UIQuery Codable backward compat (within / containsText optional)

    func testUIQueryDecodesWithoutWithinOrContainsText() throws {
        // v0.2.12 ve öncesi JSON şeması — yeni alanlar yok.
        let json = #"""
        {
          "bundleID": "com.example.App",
          "role": "AXButton",
          "title": "Save",
          "matchMode": "exact",
          "maxDepth": 12,
          "timeout": 3.0
        }
        """#
        let data = json.data(using: .utf8)!
        let query = try JSONDecoder().decode(UIQuery.self, from: data)
        XCTAssertEqual(query.bundleID, "com.example.App")
        XCTAssertEqual(query.title, "Save")
        XCTAssertNil(query.containsText)
        XCTAssertTrue(query.within.isEmpty)
    }

    func testUIQueryRoundTripPreservesWithinAndContainsText() throws {
        let inner = UIQuery(role: .group, title: "Sidebar")
        let outer = UIQuery(
            role: .button,
            title: "Save",
            containsText: "save",
            within: [inner],
            matchMode: .fuzzy
        )
        let data = try JSONEncoder().encode(outer)
        let decoded = try JSONDecoder().decode(UIQuery.self, from: data)
        XCTAssertEqual(decoded.containsText, "save")
        XCTAssertEqual(decoded.within.count, 1)
        XCTAssertEqual(decoded.within[0].role, .group)
        XCTAssertEqual(decoded.within[0].title, "Sidebar")
    }

    func testUIQueryEncodeOmitsEmptyWithinArray() throws {
        // within boş array iken JSON'a yazılmamalı — geriye uyumlu output.
        let query = UIQuery(role: .button, title: "Save")
        let data = try JSONEncoder().encode(query)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("within"))
    }

    // MARK: - within debugSummary

    func testDebugSummaryIncludesWithinCount() {
        let query = UIQuery(
            role: .button,
            within: [UIQuery(role: .group, title: "Sidebar")]
        )
        XCTAssertTrue(query.debugSummary.contains("within=[1]"))
    }

    func testDebugSummaryIncludesContainsText() {
        let query = UIQuery(containsText: "save")
        XCTAssertTrue(query.debugSummary.contains("contains=\"save\""))
    }
}
