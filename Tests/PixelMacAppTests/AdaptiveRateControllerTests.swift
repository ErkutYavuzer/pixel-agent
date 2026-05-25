import XCTest

@testable import PixelMacApp

final class AdaptiveRateControllerTests: XCTestCase {

    // MARK: - Slow lane (backoff)

    func testHighLatencyTriggersBackoffByOneAndHalf() {
        // current 1000ms, latency 800ms (> current/2 = 500ms) → 1500ms.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 1000,
            lastSendLatencyMs: 800,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1500)
    }

    func testBackoffRespectsMaxCap() {
        // current 4000ms, latency 3000ms → would be 6000ms, capped at 5000.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 4000,
            lastSendLatencyMs: 3000,
            baseMs: 1000
        )
        XCTAssertEqual(next, 5000)
    }

    func testBackoffAtExactlyHalfThresholdNoOp() {
        // latency == current/2 (NOT >) → no change (hysteresis zone).
        let next = AdaptiveRateController.nextInterval(
            currentMs: 1000,
            lastSendLatencyMs: 500,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1000)
    }

    // MARK: - Fast lane (speedup)

    func testLowLatencyAndAboveBaseTriggersSpeedup() {
        // current 2000ms, latency 100ms (< 2000/10 = 200ms), base 1000 → 0.8x = 1600.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 2000,
            lastSendLatencyMs: 100,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1600)
    }

    func testSpeedupRespectsBaseFloor() {
        // current 1100ms, latency 50ms → 880, ama base=1000 → max(1000, 880) = 1000.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 1100,
            lastSendLatencyMs: 50,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1000)
    }

    func testSpeedupDoesNotTriggerAtBase() {
        // current == base → speedup skip (zaten user tercih tabanında).
        let next = AdaptiveRateController.nextInterval(
            currentMs: 1000,
            lastSendLatencyMs: 50,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1000)
    }

    // MARK: - Hysteresis zone

    func testMidLatencyNoChange() {
        // latency 300ms, current 1000ms (between thresholds 100 and 500) → no change.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 1000,
            lastSendLatencyMs: 300,
            baseMs: 1000
        )
        XCTAssertEqual(next, 1000)
    }

    // MARK: - Defensive clamping

    func testDefensiveClampInvalidCurrent() {
        // currentMs > maxMs → defensive clamp + speedup yine işler.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 9999,
            lastSendLatencyMs: 50,
            baseMs: 1000
        )
        // current 5000 (clamped), latency 50 < 500 → 5000*0.8 = 4000.
        XCTAssertEqual(next, 4000)
    }

    func testDefensiveClampNegativeLatency() {
        // Negative latency → treated as 0.
        let next = AdaptiveRateController.nextInterval(
            currentMs: 2000,
            lastSendLatencyMs: -100,
            baseMs: 1000
        )
        // latency 0 < 200 → 2000*0.8 = 1600.
        XCTAssertEqual(next, 1600)
    }

    // MARK: - Realistic scenarios

    func testSequentialBackoffThenSpeedup() {
        // Simulate slow network → fast network recovery.
        // Start: 1000ms (base 1000).
        var current = 1000

        // Tick 1: slow (latency 800) → 1500
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 800, baseMs: 1000)
        XCTAssertEqual(current, 1500)

        // Tick 2: still slow (latency 1200) → 2250
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 1200, baseMs: 1000)
        XCTAssertEqual(current, 2250)

        // Tick 3: network recovers (latency 50) → 1800 (0.8x)
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 50, baseMs: 1000)
        XCTAssertEqual(current, 1800)

        // Tick 4: still fast → 1440
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 50, baseMs: 1000)
        XCTAssertEqual(current, 1440)

        // Tick 5: still fast → 1152
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 50, baseMs: 1000)
        XCTAssertEqual(current, 1152)

        // Tick 6: still fast → max(1000, 921) = 1000 (base floor)
        current = AdaptiveRateController.nextInterval(currentMs: current, lastSendLatencyMs: 50, baseMs: 1000)
        XCTAssertEqual(current, 1000)
    }
}
