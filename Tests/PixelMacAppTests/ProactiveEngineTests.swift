import XCTest
@testable import PixelMacApp

/// **Sprint 38 (v0.2.65):** ProactiveEngine orchestrator entegrasyon testleri.
/// Detector'lar başlatılmadan `handle(_:)` doğrudan çağrılarak suppression
/// + rate limit + delivery zinciri doğrulanır.
final class ProactiveEngineTests: XCTestCase {

    actor DeliveryRecorder {
        var calls: [(title: String, body: String)] = []
        func record(_ title: String, _ body: String) { calls.append((title, body)) }
        func count() -> Int { calls.count }
        func clear() { calls.removeAll() }
    }

    func testHandleDeliversTriggerWhenNotSuppressed() async {
        let recorder = DeliveryRecorder()
        let engine = ProactiveEngine(deliver: { title, body, _ in
            await recorder.record(title, body)
        })
        await engine.handle(.idle(minutes: 15))
        let count = await recorder.count()
        XCTAssertEqual(count, 1)
    }

    func testHandleSuppressedKindDoesNotDeliver() async {
        let recorder = DeliveryRecorder()
        var store = SuppressionStore()
        store.setKind(.idle, suppressed: true)
        let engine = ProactiveEngine(
            suppression: store,
            deliver: { t, b, _ in await recorder.record(t, b) }
        )
        await engine.handle(.idle(minutes: 20))
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testHandleSuppressedBundleDoesNotDeliver() async {
        let recorder = DeliveryRecorder()
        var store = SuppressionStore()
        store.setBundle("com.apple.safari", suppressed: true)
        let engine = ProactiveEngine(
            suppression: store,
            deliver: { t, b, _ in await recorder.record(t, b) }
        )
        await engine.handle(.appChanged(name: "Safari", bundleID: "com.apple.safari"))
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testRateLimitBlocksSecondTrigger() async {
        let recorder = DeliveryRecorder()
        let engine = ProactiveEngine(deliver: { t, b, _ in await recorder.record(t, b) })
        let now = Date(timeIntervalSince1970: 10_000)
        await engine.handle(.idle(minutes: 15), now: now)
        await engine.handle(.idle(minutes: 16), now: now.addingTimeInterval(10))
        let count = await recorder.count()
        XCTAssertEqual(count, 1, "Global cooldown ikinci tetiklemeyi engellemeli")
    }

    func testFormatProducesTurkishTitle() async {
        let engine = ProactiveEngine(deliver: { _, _, _ in })
        let (title, body) = await engine.format(.idle(minutes: 20))
        XCTAssertTrue(title.contains("Pixel Agent"))
        XCTAssertTrue(body.contains("20"))
    }

    func testFormatAppChangedUsesName() async {
        let engine = ProactiveEngine(deliver: { _, _, _ in })
        let (title, body) = await engine.format(.appChanged(name: "Xcode", bundleID: "com.apple.dt.Xcode"))
        XCTAssertTrue(title.contains("Xcode"))
        XCTAssertFalse(body.isEmpty)
    }

    func testUpdateSuppressionAppliesAtNextHandle() async {
        let recorder = DeliveryRecorder()
        let engine = ProactiveEngine(
            defaults: UserDefaults(suiteName: "test.engine.\(UUID().uuidString)")!,
            deliver: { t, b, _ in await recorder.record(t, b) }
        )
        // İlk: deliver
        await engine.handle(.appChanged(name: "Slack", bundleID: "com.slack"))
        var c1 = await recorder.count()
        XCTAssertEqual(c1, 1)

        // Wait beyond global cooldown for second test
        // Suppress et: ikinci handle delivery yapmamalı
        var store = await engine.currentSuppression()
        store.setBundle("com.slack", suppressed: true)
        await engine.updateSuppression(store)

        // Cooldown sonrası bile suppressed
        let later = Date(timeIntervalSinceNow: 600)
        await engine.handle(.appChanged(name: "Slack", bundleID: "com.slack"), now: later)
        let c2 = await recorder.count()
        XCTAssertEqual(c2, 1, "Suppression sonrası ikinci tetik yutulmalı")
    }

    func testCurrentSuppressionReturnsLatest() async {
        var store = SuppressionStore()
        store.setKind(.idle, suppressed: true)
        let engine = ProactiveEngine(suppression: store, deliver: { _, _, _ in })
        let snap = await engine.currentSuppression()
        XCTAssertTrue(snap.suppressedKinds.contains(.idle))
    }
}
