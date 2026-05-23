import XCTest

@testable import PixelMacApp

final class SystemStatsTests: XCTestCase {
    typealias CPUTicks = SystemStats.CPUTicks

    func testComputePercentReturnsZeroOnNoDelta() {
        let same = CPUTicks(user: 100, system: 50, idle: 200, nice: 0)
        XCTAssertEqual(SystemStats.computePercent(previous: same, current: same), 0)
    }

    func testComputePercentSplitsActiveAndIdle() {
        let previous = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 60, system: 20, idle: 20, nice: 0)
        // active = 80, total = 100 → 80%
        XCTAssertEqual(SystemStats.computePercent(previous: previous, current: current), 80, accuracy: 0.001)
    }

    func testComputePercentIncludesNiceInActive() {
        let previous = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 10, system: 10, idle: 70, nice: 10)
        // active = user+system+nice = 30, total = 100 → 30%
        XCTAssertEqual(SystemStats.computePercent(previous: previous, current: current), 30, accuracy: 0.001)
    }

    func testComputePercentClampsToHundred() {
        let previous = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: .max, system: 0, idle: 0, nice: 0)
        let value = SystemStats.computePercent(previous: previous, current: current)
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThanOrEqual(value, 100)
    }

    func testComputePercentHandlesTickWraparound() {
        // user 32-bit tick counter wrap-around: previous near MAX, current small
        let previous = CPUTicks(user: .max - 9, system: 0, idle: 0, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 90, nice: 0)
        // &- wrap: 10 &- (UInt32.max - 9) = 20
        // active = 20, total = 110 → ~18.18%
        let value = SystemStats.computePercent(previous: previous, current: current)
        XCTAssertEqual(value, 18.1818, accuracy: 0.01)
    }

    func testFirstCPUCallReturnsZeroBaseline() async {
        let stats = SystemStats()
        let first = await stats.cpuUsagePercent()
        XCTAssertEqual(first, 0, "İlk çağrı previousTicks olmadığı için baseline 0 dönmeli")
    }

    func testMemoryUsageWithinSensibleRange() {
        let percent = SystemStats.memoryUsagePercent()
        XCTAssertGreaterThanOrEqual(percent, 0)
        XCTAssertLessThanOrEqual(percent, 100)
    }
}
