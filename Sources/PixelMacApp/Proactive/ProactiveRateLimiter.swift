import Foundation

/// **Sprint 38 (v0.2.65):** Proaktif tetikleyici rate-limit kararı.
///
/// İki katman:
/// - **Global cooldown** (default 5 dakika): Hiçbir trigger global pencerede
///   bir kereden fazla atmaz. Kullanıcının "rahatsız ediliyorum" hissini
///   önler.
/// - **Per-kind cooldown** (override): idle başka, appChange başka. Default
///   her ikisi de 5 dakika; ileride per-kind ince ayar yapılabilir.
///
/// Saf value type — `lastFires` snapshot'ı state taşıyıcısı. `ProactiveEngine`
/// actor içinde tutar, her trigger sonrası `record()` çağırır.
public struct ProactiveRateLimiter: Sendable, Equatable {
    /// Default global cooldown — herhangi bir trigger pencere içinde tek atış.
    public static let defaultCooldownSeconds: TimeInterval = 300  // 5 dakika

    /// Per-kind son tetikleme zamanları. Caller `canFire`'dan sonra
    /// `record(kind:at:)` ile günceller.
    public private(set) var lastFires: [TriggerKind: Date]

    /// Per-kind opsiyonel cooldown override. Boşsa default kullanılır.
    public private(set) var cooldownsOverrides: [TriggerKind: TimeInterval]

    /// Global cooldown — herhangi bir trigger pencere içinde tek atış.
    public let globalCooldownSeconds: TimeInterval

    public init(
        lastFires: [TriggerKind: Date] = [:],
        cooldownsOverrides: [TriggerKind: TimeInterval] = [:],
        globalCooldownSeconds: TimeInterval = defaultCooldownSeconds
    ) {
        self.lastFires = lastFires
        self.cooldownsOverrides = cooldownsOverrides
        self.globalCooldownSeconds = max(0, globalCooldownSeconds)
    }

    /// **Sprint 38:** Bu trigger şu an atılabilir mi?
    ///
    /// İki check:
    /// 1. **Global cooldown** — herhangi bir kind son `globalCooldownSeconds`
    ///    içinde fired ise false.
    /// 2. **Per-kind cooldown** — bu kind son `effectiveCooldown(for:)`
    ///    içinde fired ise false.
    ///
    /// `now = Date()` test'lerde clock injection için parametre.
    public func canFire(_ kind: TriggerKind, now: Date = Date()) -> Bool {
        // Global cooldown — en son herhangi bir kind ne zaman fired?
        if let mostRecent = lastFires.values.max() {
            if now.timeIntervalSince(mostRecent) < globalCooldownSeconds {
                return false
            }
        }
        // Per-kind cooldown
        if let lastFire = lastFires[kind] {
            let cooldown = effectiveCooldown(for: kind)
            if now.timeIntervalSince(lastFire) < cooldown {
                return false
            }
        }
        return true
    }

    /// **Sprint 38:** Fire kaydet — caller `canFire == true` durumunda çağırır.
    public mutating func record(kind: TriggerKind, at time: Date = Date()) {
        lastFires[kind] = time
    }

    /// **Sprint 38:** Bu kind için efektif cooldown — override varsa o,
    /// yoksa global default.
    public func effectiveCooldown(for kind: TriggerKind) -> TimeInterval {
        cooldownsOverrides[kind] ?? globalCooldownSeconds
    }

    /// **Sprint 38:** Per-kind override set — Settings UI'dan çağrılabilir.
    public mutating func setCooldown(_ seconds: TimeInterval, for kind: TriggerKind) {
        cooldownsOverrides[kind] = max(0, seconds)
    }
}
