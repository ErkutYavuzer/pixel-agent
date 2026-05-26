import XCTest
@testable import PixelMacApp

/// **Sprint 39 (v0.2.66):** CalendarEventDetector window + dedup testleri.
final class CalendarEventDetectorTests: XCTestCase {

    actor FireRecorder {
        var fires: [(title: String, minutes: Int, location: String?)] = []
        func record(_ t: String, _ m: Int, _ l: String?) { fires.append((t, m, l)) }
        func count() -> Int { fires.count }
        func last() -> (title: String, minutes: Int, location: String?)? { fires.last }
    }

    final class MutableSource: @unchecked Sendable {
        private let lock = NSLock()
        private var current: CalendarEventDetector.UpcomingEvent?
        init(_ initial: CalendarEventDetector.UpcomingEvent?) { self.current = initial }
        func set(_ v: CalendarEventDetector.UpcomingEvent?) {
            lock.lock(); current = v; lock.unlock()
        }
        func get() -> CalendarEventDetector.UpcomingEvent? {
            lock.lock(); defer { lock.unlock() }; return current
        }
    }

    func testFiresWithin3To10MinuteWindow() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let event = CalendarEventDetector.UpcomingEvent(
            title: "Daily Standup",
            startDate: now.addingTimeInterval(5 * 60),  // 5 dk sonra
            location: "Zoom"
        )
        let source = MutableSource(event)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick(now: now)
        let count = await recorder.count()
        XCTAssertEqual(count, 1)
        let last = await recorder.last()
        XCTAssertEqual(last?.title, "Daily Standup")
        XCTAssertEqual(last?.minutes, 5)
        XCTAssertEqual(last?.location, "Zoom")
    }

    func testDoesNotFireBelowLowerBound() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let event = CalendarEventDetector.UpcomingEvent(
            title: "Imminent",
            startDate: now.addingTimeInterval(60),  // 1 dk sonra (< 3)
            location: nil
        )
        let source = MutableSource(event)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick(now: now)
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testDoesNotFireAboveUpperBound() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let event = CalendarEventDetector.UpcomingEvent(
            title: "Far",
            startDate: now.addingTimeInterval(15 * 60),  // 15 dk sonra (> 10)
            location: nil
        )
        let source = MutableSource(event)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick(now: now)
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testDedupSameEvent() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let event = CalendarEventDetector.UpcomingEvent(
            title: "Standup",
            startDate: now.addingTimeInterval(5 * 60),
            location: nil
        )
        let source = MutableSource(event)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick(now: now)
        await detector.tick(now: now.addingTimeInterval(30))
        await detector.tick(now: now.addingTimeInterval(60))
        let count = await recorder.count()
        XCTAssertEqual(count, 1, "Aynı event için per-key dedup")
    }

    func testFiresAgainForNewEvent() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let firstEvent = CalendarEventDetector.UpcomingEvent(
            title: "Standup",
            startDate: now.addingTimeInterval(5 * 60),
            location: nil
        )
        let source = MutableSource(firstEvent)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick(now: now)
        // Sonraki event farklı
        let secondEvent = CalendarEventDetector.UpcomingEvent(
            title: "Code Review",
            startDate: now.addingTimeInterval(20 * 60).addingTimeInterval(5 * 60),  // 20 dk sonra...
            location: nil
        )
        // Yeniden window'a alacak şekilde: now ileri kayar
        let later = now.addingTimeInterval(20 * 60)
        source.set(CalendarEventDetector.UpcomingEvent(
            title: "Code Review",
            startDate: later.addingTimeInterval(5 * 60),
            location: nil
        ))
        await detector.tick(now: later)
        let count = await recorder.count()
        XCTAssertEqual(count, 2)
    }

    func testNoFireWhenEventSourceNil() async {
        let source = MutableSource(nil)
        let recorder = FireRecorder()
        let detector = CalendarEventDetector(
            eventSource: { source.get() },
            onFire: { t, m, l in await recorder.record(t, m, l) }
        )
        await detector.tick()
        let count = await recorder.count()
        XCTAssertEqual(count, 0)
    }

    func testDedupKeyIncludesStartTime() {
        let date = Date(timeIntervalSince1970: 12_345)
        let event = CalendarEventDetector.UpcomingEvent(
            title: "X",
            startDate: date,
            location: nil
        )
        XCTAssertEqual(event.dedupKey, "X@12345")
    }
}
