import XCTest
@testable import PixelMacApp

/// **Sprint 39 (v0.2.66):** WindowDwellDetector dwell counter testleri.
final class WindowDwellDetectorTests: XCTestCase {

    actor FireRecorder {
        var fires: [(name: String, bundleID: String, title: String, minutes: Int)] = []
        func record(_ n: String, _ b: String, _ t: String, _ m: Int) {
            fires.append((n, b, t, m))
        }
        func count() -> Int { fires.count }
        func last() -> (name: String, bundleID: String, title: String, minutes: Int)? {
            fires.last
        }
    }

    final class MutableSource: @unchecked Sendable {
        private let lock = NSLock()
        private var current: WindowDwellDetector.WindowInfo?
        init(_ initial: WindowDwellDetector.WindowInfo?) { self.current = initial }
        func set(_ v: WindowDwellDetector.WindowInfo?) {
            lock.lock(); current = v; lock.unlock()
        }
        func get() -> WindowDwellDetector.WindowInfo? {
            lock.lock(); defer { lock.unlock() }; return current
        }
    }

    private func makeDetector(
        source: MutableSource,
        recorder: FireRecorder,
        threshold: TimeInterval = 60,
        poll: TimeInterval = 10,
        selfBundleID: String? = nil
    ) -> WindowDwellDetector {
        WindowDwellDetector(
            thresholdSeconds: threshold,
            pollIntervalSeconds: poll,
            windowSource: { source.get() },
            selfBundleID: selfBundleID,
            onFire: { n, b, t, m in await recorder.record(n, b, t, m) }
        )
    }

    func testAccumulatesDwellOnSameWindow() async {
        let source = MutableSource(.init(appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "main.swift"))
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        // Threshold 60s, poll 10s. İlk tick: dwell 0 (key set). Sonraki
        // her tick'te += 10. 7 tick → dwell 60 → fire.
        for _ in 0..<7 {
            await detector.tick()
        }
        let count = await recorder.count()
        XCTAssertEqual(count, 1)
        let last = await recorder.last()
        XCTAssertEqual(last?.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(last?.title, "main.swift")
        XCTAssertEqual(last?.minutes, 1)  // 60sn / 60 = 1
    }

    func testResetsDwellWhenWindowChanges() async {
        let source = MutableSource(.init(appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "a.swift"))
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        // 4 tick aynı pencerede (40s)
        for _ in 0..<4 {
            await detector.tick()
        }
        // Pencere değişir — dwell reset
        source.set(.init(appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "b.swift"))
        for _ in 0..<4 {
            await detector.tick()
        }
        // İlki 40s sonra reset; sonra 40s daha → 60s'e ulaşmadık
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testFiresOncePerWindow() async {
        let source = MutableSource(.init(appName: "Xcode", bundleID: "com.apple.dt.Xcode", title: "x"))
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        for _ in 0..<10 {
            await detector.tick()
        }
        // 100s ama threshold 60s → tek fire
        let count = await recorder.count()
        XCTAssertEqual(count, 1)
    }

    func testNoFireWhenWindowNil() async {
        let source = MutableSource(nil)
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        for _ in 0..<10 {
            await detector.tick()
        }
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testSelfBundleFilteredOut() async {
        let source = MutableSource(.init(
            appName: "Pixel Agent",
            bundleID: "dev.erkutyavuzer.pixel-agent",
            title: "Chat"
        ))
        let recorder = FireRecorder()
        let detector = makeDetector(
            source: source,
            recorder: recorder,
            threshold: 60,
            poll: 10,
            selfBundleID: "dev.erkutyavuzer.pixel-agent"
        )
        for _ in 0..<10 {
            await detector.tick()
        }
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testTitleVariantChangesKey() async {
        let source = MutableSource(.init(appName: "Browser", bundleID: "com.browser", title: "Tab A"))
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        // 4 tick "Tab A"
        for _ in 0..<4 {
            await detector.tick()
        }
        // Title değişir → reset
        source.set(.init(appName: "Browser", bundleID: "com.browser", title: "Tab B"))
        for _ in 0..<4 {
            await detector.tick()
        }
        // Toplam 80s ama ikisi ayrı pencere — fire yok
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testEmptyTitleDwellWorksOnBundleAlone() async {
        let source = MutableSource(.init(appName: "Terminal", bundleID: "com.apple.Terminal", title: ""))
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, threshold: 60, poll: 10)

        for _ in 0..<7 {
            await detector.tick()
        }
        let count = await recorder.count()
        XCTAssertEqual(count, 1, "Permission yok → title boş → bundle key bazında dwell hâlâ çalışmalı")
    }
}
