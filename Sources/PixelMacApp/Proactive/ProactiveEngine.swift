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

    public typealias Delivery = @Sendable (_ title: String, _ body: String) async -> Void

    private var idleDetector: IdleDetector?
    private var appObserver: AppChangeObserver?
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

    /// **Sprint 38:** Production delivery — `SystemNotifications.post` wrap.
    public static let defaultDelivery: Delivery = { title, body in
        await SystemNotifications.post(title: title, body: body)
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
    }

    /// **Sprint 38:** Engine durdur. Detector'lar cancel olur.
    public func stop() async {
        await idleDetector?.stop()
        await appObserver?.stop()
        idleDetector = nil
        appObserver = nil
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
        await deliver(title, body)
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
