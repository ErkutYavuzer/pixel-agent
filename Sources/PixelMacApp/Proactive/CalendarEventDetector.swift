import EventKit
import Foundation

/// **Sprint 39 (v0.2.66):** Yaklaşan calendar event detektörü.
///
/// v2 (`ProactiveEngine.swift:303-317`, `CalendarStore.swift:103`) paterni:
/// Her N saniyede `nextUpcoming(withinMinutes: 12)` çağır, sonuç 3-10 dakika
/// aralığındaysa fire. Event key cache (`title@start`) aynı event'i iki kez
/// tetiklemesin.
///
/// **Permission:** macOS 14+ `EKEventStore.requestFullAccessToEvents`.
/// `authorizationStatus(for: .event)` `.fullAccess` veya `.writeOnly` ise OK.
/// Permission yoksa detector start no-op olur, polling başlamaz.
///
/// State:
/// - `lastFiredEventKey: String?` — son fire edilen event'in `title@unix_start`
public actor CalendarEventDetector {
    /// Mock'lanabilir event source — test için EventKit dependency bypass.
    public typealias EventSource = @Sendable () -> UpcomingEvent?

    public struct UpcomingEvent: Sendable, Equatable {
        public let title: String
        public let startDate: Date
        public let location: String?

        public init(title: String, startDate: Date, location: String?) {
            self.title = title
            self.startDate = startDate
            self.location = location
        }

        /// Event key — deduplication için. Aynı title + start time aynı event.
        public var dedupKey: String {
            "\(title)@\(Int(startDate.timeIntervalSince1970))"
        }
    }

    public typealias FireCallback = @Sendable (
        _ title: String,
        _ minutesUntil: Int,
        _ location: String?
    ) async -> Void

    /// Polling interval — calendar events nadir değişir, 60sn yeterli.
    public static let defaultPollIntervalSeconds: TimeInterval = 60

    /// Pencere — bu kadar dakika sonra başlayacak event'leri al.
    public static let lookAheadMinutes: Int = 12

    /// Fire window — startTime ile şu an arası bu aralıkta olmalı.
    public static let fireWindowLowerMinutes: Int = 3
    public static let fireWindowUpperMinutes: Int = 10

    /// **Sprint 39:** Production event source — EKEventStore wrap.
    /// Permission status check + nextUpcoming query. MainActor üzerinde çağrılır.
    @MainActor
    public static func systemEventSource() -> UpcomingEvent? {
        guard isCalendarAuthorized() else { return nil }
        return CalendarEventDetector.nextUpcoming(withinMinutes: lookAheadMinutes)
    }

    @MainActor
    private static let sharedStore = EKEventStore()

    /// **Sprint 39:** Calendar permission durum kontrolü.
    @MainActor
    public static func isCalendarAuthorized() -> Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess, .writeOnly:
                return true
            default:
                return false
            }
        } else {
            return false
        }
    }

    /// **Sprint 39:** macOS 14+ Calendar full access request.
    @MainActor
    public static func requestAccessIfNeeded() async -> Bool {
        guard #available(macOS 14.0, *) else { return false }
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .writeOnly: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                sharedStore.requestFullAccessToEvents { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }

    /// **Sprint 39:** Şu an ile `withinMinutes` arasında başlayacak ilk event.
    @MainActor
    private static func nextUpcoming(withinMinutes minutes: Int) -> UpcomingEvent? {
        let now = Date()
        let future = now.addingTimeInterval(TimeInterval(minutes * 60))
        let predicate = sharedStore.predicateForEvents(
            withStart: now,
            end: future,
            calendars: nil
        )
        let events = sharedStore.events(matching: predicate)
        guard let first = events
            .filter({ !$0.isAllDay && $0.startDate > now })
            .sorted(by: { $0.startDate < $1.startDate })
            .first
        else { return nil }
        return UpcomingEvent(
            title: first.title ?? "(başlıksız)",
            startDate: first.startDate,
            location: first.location
        )
    }

    private let pollIntervalSeconds: TimeInterval
    private let eventSource: EventSource
    private let onFire: FireCallback
    private let lowerBoundMinutes: Int
    private let upperBoundMinutes: Int

    private var pollTask: Task<Void, Never>?
    private var lastFiredEventKey: String?

    public init(
        pollIntervalSeconds: TimeInterval = defaultPollIntervalSeconds,
        lowerBoundMinutes: Int = fireWindowLowerMinutes,
        upperBoundMinutes: Int = fireWindowUpperMinutes,
        eventSource: @escaping EventSource = {
            MainActor.assumeIsolated { CalendarEventDetector.systemEventSource() }
        },
        onFire: @escaping FireCallback
    ) {
        self.pollIntervalSeconds = max(10, pollIntervalSeconds)
        self.lowerBoundMinutes = max(0, lowerBoundMinutes)
        self.upperBoundMinutes = max(lowerBoundMinutes + 1, upperBoundMinutes)
        self.eventSource = eventSource
        self.onFire = onFire
    }

    public func start() {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = await self.pollIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// **Sprint 39:** Tek tick — event source çağır, window check + dedup +
    /// fire.
    public func tick(now: Date = Date()) async {
        guard let event = eventSource() else { return }
        let minutesUntil = Int(event.startDate.timeIntervalSince(now) / 60)
        guard minutesUntil >= lowerBoundMinutes,
              minutesUntil <= upperBoundMinutes else { return }
        guard lastFiredEventKey != event.dedupKey else { return }
        lastFiredEventKey = event.dedupKey
        await onFire(event.title, minutesUntil, event.location)
    }

    public var snapshotLastFiredKey: String? { lastFiredEventKey }
}
