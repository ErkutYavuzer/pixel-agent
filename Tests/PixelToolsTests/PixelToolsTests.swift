import XCTest
@testable import PixelTools

final class PixelToolsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelTools.version, "0.0.0")
    }
}
