import XCTest
@testable import PixelRemote

final class PixelRemoteTests: XCTestCase {
    func testVersionPlaceholder() {
        XCTAssertEqual(PixelRemote.version, "0.1.0")
        XCTAssertEqual(PixelRemote.protocolVersion, 1)
    }
}
