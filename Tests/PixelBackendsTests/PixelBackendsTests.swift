import XCTest
@testable import PixelBackends

final class PixelBackendsTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelBackends.version, "0.0.0")
    }
}
