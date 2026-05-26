import Foundation
import PixelTools

/// **Sprint 38 (v0.2.65):** Proaktif tetikleyici orchestratorü.
///
/// v2 (~64k LOC) `ProactiveEngine.swift:14-368` paterninin v3 karşılığı,
/// modüler sub-helper'lara ayrılmış:
/// - **`IdleDetector`** — CGEventSource polling, threshold tetikleme
/// - **`AppChangeObserver`** — NSWorkspace notification observer
/// - **`SuppressionStore`** — UserDefaults-backed per-kind/bundle mute
/// - **`ProactiveRateLimiter`** — global + per-kind cooldown
///
/// Engine bu helper'ları birleştirir, trigger'ları suppression + rate limit
/// filtresinden geçirir, **`SystemNotifications.post`** ile delivery yapar.
///
/// `Sendable` actor — Mac app lifecycle'ında `RootView.task` blokunda start
/// olur, app kapanınca implicit stop (process exit).
///
/// **Master toggle** UserDefaults `pixel.proactive.masterEnabled` (default
/// `true`). Settings'ten kapatılabilir → tüm trigger'lar suspend.
///
/// **Test edilebilirlik:** Tüm helper'lar mock'lanabilir. `deliver` closure
/// inject — production'da `SystemNotifications.post`, test'lerde fake.
public actor ProactiveEngine {
    public static let masterEnabledDefaultsKey = "pixel.proactive.masterEnabled"
    public static let idleThresholdDefaultsKey = "pixel.proactive.idleThresholdMinutes"
    public static let defaultIdleThresholdMinutes: Int = 15

    public typealias Delivery = @Sendable (_ title: String, _ body: String, _ userInfo: [String: String]) async -> Void

    private var idleDetector: IdleDetector?
    private var appObserver: AppChangeObserver?
    private var typedPauseDetector: TypedPauseDetector?
    private var windowDwellDetector: WindowDwellDetector?
    private var calendarDetector: CalendarEventDetector?

    private var rateLimiter: ProactiveRateLimiter
    private var suppression: SuppressionStore
    private let deliver: Delivery
    private let defaults: UserDefaults

    /// Engine running mi — `start()` idempotent için.
    private var isRunning: Bool = false

    public init(
        rateLimiter: ProactiveRateLimiter = ProactiveRateLimiter(),
        suppression: SuppressionStore = SuppressionStore.load(),
        defaults: UserDefaults = .standard,
        deliver: @escaping Delivery = ProactiveEngine.defaultDelivery
    ) {
        self.rateLimiter = rateLimiter
        self.suppression = suppression
        self.defaults = defaults
        self.deliver = deliver
    }

    /// **Sprint 38 + 40:** Production delivery — `SystemNotifications.post`
    /// wrap. Sprint 40'da `userInfo` ile trigger context iletilir; tap
    /// `NotificationActionDispatcher`'a ulaşır → ChatView draft inject.
    public static let defaultDelivery: Delivery = { title, body, userInfo in
        await SystemNotifications.post(title: title, body: body, userInfo: userInfo)
    }

    /// **Sprint 38:** Engine başlat. Master toggle kapalıysa no-op.
    /// Detector'ları yarat ve `start()` çağır.
    public func start() async {
        guard !isRunning else { return }
        guard isMasterEnabled() else { return }
        isRunning = true

        let thresholdMinutes = currentIdleThresholdMinutes()
        let thresholdSeconds = TimeInterval(thresholdMinutes * 60)

        // Idle detector
        let idle = IdleDetector(
            thresholdSeconds: thresholdSeconds,
            onFire: { [weak self] minutes in
                await self?.handle(.idle(minutes: minutes))
            }
        )
        await idle.start()
        idleDetector = idle

        // App change observer
        let observer = AppChangeObserver(
            onFire: { [weak self] name, bundle in
                await self?.handle(.appChanged(name: name, bundleID: bundle))
            }
        )
        await observer.start()
        appObserver = observer

        // Sprint 39 (v0.2.66): Tier 2 detector'lar
        // TypedPause — permission YOK
        let typed = TypedPauseDetector(onFire: { [weak self] name, bundle in
            await self?.handle(.typedPause(app: name, bundleID: bundle))
        })
        await typed.start()
        typedPauseDetector = typed

        // WindowDwell — Accessibility permission gerek (yoksa title boş, dwell
        // bundle bazında çalışır)
        let dwell = WindowDwellDetector(onFire: { [weak self] name, bundle, title, minutes in
            await self?.handle(.windowDwell(
                app: name, title: title, minutes: minutes, bundleID: bundle
            ))
        })
        await dwell.start()
        windowDwellDetector = dwell

        // Calendar — EKEventStore permission gerek (yoksa detector no-op olur,
        // tick'lerde event source nil döner, fire çıkmaz)
        let calendar = CalendarEventDetector(onFire: { [weak self] title, minutesUntil, location in
            await self?.handle(.upcomingEvent(
                title: title, minutesUntil: minutesUntil, location: location
            ))
        })
        await calendar.start()
        calendarDetector = calendar
    }

    /// **Sprint 38:** Engine durdur. Detector'lar cancel olur.
    public func stop() async {
        await idleDetector?.stop()
        await appObserver?.stop()
        await typedPauseDetector?.stop()
        await windowDwellDetector?.stop()
        await calendarDetector?.stop()
        idleDetector = nil
        appObserver = nil
        typedPauseDetector = nil
        windowDwellDetector = nil
        calendarDetector = nil
        isRunning = false
    }

    /// **Sprint 38:** Trigger handle — suppression + rate-limit chain →
    /// delivery. Public test entry point (manuel trigger inject için).
    public func handle(_ trigger: ProactiveTrigger, now: Date = Date()) async {
        // 1. Suppression
        if suppression.shouldSuppress(trigger) { return }
        // 2. Rate limit
        guard rateLimiter.canFire(trigger.kind, now: now) else { return }
        // 3. Record + deliver
        rateLimiter.record(kind: trigger.kind, at: now)
        let (title, body) = format(trigger)
        // Sprint 40 (v0.2.67): userInfo trigger payload — tap sonrası
        // dispatcher decode edip ChatView draft inject eder.
        await deliver(title, body, trigger.userInfoPayload())
    }

    /// **Sprint 38:** Suppression store güncellendiğinde UserDefaults'a yaz +
    /// engine state'ini değiştir. Settings UI'dan çağrılır.
    public func updateSuppression(_ newStore: SuppressionStore) {
        suppression = newStore
        suppression.save(to: defaults)
    }

    /// **Sprint 38:** Current suppression — Settings UI'a expose.
    public func currentSuppression() -> SuppressionStore { suppression }

    /// **Sprint 38:** Engine running mi? Settings UI'da göstergeli.
    public func currentlyRunning() -> Bool { isRunning }

    // MARK: - Helpers

    /// Notification title + body üretir trigger için.
    public func format(_ trigger: ProactiveTrigger) -> (title: String, body: String) {
        switch trigger {
        case .idle(let minutes):
            return (
                title: "Pixel Agent — boştasınız",
                body: "\(minutes) dakikadır işlem yok. Yardım isterseniz Pixel Agent'ı açabilirsiniz."
            )
        case .appChanged(let name, _):
            return (
                title: "Pixel Agent — \(name)",
                body: "Bu uygulamayla ilgili sorularınız için Pixel Agent'a yazabilirsiniz."
            )
        case .windowDwell(let app, let title, let minutes, _):
            let titleSuffix = title.isEmpty ? "" : " — \(title)"
            return (
                title: "Pixel Agent — \(app)\(titleSuffix)",
                body: "\(minutes) dakikadır bu pencerede çalışıyorsun. Tıkanan bir şey var mı?"
            )
        case .typedPause(let app, _):
            return (
                title: "Pixel Agent — \(app)",
                body: "Yazmayı bıraktın gibi görünüyor. Yardım ister misin?"
            )
        case .upcomingEvent(let title, let minutesUntil, let location):
            let locSuffix = location.map { " @ \($0)" } ?? ""
            return (
                title: "Pixel Agent — yaklaşan toplantı",
                body: "\(minutesUntil) dk sonra: \(title)\(locSuffix). Hazırlık için Pixel Agent'a danışabilirsin."
            )
        }
    }

    private func isMasterEnabled() -> Bool {
        if let stored = defaults.object(forKey: Self.masterEnabledDefaultsKey) as? Bool {
            return stored
        }
        return true  // Default ON
    }

    private func currentIdleThresholdMinutes() -> Int {
        let stored = defaults.integer(forKey: Self.idleThresholdDefaultsKey)
        return stored > 0 ? stored : Self.defaultIdleThresholdMinutes
    }
}
