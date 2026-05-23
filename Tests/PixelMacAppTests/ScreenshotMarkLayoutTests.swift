import XCTest
import CoreGraphics
import PixelComputerUse

@testable import PixelMacApp

final class ScreenshotMarkLayoutTests: XCTestCase {

    // MARK: - viewRect scaling

    func testViewRectScalesProportionally() {
        // 1000×500 pixel image → 500×250 view; mark at (100, 50, 200, 100)
        // → view rect (50, 25, 100, 50)
        let mark = CGRectBox(x: 100, y: 50, width: 200, height: 100)
        let result = ScreenshotMarkLayout.viewRect(
            forImageRect: mark,
            imagePixelSize: CGSize(width: 1000, height: 500),
            viewSize: CGSize(width: 500, height: 250)
        )
        XCTAssertEqual(result.minX, 50, accuracy: 0.001)
        XCTAssertEqual(result.minY, 25, accuracy: 0.001)
        XCTAssertEqual(result.width, 100, accuracy: 0.001)
        XCTAssertEqual(result.height, 50, accuracy: 0.001)
    }

    func testViewRectWithUnitScaleNoOp() {
        // Aynı boyutlu → koordinatlar aynı.
        let mark = CGRectBox(x: 12, y: 34, width: 56, height: 78)
        let result = ScreenshotMarkLayout.viewRect(
            forImageRect: mark,
            imagePixelSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(result, CGRect(x: 12, y: 34, width: 56, height: 78))
    }

    func testViewRectZeroImageSizeReturnsZero() {
        let result = ScreenshotMarkLayout.viewRect(
            forImageRect: CGRectBox(x: 10, y: 10, width: 10, height: 10),
            imagePixelSize: .zero,
            viewSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(result, .zero)
    }

    // MARK: - fittedSize

    func testFittedSizeImageWiderThanContainer() {
        // 4:3 image (2000×1500), container 16:9 (640×360) → image fitter, height küçülür.
        // imageAspect = 1.333, containerAspect = 1.778 → image daha dar → height'a sığdır.
        let result = ScreenshotMarkLayout.fittedSize(
            imagePixelSize: CGSize(width: 2000, height: 1500),
            containerSize: CGSize(width: 640, height: 360)
        )
        XCTAssertEqual(result.height, 360, accuracy: 0.001)
        XCTAssertEqual(result.width, 360 * (2000.0 / 1500.0), accuracy: 0.001)
    }

    func testFittedSizeImageWiderAspect() {
        // 16:9 image (1600×900), container 4:3 (800×600) → image daha geniş → width'a sığdır.
        // imageAspect = 1.778, containerAspect = 1.333 → image > container → width'a sığdır.
        let result = ScreenshotMarkLayout.fittedSize(
            imagePixelSize: CGSize(width: 1600, height: 900),
            containerSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(result.width, 800, accuracy: 0.001)
        XCTAssertEqual(result.height, 800 / (1600.0 / 900.0), accuracy: 0.001)
    }

    func testFittedSizeSameAspect() {
        // Aynı aspect → container'ı tam doldurur.
        let result = ScreenshotMarkLayout.fittedSize(
            imagePixelSize: CGSize(width: 1920, height: 1080),
            containerSize: CGSize(width: 960, height: 540)
        )
        XCTAssertEqual(result.width, 960, accuracy: 0.001)
        XCTAssertEqual(result.height, 540, accuracy: 0.001)
    }

    func testFittedSizeZeroImageReturnsZero() {
        let result = ScreenshotMarkLayout.fittedSize(
            imagePixelSize: .zero,
            containerSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(result, .zero)
    }

    // MARK: - End-to-end: mark in fitted view

    func testMarkInFittedViewMaintainsRelativePosition() {
        // 1000×500 image, fitted into 800-wide container with 4:3 (800×600).
        // imageAspect = 2, containerAspect = 1.333 → image daha geniş → width'a sığdır.
        // fitted size = 800 × 400.
        let imagePixelSize = CGSize(width: 1000, height: 500)
        let containerSize = CGSize(width: 800, height: 600)
        let fitted = ScreenshotMarkLayout.fittedSize(
            imagePixelSize: imagePixelSize, containerSize: containerSize
        )
        XCTAssertEqual(fitted.width, 800, accuracy: 0.001)
        XCTAssertEqual(fitted.height, 400, accuracy: 0.001)

        // Mark merkezi (500, 250) → fitted'te (400, 200) — kareye sığar.
        let mark = CGRectBox(x: 450, y: 200, width: 100, height: 100)
        let viewRect = ScreenshotMarkLayout.viewRect(
            forImageRect: mark, imagePixelSize: imagePixelSize, viewSize: fitted
        )
        XCTAssertEqual(viewRect.midX, 400, accuracy: 0.001)
        XCTAssertEqual(viewRect.midY, 200, accuracy: 0.001)
    }
}
