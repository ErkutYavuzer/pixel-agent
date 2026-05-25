import Foundation
import XCTest

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@testable import PixelComputerUse

/// **Faz 5c follow-up (v0.2.52):** `ElementRegionExpander` saf math helper'ı.
/// Per-element OCR crop için region genişletme + bounds clamping.
final class ElementRegionExpanderTests: XCTestCase {

    // MARK: - Basic expansion

    func testExpandsByBadgeSizePlusPadding() {
        // 100x40 element ortada; badge=36, padding=8 → her yönde +44.
        let element = CGRect(x: 200, y: 200, width: 100, height: 40)
        let image = CGSize(width: 1000, height: 1000)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image,
            padding: 8
        )
        XCTAssertNotNil(expanded)
        // x: 200 - 44 = 156; y: 200 - 44 = 156
        // width: 100 + 2*44 = 188; height: 40 + 2*44 = 128
        XCTAssertEqual(expanded?.origin.x, 156)
        XCTAssertEqual(expanded?.origin.y, 156)
        XCTAssertEqual(expanded?.width, 188)
        XCTAssertEqual(expanded?.height, 128)
    }

    func testUsesDefaultPadding() {
        // padding=8 default.
        let element = CGRect(x: 200, y: 200, width: 100, height: 40)
        let image = CGSize(width: 1000, height: 1000)
        let expandedDefault = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image
        )
        let expandedExplicit = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image,
            padding: 8
        )
        XCTAssertEqual(expandedDefault, expandedExplicit)
    }

    // MARK: - Bounds clamping

    func testTopLeftCornerElementClampsToImage() {
        // Element (0, 0, 100, 40); badge+padding expands to negative → clamp.
        let element = CGRect(x: 0, y: 0, width: 100, height: 40)
        let image = CGSize(width: 1000, height: 1000)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image
        )
        XCTAssertNotNil(expanded)
        // x ≥ 0 (clamp), y ≥ 0 (clamp)
        XCTAssertEqual(expanded?.origin.x, 0)
        XCTAssertEqual(expanded?.origin.y, 0)
        // Sağ + alt taraflar normal expansion
        XCTAssertEqual(expanded?.maxX, min(100 + 44, 1000))
        XCTAssertEqual(expanded?.maxY, min(40 + 44, 1000))
    }

    func testBottomRightCornerElementClampsToImage() {
        // Element image kenarında; expansion sağ + alt'a taşar.
        let imageSize = CGSize(width: 1000, height: 1000)
        let element = CGRect(x: 900, y: 950, width: 100, height: 40)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: imageSize
        )
        XCTAssertNotNil(expanded)
        XCTAssertLessThanOrEqual(expanded!.maxX, 1000)
        XCTAssertLessThanOrEqual(expanded!.maxY, 1000)
    }

    func testElementCompletelyOutsideImageReturnsNil() {
        let element = CGRect(x: 2000, y: 2000, width: 100, height: 40)
        let image = CGSize(width: 1000, height: 1000)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image
        )
        XCTAssertNil(expanded, "Image dışı element için nil dönmeli")
    }

    func testZeroSizeImageReturnsNil() {
        let element = CGRect(x: 0, y: 0, width: 100, height: 40)
        let zero = CGSize(width: 0, height: 0)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: zero
        )
        XCTAssertNil(expanded)
    }

    // MARK: - Custom padding

    func testZeroPaddingShrinksToExactBadgeArea() {
        // padding=0: badge size kadar her yönde expansion.
        let element = CGRect(x: 500, y: 500, width: 100, height: 40)
        let image = CGSize(width: 1000, height: 1000)
        let expanded = ElementRegionExpander.expandedRect(
            elementRect: element,
            badgeSize: 36,
            imagePixelSize: image,
            padding: 0
        )
        XCTAssertNotNil(expanded)
        XCTAssertEqual(expanded?.width, 100 + 72)
        XCTAssertEqual(expanded?.height, 40 + 72)
    }

    func testLargePaddingExpandsMore() {
        let element = CGRect(x: 500, y: 500, width: 100, height: 40)
        let image = CGSize(width: 2000, height: 2000)
        let p0 = ElementRegionExpander.expandedRect(
            elementRect: element, badgeSize: 36, imagePixelSize: image, padding: 0
        )
        let p100 = ElementRegionExpander.expandedRect(
            elementRect: element, badgeSize: 36, imagePixelSize: image, padding: 100
        )
        XCTAssertNotNil(p0)
        XCTAssertNotNil(p100)
        XCTAssertGreaterThan(p100!.width, p0!.width)
        XCTAssertGreaterThan(p100!.height, p0!.height)
    }

    // MARK: - Default padding sabiti

    func testDefaultPaddingIsEightPixels() {
        XCTAssertEqual(ElementRegionExpander.defaultPadding, 8)
    }
}
