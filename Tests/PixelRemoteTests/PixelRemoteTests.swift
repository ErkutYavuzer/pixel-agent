import XCTest
@testable import PixelRemote

final class PixelRemoteTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelRemote.version, "0.0.0")
    }
}
