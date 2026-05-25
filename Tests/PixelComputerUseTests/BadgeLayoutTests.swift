import XCTest

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@testable import PixelComputerUse

final class BadgeLayoutTests: XCTestCase {

    private let imageSize = CGSize(width: 1000, height: 800)

    // MARK: - Basic placement math

    func testTopLeftInsideOriginAtElementTopLeft() {
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 100, y: 200, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topLeftInside
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 200, width: 36, height: 36))
    }

    func testTopLeftOutsideOriginShiftedByHalfBadgeSize() {
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 100, y: 200, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topLeftOutside
        )
        // -18 shift on x + y (badge merkezi rect köşesinde)
        XCTAssertEqual(rect, CGRect(x: 82, y: 182, width: 36, height: 36))
    }

    func testTopRightInsideOriginAtElementMaxXMinusBadgeSize() {
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 100, y: 200, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topRightInside
        )
        XCTAssertEqual(rect, CGRect(x: 144, y: 200, width: 36, height: 36))
    }

    func testTopRightOutsideOriginAtMaxXMinusHalf() {
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 100, y: 200, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topRightOutside
        )
        XCTAssertEqual(rect, CGRect(x: 162, y: 182, width: 36, height: 36))
    }

    // MARK: - Clamping

    func testTopLeftOutsideAtImageOriginClampedInside() {
        // Element image origin'inde (0,0) — topLeftOutside negatif olur, clamp'lenir.
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 0, y: 0, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topLeftOutside
        )
        XCTAssertEqual(rect?.minX, 0)
        XCTAssertEqual(rect?.minY, 0)
    }

    func testBadgePushedInsideWhenBeyondMaxBounds() {
        // Element image sağ-alt köşesinde — topRightInside badge taşar, clamp'lenir.
        let rect = BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 950, y: 750, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize,
            placement: .topRightInside
        )
        // imageSize.width=1000, badge size=36 → maxX olur 964
        XCTAssertNotNil(rect)
        if let rect {
            XCTAssertLessThanOrEqual(rect.maxX, imageSize.width)
            XCTAssertLessThanOrEqual(rect.maxY, imageSize.height)
        }
    }

    // MARK: - Smart corner strategy

    func testSmartCornerPrefersOutsideWhenBoundsAllow() {
        // Element rahat orta yerde — smartCorner topLeftOutside seçer.
        let strategy = BadgeLayout.resolveStrategy(
            placement: .smartCorner,
            elementRect: CGRect(x: 200, y: 200, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize
        )
        XCTAssertEqual(strategy, .topLeftOutside)
    }

    func testSmartCornerFallsBackToInsideAtImageOrigin() {
        // Element (0,0)'da — outside taşar; inside fallback.
        let strategy = BadgeLayout.resolveStrategy(
            placement: .smartCorner,
            elementRect: CGRect(x: 0, y: 0, width: 80, height: 40),
            badgeSize: 36,
            imagePixelSize: imageSize
        )
        XCTAssertEqual(strategy, .topLeftInside)
    }

    func testSmartCornerNonSmartPassesThrough() {
        // Diğer strategy'ler smartCorner değil → değiştirilmez.
        for placement: BadgePlacement in [.topLeftInside, .topRightInside, .topLeftOutside, .topRightOutside] {
            let result = BadgeLayout.resolveStrategy(
                placement: placement,
                elementRect: CGRect(x: 200, y: 200, width: 80, height: 40),
                badgeSize: 36,
                imagePixelSize: imageSize
            )
            XCTAssertEqual(result, placement)
        }
    }

    // MARK: - Defensive edge cases

    func testZeroImageSizeReturnsNil() {
        XCTAssertNil(BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            badgeSize: 36,
            imagePixelSize: .zero,
            placement: .topLeftInside
        ))
    }

    func testZeroBadgeSizeReturnsNil() {
        XCTAssertNil(BadgeLayout.computeBadgeRect(
            elementRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            badgeSize: 0,
            imagePixelSize: imageSize,
            placement: .topLeftInside
        ))
    }
}
