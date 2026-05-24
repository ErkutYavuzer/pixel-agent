import XCTest

@testable import PixelMacApp

final class ComposerHaloStyleTests: XCTestCase {

    // MARK: - Streaming dominates (no halo while disabled)

    func testStreamingAlwaysReturnsNoneRegardlessOfOtherFlags() {
        for planMode in [false, true] {
            for isFocused in [false, true] {
                let style = ComposerHaloStyle.resolve(
                    planMode: planMode,
                    isFocused: isFocused,
                    isStreaming: true
                )
                XCTAssertEqual(style, .none,
                    "Streaming durumunda halo gözükmemeli (planMode=\(planMode), isFocused=\(isFocused))")
            }
        }
    }

    // MARK: - Plan > focused priority

    func testPlanModeOverridesFocused() {
        let style = ComposerHaloStyle.resolve(
            planMode: true,
            isFocused: true,
            isStreaming: false
        )
        XCTAssertEqual(style, .plan)
    }

    func testPlanModeAloneShowsPlan() {
        let style = ComposerHaloStyle.resolve(
            planMode: true,
            isFocused: false,
            isStreaming: false
        )
        XCTAssertEqual(style, .plan)
    }

    // MARK: - Focused alone

    func testFocusedWithoutPlanShowsFocused() {
        let style = ComposerHaloStyle.resolve(
            planMode: false,
            isFocused: true,
            isStreaming: false
        )
        XCTAssertEqual(style, .focused)
    }

    func testNothingActiveShowsNone() {
        let style = ComposerHaloStyle.resolve(
            planMode: false,
            isFocused: false,
            isStreaming: false
        )
        XCTAssertEqual(style, .none)
    }

    // MARK: - Visual metadata

    func testNoneIsInvisible() {
        XCTAssertFalse(ComposerHaloStyle.none.isVisible)
        XCTAssertEqual(ComposerHaloStyle.none.lineWidth, 0)
    }

    func testPlanAndFocusedAreVisibleWithSameLineWidth() {
        XCTAssertTrue(ComposerHaloStyle.plan.isVisible)
        XCTAssertTrue(ComposerHaloStyle.focused.isVisible)
        XCTAssertEqual(ComposerHaloStyle.plan.lineWidth, 1.5)
        XCTAssertEqual(ComposerHaloStyle.focused.lineWidth, 1.5)
    }

    // MARK: - Sprint 5: dropTargeted

    func testDropTargetedHasHighestPriority() {
        // dropTargeted plan ve focused'tan üstün.
        for planMode in [false, true] {
            for isFocused in [false, true] {
                let style = ComposerHaloStyle.resolve(
                    planMode: planMode,
                    isFocused: isFocused,
                    isStreaming: false,
                    isDropTargeted: true
                )
                XCTAssertEqual(style, .dropTargeted,
                    "dropTargeted plan'dan da focused'tan da öncelikli (plan=\(planMode), focused=\(isFocused))")
            }
        }
    }

    func testStreamingStillOverridesDropTargeted() {
        // Streaming hâlâ en yüksek öncelik (UI disabled görsel anlatı).
        let style = ComposerHaloStyle.resolve(
            planMode: false,
            isFocused: false,
            isStreaming: true,
            isDropTargeted: true
        )
        XCTAssertEqual(style, .none)
    }

    func testDropTargetedVisualMetadata() {
        XCTAssertTrue(ComposerHaloStyle.dropTargeted.isVisible)
        XCTAssertEqual(ComposerHaloStyle.dropTargeted.lineWidth, 2.5)
    }
}
