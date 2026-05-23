import XCTest
import CoreGraphics

@testable import PixelComputerUse

/// **Faz 3c (ADR-0030):** `WindowCrop` saf fonksiyonları — ScreenCaptureKit
/// bağımsız, retina scale matematiği ve logical frame hesabı.
final class WindowCropTests: XCTestCase {

    // MARK: - computeCropRect

    func testCropRect1xRetinaTitlebar28pt() {
        // 800×600 logical (1x display) → 800×600 pixel; 28pt titlebar atılır.
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 28
        )
        XCTAssertEqual(rect?.origin.x, 0)
        XCTAssertEqual(rect?.origin.y, 28)
        XCTAssertEqual(rect?.size.width, 800)
        XCTAssertEqual(rect?.size.height, 572)
    }

    func testCropRect2xRetinaTitlebar28pt() {
        // 800×600 logical → 1600×1200 pixel (2x retina); 28pt = 56px atılır.
        let rect = WindowCrop.computeCropRect(
            imageWidth: 1600,
            imageHeight: 1200,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 28
        )
        XCTAssertEqual(rect?.origin.y, 56)
        XCTAssertEqual(rect?.size.height, 1144)
        XCTAssertEqual(rect?.size.width, 1600)
    }

    func testCropRect3xRetinaTitlebar28pt() {
        // 3x display — pratikte yok ama matematik test.
        let rect = WindowCrop.computeCropRect(
            imageWidth: 2400,
            imageHeight: 1800,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 28
        )
        XCTAssertEqual(rect?.origin.y, 84)
        XCTAssertEqual(rect?.size.height, 1716)
    }

    func testCropRectToolbarPlusTitlebar72pt() {
        // 800×600 1x, 72pt offset (titlebar + toolbar) atılır.
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 72
        )
        XCTAssertEqual(rect?.origin.y, 72)
        XCTAssertEqual(rect?.size.height, 528)
    }

    func testCropRectZeroOffsetCoversEntireImage() {
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 0
        )
        XCTAssertEqual(rect?.origin.y, 0)
        XCTAssertEqual(rect?.size.height, 600)
    }

    func testCropRectOffsetEqualToWindowHeightReturnsNil() {
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 600
        )
        XCTAssertNil(rect)
    }

    func testCropRectOffsetGreaterThanWindowReturnsNil() {
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: 700
        )
        XCTAssertNil(rect)
    }

    func testCropRectNegativeOffsetReturnsNil() {
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 600,
            titlebarOffsetPoints: -5
        )
        XCTAssertNil(rect)
    }

    func testCropRectZeroWindowHeightReturnsNil() {
        let rect = WindowCrop.computeCropRect(
            imageWidth: 800,
            imageHeight: 600,
            windowWidth: 800,
            windowHeight: 0,
            titlebarOffsetPoints: 28
        )
        XCTAssertNil(rect)
    }

    // MARK: - computeLogicalFrame

    func testLogicalFrameShiftsOriginAndShrinksHeight() {
        let frame = WindowCrop.computeLogicalFrame(
            windowFrame: CGRect(x: 100, y: 200, width: 800, height: 600),
            titlebarOffsetPoints: 28
        )
        XCTAssertEqual(frame.origin.x, 100)
        XCTAssertEqual(frame.origin.y, 228)  // 200 + 28
        XCTAssertEqual(frame.size.width, 800)
        XCTAssertEqual(frame.size.height, 572)  // 600 - 28
    }

    func testLogicalFrameClampsOffsetToWindowHeight() {
        // Offset > height → clamp to height (height becomes 0).
        let frame = WindowCrop.computeLogicalFrame(
            windowFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            titlebarOffsetPoints: 800
        )
        XCTAssertEqual(frame.size.height, 0)
        XCTAssertEqual(frame.origin.y, 600)  // clamp to height
    }

    func testLogicalFrameZeroOffsetUnchanged() {
        let original = CGRect(x: 50, y: 50, width: 400, height: 300)
        let frame = WindowCrop.computeLogicalFrame(
            windowFrame: original,
            titlebarOffsetPoints: 0
        )
        XCTAssertEqual(frame, original)
    }

    func testLogicalFrameNegativeOffsetClampedToZero() {
        let original = CGRect(x: 0, y: 100, width: 800, height: 600)
        let frame = WindowCrop.computeLogicalFrame(
            windowFrame: original,
            titlebarOffsetPoints: -10
        )
        XCTAssertEqual(frame, original)  // negatif → 0 → unchanged
    }
}
