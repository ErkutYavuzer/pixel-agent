import XCTest
@testable import PixelMemory

final class PixelMemoryTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelMemory.version, "0.1.0")
    }
}
