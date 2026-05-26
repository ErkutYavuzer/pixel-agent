import XCTest
@testable import PixelMacApp

/// **Sprint 39 (v0.2.66):** TypedPauseDetector state machine testleri.
final class TypedPauseDetectorTests: XCTestCase {

    actor FireRecorder {
        var fires: [(name: String, bundleID: String)] = []
        func record(_ name: String, _ bundle: String) { fires.append((name, bundle)) }
        func count() -> Int { fires.count }
        func last() -> (name: String, bundleID: String)? { fires.last }
    }

    /// Sendable mutable source — NSLock arkasında int holder.
    final class MutableSource: @unchecked Sendable {
        private let lock = NSLock()
        private var keyDownSec: TimeInterval = 0
        private var front: (name: String, bundleID: String)? = (name: "Xcode", bundleID: "com.apple.dt.Xcode")
        func setKeyDown(_ v: TimeInterval) { lock.lock(); keyDownSec = v; lock.unlock() }
        func getKeyDown() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return keyDownSec }
        func setFront(_ v: (name: String, bundleID: String)?) { lock.lock(); front = v; lock.unlock() }
        func getFront() -> (name: String, bundleID: String)? { lock.lock(); defer { lock.unlock() }; return front }
    }

    private func makeDetector(
        source: MutableSource,
        recorder: FireRecorder,
        selfBundleID: String? = nil,
        pollInterval: TimeInterval = 5
    ) -> TypedPauseDetector {
        TypedPauseDetector(
            pollIntervalSeconds: pollInterval,
            keyDownSource: { source.getKeyDown() },
            frontAppSource: { source.getFront() },
            selfBundleID: selfBundleID,
            onFire: { name, bundle in await recorder.record(name, bundle) }
        )
    }

    // MARK: - Pause window

    func testFiresInPauseWindowAfterActiveStreak() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        // 1. Aktif yazma: 2 ardışık tick'te keyDown < pollInterval
        source.setKeyDown(1)
        await detector.tick()  // streak = 1
        await detector.tick()  // streak = 2

        // 2. Pause window: 8-30 sn arası
        source.setKeyDown(15)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 1)
        let last = await recorder.last()
        XCTAssertEqual(last?.bundleID, "com.apple.dt.Xcode")
    }

    func testDoesNotFireBelowMinActiveStreak() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        // Sadece 1 aktif tick
        source.setKeyDown(1)
        await detector.tick()  // streak = 1

        // Pause window'a gir
        source.setKeyDown(15)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0, "minActiveStreak (2) altında fire olmamalı")
    }

    func testDoesNotFireBelowPauseLowerBound() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()

        // < 8 saniye pause — daha fire window'da değil
        source.setKeyDown(5)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testDoesNotFireAbovePauseUpperBoundAndResetsStreak() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()

        // > 30 saniye — başka şey yapıyor
        source.setKeyDown(60)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0)

        // Streak reset edilmeli — pause window'a dönsek bile fire olmamalı
        source.setKeyDown(15)
        await detector.tick()
        let stillZero = await recorder.count()
        XCTAssertEqual(stillZero, 0, "60sn+ pause sonrası streak reset olur")
    }

    // MARK: - Dedup

    func testDoesNotFireTwiceForSameBundle() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()

        source.setKeyDown(15)
        await detector.tick()
        await detector.tick()  // İkinci pause tick — aynı bundle
        let count = await recorder.count()
        XCTAssertEqual(count, 1, "Per-bundle dedup")
    }

    func testFiresAgainAfterRetypingAndPause() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        // İlk pause cycle
        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()
        source.setKeyDown(15)
        await detector.tick()
        let c1 = await recorder.count()
        XCTAssertEqual(c1, 1)

        // Tekrar aktif yazma — dedup flag clear
        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()

        // Tekrar pause — yeni fire
        source.setKeyDown(15)
        await detector.tick()
        let c2 = await recorder.count()
        XCTAssertEqual(c2, 2)
    }

    // MARK: - Self filter

    func testIgnoresSelfBundleID() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(
            source: source,
            recorder: recorder,
            selfBundleID: "dev.erkutyavuzer.pixel-agent"
        )

        source.setFront((name: "Pixel Agent", bundleID: "dev.erkutyavuzer.pixel-agent"))
        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()

        source.setKeyDown(15)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0, "Self filter: kendi app'imizde fire olmamalı")
    }

    // MARK: - Missing front app

    func testNoFireWhenFrontAppNil() async {
        let source = MutableSource()
        source.setFront(nil)
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder)

        source.setKeyDown(1)
        await detector.tick()
        await detector.tick()
        source.setKeyDown(15)
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Lifecycle

    func testStopCancelsPollTask() async {
        let source = MutableSource()
        let recorder = FireRecorder()
        let detector = makeDetector(source: source, recorder: recorder, pollInterval: 0.01)
        await detector.start()
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        await detector.stop()
        // Smoke — call should not crash
        XCTAssertTrue(true)
    }
}
