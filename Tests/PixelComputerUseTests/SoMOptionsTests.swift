import XCTest

@testable import PixelComputerUse

final class SoMOptionsTests: XCTestCase {

    // MARK: - SoMOptions defaults + clamping

    func testDefaultMatchesLegacyHardcodedValues() {
        let opts = SoMOptions.default
        XCTAssertEqual(opts.outlineWidth, 4)
        XCTAssertEqual(opts.badgeSize, 36)
        XCTAssertEqual(opts.fontSize, 20)
        XCTAssertEqual(opts.textColor, .white)
        XCTAssertEqual(opts.badgePlacement, .topLeftInside)
        XCTAssertEqual(opts.palette.count, 5)
        XCTAssertEqual(opts.palette, SoMColor.defaultPalette)
    }

    func testEmptyPaletteFallsBackToDefault() {
        let opts = SoMOptions(palette: [])
        XCTAssertEqual(opts.palette, SoMColor.defaultPalette)
    }

    func testOutlineWidthClampedToMinimum() {
        XCTAssertEqual(SoMOptions(outlineWidth: 0).outlineWidth, 0.5)
        XCTAssertEqual(SoMOptions(outlineWidth: -5).outlineWidth, 0.5)
        XCTAssertEqual(SoMOptions(outlineWidth: 10).outlineWidth, 10)
    }

    func testBadgeSizeClampedToMinimum() {
        XCTAssertEqual(SoMOptions(badgeSize: 0).badgeSize, 8)
        XCTAssertEqual(SoMOptions(badgeSize: 50).badgeSize, 50)
    }

    func testFontSizeClampedToMinimum() {
        XCTAssertEqual(SoMOptions(fontSize: 0).fontSize, 6)
        XCTAssertEqual(SoMOptions(fontSize: 24).fontSize, 24)
    }

    // MARK: - Codable round-trip (MCP wire compat)

    func testCodableRoundTripDefault() throws {
        let original = SoMOptions.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoMOptions.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripCustom() throws {
        let original = SoMOptions(
            palette: [SoMColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)],
            outlineWidth: 6,
            badgeSize: 48,
            fontSize: 24,
            textColor: .black,
            badgePlacement: .smartCorner
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoMOptions.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - SoMColor

    func testSoMColorDefaultPaletteSize() {
        XCTAssertEqual(SoMColor.defaultPalette.count, 5)
    }

    func testSoMColorCodableRoundTrip() throws {
        let original = SoMColor(red: 0.42, green: 0.13, blue: 0.99, alpha: 0.75)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoMColor.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - BadgePlacement enum

    func testBadgePlacementCodableRoundTrip() throws {
        for placement: BadgePlacement in [.topLeftInside, .topLeftOutside, .topRightInside, .topRightOutside, .smartCorner] {
            let data = try JSONEncoder().encode(placement)
            let decoded = try JSONDecoder().decode(BadgePlacement.self, from: data)
            XCTAssertEqual(decoded, placement)
        }
    }
}
