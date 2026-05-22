import XCTest
@testable import PixelSubagent

final class BudgetTests: XCTestCase {
    func testDefaultValues() {
        XCTAssertEqual(Budget.default.maxDuration, 60)
        XCTAssertNil(Budget.default.maxOutputBytes)
    }

    func testExploratoryShortBudget() {
        XCTAssertEqual(Budget.exploratory.maxDuration, 10)
        XCTAssertEqual(Budget.exploratory.maxOutputBytes, 8 * 1024)
    }

    func testCustomBudget() {
        let b = Budget(maxDuration: 5, maxOutputBytes: 1024)
        XCTAssertEqual(b.maxDuration, 5)
        XCTAssertEqual(b.maxOutputBytes, 1024)
    }

    func testEquatable() {
        XCTAssertEqual(Budget(maxDuration: 30), Budget(maxDuration: 30))
        XCTAssertNotEqual(Budget(maxDuration: 30), Budget(maxDuration: 31))
    }
}
