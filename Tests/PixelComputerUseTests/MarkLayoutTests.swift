import XCTest
import CoreGraphics

@testable import PixelComputerUse

/// **Faz 4 (ADR-0031):** `MarkLayout.computeMarkRect` saf fonksiyon —
/// retina scale + top-left convention + edge case'ler. ScreenCaptureKit ve
/// AppKit bağımsız.
final class MarkLayoutTests: XCTestCase {

    // MARK: - Element fully inside image, 1x retina

    func testElementInsideImage1x() {
        // Window (800×600) image; element (100, 50, 40, 30) → pixel rect aynı.
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 50, width: 40, height: 30),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 40, height: 30))
    }

    // MARK: - 2x retina scale

    func testElementInsideImage2xRetina() {
        // 800×600 logical → 1600×1200 pixel. Element pixel-doubled.
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 50, width: 40, height: 30),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 1600, height: 1200)
        )
        XCTAssertEqual(rect, CGRect(x: 200, y: 100, width: 80, height: 60))
    }

    // MARK: - Image not at screen origin (windowContent — titlebar shifted)

    func testElementWithImageOriginOffset() {
        // Image is window content area; image origin at screen (50, 100).
        // Element screen (90, 130, 40, 30) → relative (40, 30, 40, 30) → pixel same (1x).
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 90, y: 130, width: 40, height: 30),
            imageScreenOrigin: CGPoint(x: 50, y: 100),
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(rect, CGRect(x: 40, y: 30, width: 40, height: 30))
    }

    // MARK: - Off-screen filtering

    func testElementEntirelyLeftOfImage() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: -200, y: 100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testElementEntirelyAboveImage() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: -100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testElementEntirelyRightOfImage() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 1000, y: 100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testElementEntirelyBelowImage() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 800, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testElementPartiallyOutsideReturnsFullRect() {
        // Sol kenarda yarısı dışarı taşan element — caller (CG context) clip eder.
        // Helper rect'i olduğu gibi döner.
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: -20, y: 100, width: 100, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(rect, CGRect(x: -20, y: 100, width: 100, height: 50))
    }

    // MARK: - Degenerate inputs

    func testZeroSizeElementReturnsNil() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 100, width: 0, height: 0),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testZeroLogicalSizeReturnsNil() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 0, height: 600),
            imagePixelSize: CGSize(width: 800, height: 600)
        )
        XCTAssertNil(rect)
    }

    func testZeroPixelSizeReturnsNil() {
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 800, height: 600),
            imagePixelSize: CGSize(width: 0, height: 0)
        )
        XCTAssertNil(rect)
    }

    // MARK: - Real-world scenario: Faz 3c crop + 2x retina

    func testElementInWindowContentArea2xRetina() {
        // Window screen frame: (200, 100, 1000, 800)
        // titlebarOffset 28 → image origin (200, 128), logical (1000, 772)
        // 2x retina → pixel (2000, 1544)
        // Element at screen (300, 200, 80, 40) → in-image (100, 72, 80, 40)
        // → pixel (200, 144, 160, 80)
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 300, y: 200, width: 80, height: 40),
            imageScreenOrigin: CGPoint(x: 200, y: 128),
            imageLogicalSize: CGSize(width: 1000, height: 772),
            imagePixelSize: CGSize(width: 2000, height: 1544)
        )
        XCTAssertEqual(rect?.origin.x, 200)
        XCTAssertEqual(rect?.origin.y, 144)
        XCTAssertEqual(rect?.size.width, 160)
        XCTAssertEqual(rect?.size.height, 80)
    }

    func testNonSquareAspectRatioScale() {
        // 1000×500 logical → 2000×1500 pixel (3x vertical, 2x horizontal).
        // Anomali ama matematik test.
        let rect = MarkLayout.computeMarkRect(
            elementFrame: CGRect(x: 100, y: 100, width: 50, height: 50),
            imageScreenOrigin: .zero,
            imageLogicalSize: CGSize(width: 1000, height: 500),
            imagePixelSize: CGSize(width: 2000, height: 1500)
        )
        XCTAssertEqual(rect?.origin.x, 200)
        XCTAssertEqual(rect?.origin.y, 300)
        XCTAssertEqual(rect?.size.width, 100)
        XCTAssertEqual(rect?.size.height, 150)
    }
}
