import XCTest
@testable import PixelMascot

final class PixelMascotTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelMascot.version, "0.0.0")
    }
}
