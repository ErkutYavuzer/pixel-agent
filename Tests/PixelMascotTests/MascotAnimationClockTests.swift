import XCTest
import CoreGraphics

@testable import PixelMascot

final class MascotAnimationClockTests: XCTestCase {

    // MARK: - Idle bob

    func testIdleOffsetIsZeroAtTimeZero() {
        let offset = MascotAnimationClock.idleOffset(time: 0)
        XCTAssertEqual(offset.width, 0, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }

    func testIdleOffsetVerticalOnly() {
        for t in [0.5, 1.0, 1.5, 2.0, 3.7] {
            let offset = MascotAnimationClock.idleOffset(time: t)
            XCTAssertEqual(offset.width, 0,
                           "t=\(t) için width=0 bekleniyor; got \(offset.width)")
        }
    }

    func testIdleOffsetAmplitudeWithinBounds() {
        // sin maks 1; amplitude 1.5 → |height| ≤ 1.5.
        for t in stride(from: 0.0, through: 8.0, by: 0.1) {
            let offset = MascotAnimationClock.idleOffset(time: t)
            XCTAssertLessThanOrEqual(abs(offset.height), 1.5 + 0.001,
                                     "t=\(t) → \(offset.height) bound aşıldı")
        }
    }

    func testIdleOffsetPeriodicityAt4Seconds() {
        // 4s periyot — t=0 ve t=4 değerleri yakın olmalı.
        let a = MascotAnimationClock.idleOffset(time: 0)
        let b = MascotAnimationClock.idleOffset(time: 4.0)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001)
    }

    // MARK: - Thinking wobble

    func testThinkingOffsetHorizontalOnly() {
        for t in [0.3, 0.7, 1.5] {
            let offset = MascotAnimationClock.thinkingOffset(time: t)
            XCTAssertEqual(offset.height, 0,
                           "t=\(t) → height=0 bekleniyor; got \(offset.height)")
        }
    }

    func testThinkingOffsetAmplitudeWithinBounds() {
        for t in stride(from: 0.0, through: 4.0, by: 0.1) {
            let offset = MascotAnimationClock.thinkingOffset(time: t)
            XCTAssertLessThanOrEqual(abs(offset.width), 0.8 + 0.001)
        }
    }

    // MARK: - Listening nod

    func testListeningOffsetIsZeroAtTimeZero() {
        let offset = MascotAnimationClock.listeningOffset(time: 0)
        XCTAssertEqual(offset.width, 0, accuracy: 0.001)
        XCTAssertEqual(offset.height, 0, accuracy: 0.001)
    }

    func testListeningOffsetVerticalOnly() {
        for t in [0.4, 0.9, 1.3, 2.1, 3.3] {
            let offset = MascotAnimationClock.listeningOffset(time: t)
            XCTAssertEqual(offset.width, 0,
                           "t=\(t) için width=0 bekleniyor; got \(offset.width)")
        }
    }

    func testListeningOffsetAmplitudeWithinBounds() {
        // amplitude 1.0 → |height| ≤ 1.0.
        for t in stride(from: 0.0, through: 6.0, by: 0.1) {
            let offset = MascotAnimationClock.listeningOffset(time: t)
            XCTAssertLessThanOrEqual(abs(offset.height), 1.0 + 0.001,
                                     "t=\(t) → \(offset.height) bound aşıldı")
        }
    }

    func testListeningOffsetPeriodicityAt1_67Seconds() {
        // 0.6 Hz → ~1.667s periyot; t=0 ve t=1/0.6 değerleri yakın olmalı.
        let a = MascotAnimationClock.listeningOffset(time: 0)
        let b = MascotAnimationClock.listeningOffset(time: 1.0 / 0.6)
        XCTAssertEqual(a.height, b.height, accuracy: 0.001)
    }

    // MARK: - Speaking frame index

    func testSpeakingFrameIndexAtZero() {
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0), 0)
    }

    func testSpeakingFrameIndexAlternates() {
        // 5Hz cycle: t × 5 → integer mod 2.
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0.0), 0)
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0.21), 1)
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0.41), 0)
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0.61), 1)
        XCTAssertEqual(MascotAnimationClock.speakingFrameIndex(time: 0.81), 0)
    }

    func testSpeakingFrameIndexBoundedInZeroOne() {
        for t in stride(from: 0.0, through: 1000.0, by: 1.0) {
            let idx = MascotAnimationClock.speakingFrameIndex(time: t)
            XCTAssertTrue(idx == 0 || idx == 1, "t=\(t) → \(idx)")
        }
    }

    // MARK: - Error shake decay

    func testErrorShakeAtElapsedZeroIsZero() {
        XCTAssertEqual(MascotAnimationClock.errorShakeOffset(elapsed: 0).width, 0, accuracy: 0.001)
    }

    func testErrorShakeAfterDecayPeriodIsZero() {
        XCTAssertEqual(MascotAnimationClock.errorShakeOffset(elapsed: 0.5).width, 0, accuracy: 0.001)
        XCTAssertEqual(MascotAnimationClock.errorShakeOffset(elapsed: 0.6), .zero)
        XCTAssertEqual(MascotAnimationClock.errorShakeOffset(elapsed: 1.0), .zero)
    }

    func testErrorShakeNegativeElapsedIsZero() {
        XCTAssertEqual(MascotAnimationClock.errorShakeOffset(elapsed: -0.1), .zero)
    }

    func testErrorShakeAmplitudeWithinBoundsDuringDecay() {
        for elapsed in stride(from: 0.0, through: 0.5, by: 0.01) {
            let offset = MascotAnimationClock.errorShakeOffset(elapsed: elapsed)
            XCTAssertLessThanOrEqual(abs(offset.width), 3.0 + 0.001)
        }
    }

    func testErrorShakeIsHorizontalOnly() {
        for elapsed in stride(from: 0.05, through: 0.4, by: 0.05) {
            let offset = MascotAnimationClock.errorShakeOffset(elapsed: elapsed)
            XCTAssertEqual(offset.height, 0)
        }
    }
}
