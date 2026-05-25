import Foundation
import XCTest

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@testable import PixelComputerUse

/// **Faz 5c follow-up (v0.2.53):** `ParallelCropDetection` orchestration
/// helper'ı. Vision dependency yok — mock OCR closure ile parallel execution
/// + union doğrulanır.
final class ParallelCropDetectionTests: XCTestCase {

    // MARK: - Empty input

    func testEmptyCropRectsReturnsEmpty() async {
        let result = await ParallelCropDetection.detect(cropRects: []) { _ in
            return [CGRect(x: 0, y: 0, width: 10, height: 10)]
        }
        XCTAssertTrue(result.isEmpty,
            "Boş crop rects → boş sonuç; OCR closure çağrılmamalı")
    }

    func testEmptyCropRectsDoesNotCallOcr() async {
        let callCount = OCRCallCounter()
        _ = await ParallelCropDetection.detect(cropRects: []) { _ in
            await callCount.increment()
            return []
        }
        let count = await callCount.value
        XCTAssertEqual(count, 0)
    }

    // MARK: - Single crop

    func testSingleCropRectCallsOcrOnce() async {
        let callCount = OCRCallCounter()
        let cropRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let result = await ParallelCropDetection.detect(cropRects: [cropRect]) { rect in
            await callCount.increment()
            return [CGRect(x: rect.minX + 5, y: rect.minY + 5, width: 20, height: 20)]
        }
        let count = await callCount.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].origin, CGPoint(x: 5, y: 5))
    }

    // MARK: - Multiple crops + union

    func testMultipleCropRectsUnionAllResults() async {
        // 3 crop rect, her biri 2 region döner → toplam 6 region union'da.
        let crops = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
            CGRect(x: 200, y: 0, width: 100, height: 100),
        ]
        let result = await ParallelCropDetection.detect(cropRects: crops) { rect in
            return [
                CGRect(x: rect.minX, y: 0, width: 10, height: 10),
                CGRect(x: rect.minX + 50, y: 50, width: 10, height: 10),
            ]
        }
        XCTAssertEqual(result.count, 6)
    }

    func testEmptyResultsFromOcrUnionEmpty() async {
        let crops = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let result = await ParallelCropDetection.detect(cropRects: crops) { _ in
            return []  // Mock: no text in any crop.
        }
        XCTAssertTrue(result.isEmpty)
    }

    func testMixedResultsUnionPreservesAll() async {
        // First crop returns text, second returns empty → union = first only.
        let crops = [
            CGRect(x: 0, y: 0, width: 100, height: 100),
            CGRect(x: 100, y: 0, width: 100, height: 100),
        ]
        let result = await ParallelCropDetection.detect(cropRects: crops) { rect in
            if rect.minX == 0 {
                return [CGRect(x: 10, y: 10, width: 20, height: 20)]
            } else {
                return []
            }
        }
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0], CGRect(x: 10, y: 10, width: 20, height: 20))
    }

    // MARK: - Parallel execution (concurrency)

    func testParallelExecutionMultipleInFlight() async {
        // 5 crop rect, her biri 100ms gecikme. Sequential olsa 500ms+;
        // parallel olduğu için < 500ms olmalı. Conservative timeout.
        let crops = (0..<5).map { i in
            CGRect(x: Double(i * 100), y: 0, width: 100, height: 100)
        }
        let start = Date()
        let result = await ParallelCropDetection.detect(cropRects: crops) { rect in
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            return [CGRect(x: rect.minX, y: 0, width: 10, height: 10)]
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.count, 5)
        XCTAssertLessThan(elapsed, 0.35,
            "5 task × 100ms = 500ms sequential. Parallel <350ms (conservative — Neural Engine/CPU scheduler latency dahil).")
    }

    func testParallelExecutionTracksConcurrentTasks() async {
        // 4 crop rect, her biri 200ms; counter ile concurrent in-flight ölçülür.
        let observer = ConcurrencyObserver()
        let crops = (0..<4).map { i in
            CGRect(x: Double(i * 100), y: 0, width: 100, height: 100)
        }
        _ = await ParallelCropDetection.detect(cropRects: crops) { _ in
            await observer.enter()
            try? await Task.sleep(nanoseconds: 200_000_000)
            await observer.exit()
            return []
        }
        let max = await observer.peakConcurrency
        XCTAssertGreaterThan(max, 1,
            "Aynı anda en az 2 task in-flight olmalı (gerçek paralelizm)")
    }

    // MARK: - Edge cases

    func testManyCropRectsPerformsAllOcrs() async {
        // 20 crop rect → 20 OCR call, hepsi union'da.
        let callCount = OCRCallCounter()
        let crops = (0..<20).map { i in
            CGRect(x: Double(i * 10), y: 0, width: 10, height: 10)
        }
        _ = await ParallelCropDetection.detect(cropRects: crops) { _ in
            await callCount.increment()
            return [CGRect(x: 0, y: 0, width: 5, height: 5)]
        }
        let count = await callCount.value
        XCTAssertEqual(count, 20)
    }

    func testOcrClosureNeverCalledForEmptyInput() async {
        // Defensive: closure side-effect olmasa bile çağrılmamalı.
        // Actor counter ile Sendable-safe.
        let flag = OCRCallCounter()
        _ = await ParallelCropDetection.detect(cropRects: []) { _ in
            await flag.increment()
            return []
        }
        let count = await flag.value
        XCTAssertEqual(count, 0)
    }
}

// MARK: - Test actors

/// Concurrency-safe call counter for closure-call assertion.
actor OCRCallCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// Track peak concurrent in-flight tasks. `enter()` / `exit()` her task ç/g.
actor ConcurrencyObserver {
    private var current: Int = 0
    private(set) var peakConcurrency: Int = 0

    func enter() {
        current += 1
        if current > peakConcurrency {
            peakConcurrency = current
        }
    }

    func exit() {
        current -= 1
    }
}
