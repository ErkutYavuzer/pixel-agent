import XCTest

@testable import PixelCore
@testable import PixelMacApp

final class BubbleStyleTests: XCTestCase {

    // MARK: - BubbleAlignment

    func testAlignmentUserIsTrailing() {
        XCTAssertEqual(BubbleAlignment.from(role: .user), .trailing)
    }

    func testAlignmentAssistantIsLeading() {
        XCTAssertEqual(BubbleAlignment.from(role: .assistant), .leading)
    }

    func testAlignmentSystemIsCenter() {
        XCTAssertEqual(BubbleAlignment.from(role: .system), .center)
    }

    func testLeadingSpacerOnlyForTrailingAndCenter() {
        XCTAssertFalse(BubbleAlignment.leading.leadingSpacer)
        XCTAssertTrue(BubbleAlignment.trailing.leadingSpacer)
        XCTAssertTrue(BubbleAlignment.center.leadingSpacer)
    }

    func testTrailingSpacerOnlyForLeadingAndCenter() {
        XCTAssertTrue(BubbleAlignment.leading.trailingSpacer)
        XCTAssertFalse(BubbleAlignment.trailing.trailingSpacer)
        XCTAssertTrue(BubbleAlignment.center.trailingSpacer)
    }

    // MARK: - BubbleColors (Color karşılaştırması yapamayız direkt; pattern coverage)

    func testForegroundUserIsContrastingWhite() {
        // Color karşılaştırması non-trivial; sadece "user farklı, diğerleri primary"
        // semantik teyit. User .white sabit; diğerleri primary (Color sürekli aynı
        // referans değildir, davranış kontratı önemli).
        let userFG = BubbleColors.foreground(for: .user)
        let assistantFG = BubbleColors.foreground(for: .assistant)
        let systemFG = BubbleColors.foreground(for: .system)
        // En azından user, assistant'tan farklı olmalı (semantik garanti).
        // Color Equatable Swift'te Color tipinde değişkenlik gösterir (description
        // karşılaştırma daha güvenilir).
        XCTAssertNotEqual(String(describing: userFG), String(describing: assistantFG))
        XCTAssertEqual(String(describing: assistantFG), String(describing: systemFG))
    }

    func testBackgroundUserDistinctFromAssistant() {
        let userBG = BubbleColors.background(for: .user)
        let assistantBG = BubbleColors.background(for: .assistant)
        let systemBG = BubbleColors.background(for: .system)
        // Üçü de farklı (description tabanlı zayıf karşılaştırma).
        XCTAssertNotEqual(String(describing: userBG), String(describing: assistantBG))
        XCTAssertNotEqual(String(describing: userBG), String(describing: systemBG))
        XCTAssertNotEqual(String(describing: assistantBG), String(describing: systemBG))
    }

    // MARK: - BubbleMetrics

    func testMaxWidthRatiosOrderedAssistantWidestUserNarrowest() {
        XCTAssertLessThan(BubbleMetrics.maxWidthRatio(for: .user), BubbleMetrics.maxWidthRatio(for: .assistant))
        XCTAssertLessThan(BubbleMetrics.maxWidthRatio(for: .system), BubbleMetrics.maxWidthRatio(for: .assistant))
    }

    func testMaxWidthRatiosWithinValidRange() {
        for role in [MessageRole.user, .assistant, .system] {
            let ratio = BubbleMetrics.maxWidthRatio(for: role)
            XCTAssertGreaterThan(ratio, 0)
            XCTAssertLessThanOrEqual(ratio, 1)
        }
    }

    func testMetricConstantsAreReasonable() {
        XCTAssertGreaterThan(BubbleMetrics.cornerRadius, 0)
        XCTAssertGreaterThan(BubbleMetrics.horizontalPadding, 0)
        XCTAssertGreaterThan(BubbleMetrics.verticalPadding, 0)
    }
}
