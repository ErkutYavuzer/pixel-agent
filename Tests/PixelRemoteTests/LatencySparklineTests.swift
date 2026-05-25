import Foundation
import XCTest

@testable import PixelRemote

/// **Sprint 25 (v0.2.50):** `LatencySparkline` saf normalize helper.
/// View'dan bağımsız — 0-1 koordinat algoritması test edilir, SwiftUI Path
/// çizim katmanı testleri view-level (iOS UI test target henüz yok).
final class LatencySparklineTests: XCTestCase {

    // MARK: - points: edge cases

    func testEmptyLatenciesReturnsEmpty() {
        XCTAssertTrue(LatencySparkline.points(latencies: []).isEmpty)
    }

    func testSingleLatencyReturnsCenter() {
        // Tek değer → tek nokta, görsel olarak ortada (0.5, 0.5).
        let result = LatencySparkline.points(latencies: [42])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result[0].y, 0.5, accuracy: 0.0001)
    }

    func testAllSameLatencyReturnsMidline() {
        // Tüm değerler aynı → range=0 → defensive y=0.5 (div-by-zero korumalı).
        let result = LatencySparkline.points(latencies: [100, 100, 100, 100])
        XCTAssertEqual(result.count, 4)
        for (i, point) in result.enumerated() {
            XCTAssertEqual(point.x, Double(i) / 3.0, accuracy: 0.0001)
            XCTAssertEqual(point.y, 0.5, accuracy: 0.0001)
        }
    }

    // MARK: - points: normalization

    func testTwoPointsAtMinMax() {
        // İki nokta min ve max — y=0 ve y=1.
        let result = LatencySparkline.points(latencies: [50, 200])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].x, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result[0].y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result[1].x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result[1].y, 1.0, accuracy: 0.0001)
    }

    func testMonotonicIncreasing() {
        // [0, 50, 100] → y'ler [0, 0.5, 1].
        let result = LatencySparkline.points(latencies: [0, 50, 100])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].y, 0.0, accuracy: 0.0001)
        XCTAssertEqual(result[1].y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result[2].y, 1.0, accuracy: 0.0001)
    }

    func testXSpacingUniform() {
        // 5 nokta → x'ler [0, 0.25, 0.5, 0.75, 1.0].
        let result = LatencySparkline.points(latencies: [10, 20, 30, 40, 50])
        XCTAssertEqual(result.count, 5)
        let expectedXs = [0.0, 0.25, 0.5, 0.75, 1.0]
        for (i, point) in result.enumerated() {
            XCTAssertEqual(point.x, expectedXs[i], accuracy: 0.0001,
                "x[\(i)] yanlış")
        }
    }

    func testCustomMinMaxBounds() {
        // Sabit eşik — min/max override (sparkline auto-scaling istenmediğinde).
        let result = LatencySparkline.points(
            latencies: [100, 200],
            minLatency: 0,
            maxLatency: 1000
        )
        XCTAssertEqual(result[0].y, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result[1].y, 0.2, accuracy: 0.0001)
    }

    func testYOrientationLowLatencyIsLowValue() {
        // 50ms (düşük latency) → y=0 (alt); 200ms (yüksek latency) → y=1 (üst).
        // View katmanı `1 - y` ile flip eder; düşük latency yukarıda gözükecek.
        // (Helper'ın iç konvansiyonu: y=0 alt, y=1 üst — caller flip eder.)
        let result = LatencySparkline.points(latencies: [50, 200])
        XCTAssertLessThan(result[0].y, result[1].y,
            "Düşük latency düşük y'ye map'lenmeli (helper convention).")
    }

    // MARK: - push: ring buffer

    func testPushAppendsBelowMax() {
        var buf: [Int] = []
        LatencySparkline.push(50, into: &buf, maxCount: 3)
        LatencySparkline.push(60, into: &buf, maxCount: 3)
        XCTAssertEqual(buf, [50, 60])
    }

    func testPushAtMaxKeepsAll() {
        var buf: [Int] = []
        LatencySparkline.push(50, into: &buf, maxCount: 3)
        LatencySparkline.push(60, into: &buf, maxCount: 3)
        LatencySparkline.push(70, into: &buf, maxCount: 3)
        XCTAssertEqual(buf, [50, 60, 70])
    }

    func testPushBeyondMaxDropsOldest() {
        var buf: [Int] = []
        LatencySparkline.push(50, into: &buf, maxCount: 3)
        LatencySparkline.push(60, into: &buf, maxCount: 3)
        LatencySparkline.push(70, into: &buf, maxCount: 3)
        LatencySparkline.push(80, into: &buf, maxCount: 3)
        XCTAssertEqual(buf, [60, 70, 80], "En eski (50) düşmeli")
    }

    func testPushIntoOversizedBufferTrimsAtOnce() {
        // Defensive: caller'ın maxCount değiştirdiği bir senaryoda buffer
        // halihazırda max'ın üzerinde olabilir; push tek seferde trim eder.
        var buf = [10, 20, 30, 40, 50]
        LatencySparkline.push(60, into: &buf, maxCount: 3)
        XCTAssertEqual(buf, [40, 50, 60])
    }

    func testPushMaxCountZero() {
        // Defensive: maxCount=0 → değer eklendikten sonra hemen silinir → boş.
        var buf: [Int] = []
        LatencySparkline.push(50, into: &buf, maxCount: 0)
        XCTAssertTrue(buf.isEmpty)
    }

    // MARK: - NormalizedPoint Equatable

    func testNormalizedPointEquatable() {
        let a = LatencySparkline.NormalizedPoint(x: 0.5, y: 0.7)
        let b = LatencySparkline.NormalizedPoint(x: 0.5, y: 0.7)
        let c = LatencySparkline.NormalizedPoint(x: 0.5, y: 0.8)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
