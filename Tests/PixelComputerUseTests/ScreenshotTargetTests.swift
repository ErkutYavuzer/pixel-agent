import XCTest

@testable import PixelComputerUse

/// **Faz 3c (ADR-0030):** `ScreenshotTarget` Codable round-trip — yeni
/// `.windowContent` case'inin auto-derived encoding'inin diğer case'leri
/// bozmadığını doğrular.
final class ScreenshotTargetTests: XCTestCase {

    private func roundTrip(_ target: ScreenshotTarget) throws -> ScreenshotTarget {
        let data = try JSONEncoder().encode(target)
        return try JSONDecoder().decode(ScreenshotTarget.self, from: data)
    }

    func testAllDisplaysRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.allDisplays), .allDisplays)
    }

    func testActiveDisplayRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.activeDisplay), .activeDisplay)
    }

    func testWindowRoundTrip() throws {
        let original: ScreenshotTarget = .window(bundleID: "com.apple.Safari")
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testWindowContentRoundTrip() throws {
        let original: ScreenshotTarget = .windowContent(
            bundleID: "com.apple.Safari",
            titlebarOffset: 28
        )
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testWindowContentWithCustomOffset() throws {
        let original: ScreenshotTarget = .windowContent(
            bundleID: "com.apple.finder",
            titlebarOffset: 72.5
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        if case .windowContent(_, let offset) = decoded {
            XCTAssertEqual(offset, 72.5)
        } else {
            XCTFail("Expected .windowContent, got \(decoded)")
        }
    }

    func testDefaultTitlebarOffsetIs28() {
        XCTAssertEqual(ScreenshotTarget.defaultTitlebarOffset, 28)
    }

    func testWindowAndWindowContentAreDistinct() throws {
        let plain: ScreenshotTarget = .window(bundleID: "x")
        let content: ScreenshotTarget = .windowContent(bundleID: "x", titlebarOffset: 28)
        XCTAssertNotEqual(plain, content)
    }
}
