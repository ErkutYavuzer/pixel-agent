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
        // Sprint 26 (v0.2.51): .contentAware case eklendi.
        for placement: BadgePlacement in [
            .topLeftInside, .topLeftOutside, .topRightInside, .topRightOutside,
            .smartCorner, .labelAware, .contentAware
        ] {
            let data = try JSONEncoder().encode(placement)
            let decoded = try JSONDecoder().decode(BadgePlacement.self, from: data)
            XCTAssertEqual(decoded, placement)
        }
    }

    func testBadgePlacementContentAwareRawValue() {
        XCTAssertEqual(BadgePlacement.contentAware.rawValue, "contentAware")
    }

    func testSoMOptionsAcceptsContentAware() {
        let options = SoMOptions(badgePlacement: .contentAware)
        XCTAssertEqual(options.badgePlacement, .contentAware)
    }

    // MARK: - Sprint 27 (v0.2.52): OCRCropMode

    func testOCRCropModeRawValuesSnakeCase() {
        // MCP convention: enum raw value snake_case (wire docs ile tutarlı).
        XCTAssertEqual(OCRCropMode.wholeImage.rawValue, "whole_image")
        XCTAssertEqual(OCRCropMode.perElement.rawValue, "per_element")
    }

    func testOCRCropModeCodableRoundTrip() throws {
        for mode in [OCRCropMode.wholeImage, .perElement] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(OCRCropMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testSoMOptionsDefaultOCRCropMode() {
        // Default `.wholeImage` (Sprint 26 davranışı korunur — backward compat).
        let options = SoMOptions()
        XCTAssertEqual(options.ocrCropMode, .wholeImage)
    }

    func testSoMOptionsAcceptsPerElement() {
        let options = SoMOptions(badgePlacement: .contentAware, ocrCropMode: .perElement)
        XCTAssertEqual(options.ocrCropMode, .perElement)
    }

    func testSoMOptionsCodableRoundTripWithCropMode() throws {
        let original = SoMOptions(
            badgePlacement: .contentAware,
            ocrCropMode: .perElement
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SoMOptions.self, from: data)
        XCTAssertEqual(decoded.badgePlacement, .contentAware)
        XCTAssertEqual(decoded.ocrCropMode, .perElement)
    }

    func testSoMOptionsBackwardCompatDecodeWithoutCropMode() throws {
        // Sprint 26 wire format (ocr_crop_mode field yok) → default .wholeImage.
        let oldJSON = """
        {
            "palette": [],
            "outlineWidth": 4,
            "badgeSize": 36,
            "fontSize": 20,
            "textColor": {"red": 1, "green": 1, "blue": 1, "alpha": 1},
            "badgePlacement": "contentAware"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SoMOptions.self, from: oldJSON)
        XCTAssertEqual(decoded.badgePlacement, .contentAware)
        XCTAssertEqual(decoded.ocrCropMode, .wholeImage,
            "Eski JSON field eksikse default .wholeImage'a düşmeli")
    }
}
