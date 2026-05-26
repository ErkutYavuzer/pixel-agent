import Foundation

/// **Sprint 38 (v0.2.65):** Proaktif tetikleyici türleri.
///
/// v2 (~64k LOC) `ProactiveEngine.swift:14-44` Trigger enum'unun v3 karşılığı.
/// MVP'de 2 case (idle + appChanged); Sprint 39'da windowDwell/typedPause/
/// upcomingEvent eklenecek (Accessibility/Calendar permission gerek).
///
/// Her trigger'ın `kind` ve `bundleID` (opsiyonel) bilgisi `SuppressionStore`
/// ve `ProactiveRateLimiter` tarafından mute/cooldown kararları için kullanılır.
///
/// `Sendable` — actor sınırları aracılığıyla taşınır.
public enum ProactiveTrigger: Sendable, Equatable {
    /// Kullanıcı N dakika boyunca herhangi bir input event üretmedi.
    /// `minutes` rapor anındaki idle süre (>= threshold).
    case idle(minutes: Int)

    /// Frontmost uygulama değişti. `name` insan-okur (Display name),
    /// `bundleID` SuppressionStore key'i için canonical identifier.
    case appChanged(name: String, bundleID: String)

    // **Sprint 39+ adayları** (Accessibility/Calendar permission):
    // case windowDwell(app: String, title: String, minutes: Int, bundleID: String)
    // case typedThenPaused(app: String, bundleID: String)
    // case upcomingEvent(title: String, minutesUntil: Int, location: String?)

    /// **`kind`** — `SuppressionStore` ve rate-limit anahtarı. Bundle'a göre
    /// daha granüler suppression istenirse `bundleSuppressionKey` ayrıca
    /// kullanılır.
    public var kind: TriggerKind {
        switch self {
        case .idle: return .idle
        case .appChanged: return .appChange
        }
    }

    /// **Sprint 38:** Bundle-spesifik suppression için anahtar. Örnek:
    /// Kullanıcı Slack için appChange bildirimlerini sustur, ama Xcode için
    /// görsün. Idle gibi global trigger'lar nil döner.
    public var bundleSuppressionKey: String? {
        switch self {
        case .idle: return nil
        case .appChanged(_, let bundleID): return bundleID
        }
    }

    /// **Sprint 38:** Notification başlığı + body için kısa human-readable
    /// metin. Settings UI'da ayrıca açıklayıcı string ile gösterilir.
    public var humanDescription: String {
        switch self {
        case .idle(let minutes):
            return "\(minutes) dakikadır boştasınız"
        case .appChanged(let name, _):
            return "\(name) açıldı"
        }
    }
}

/// **Sprint 38 (v0.2.65):** Trigger kategorisi — payload-free identifier.
/// `SuppressionStore` ve `ProactiveRateLimiter` bu anahtar üzerinden çalışır
/// (örn "idle" suppress, "appChange" 60s cooldown).
public enum TriggerKind: String, CaseIterable, Sendable, Codable {
    case idle
    case appChange

    // **Sprint 39+ adayları:**
    // case windowDwell
    // case typedPause
    // case calendar

    /// Settings UI'da kullanıcıya gösterilecek başlık.
    public var displayName: String {
        switch self {
        case .idle: return "Boşta kalma"
        case .appChange: return "Uygulama değişimi"
        }
    }

    /// Settings UI'da açıklayıcı caption.
    public var description: String {
        switch self {
        case .idle: return "Kullanıcı N dakika input vermezse tetiklenir."
        case .appChange: return "Frontmost uygulama her değiştiğinde tetiklenir (1 dk debounce)."
        }
    }
}
