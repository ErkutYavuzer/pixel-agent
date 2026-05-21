import XCTest
@testable import PixelCore

final class PixelCoreTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelCore.version, "0.0.0")
    }
}
