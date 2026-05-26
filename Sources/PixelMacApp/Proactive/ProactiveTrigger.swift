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

    /// **Sprint 39 (v0.2.66):** Aynı pencerede N dakika kalındı.
    /// Accessibility permission ile `kAXTitleAttribute` okunur. `title` boş
    /// olabilir (permission yok veya app desteklemiyor) — o durumda app
    /// adı tek key.
    case windowDwell(app: String, title: String, minutes: Int, bundleID: String)

    /// **Sprint 39 (v0.2.66):** Kullanıcı yazıyordu, sonra durdu (8-30 sn
    /// keyDown gelmedi). `CGEventSource` ile, **permission YOK**.
    case typedPause(app: String, bundleID: String)

    /// **Sprint 39 (v0.2.66):** Yaklaşan calendar event (3-10 dakika içinde).
    /// EKEventStore Calendar permission ile okunur. `location` opsiyonel.
    case upcomingEvent(title: String, minutesUntil: Int, location: String?)

    /// **`kind`** — `SuppressionStore` ve rate-limit anahtarı. Bundle'a göre
    /// daha granüler suppression istenirse `bundleSuppressionKey` ayrıca
    /// kullanılır.
    public var kind: TriggerKind {
        switch self {
        case .idle: return .idle
        case .appChanged: return .appChange
        case .windowDwell: return .windowDwell
        case .typedPause: return .typedPause
        case .upcomingEvent: return .calendar
        }
    }

    /// **Sprint 38:** Bundle-spesifik suppression için anahtar. Örnek:
    /// Kullanıcı Slack için appChange bildirimlerini sustur, ama Xcode için
    /// görsün. Global trigger'lar (idle, calendar) nil döner.
    public var bundleSuppressionKey: String? {
        switch self {
        case .idle: return nil
        case .appChanged(_, let bundleID): return bundleID
        case .windowDwell(_, _, _, let bundleID): return bundleID
        case .typedPause(_, let bundleID): return bundleID
        case .upcomingEvent: return nil
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
        case .windowDwell(let app, _, let minutes, _):
            return "\(minutes) dakikadır \(app) penceresindesin"
        case .typedPause(let app, _):
            return "\(app)'te yazmayı bıraktın"
        case .upcomingEvent(let title, let minutesUntil, _):
            return "\(minutesUntil) dakika sonra: \(title)"
        }
    }
}

/// **Sprint 38 (v0.2.65):** Trigger kategorisi — payload-free identifier.
/// `SuppressionStore` ve `ProactiveRateLimiter` bu anahtar üzerinden çalışır
/// (örn "idle" suppress, "appChange" 60s cooldown).
public enum TriggerKind: String, CaseIterable, Sendable, Codable {
    case idle
    case appChange
    case windowDwell   // Sprint 39 — Accessibility permission
    case typedPause    // Sprint 39 — no permission
    case calendar      // Sprint 39 — Calendar permission

    /// Settings UI'da kullanıcıya gösterilecek başlık.
    public var displayName: String {
        switch self {
        case .idle: return "Boşta kalma"
        case .appChange: return "Uygulama değişimi"
        case .windowDwell: return "Pencerede uzun süre"
        case .typedPause: return "Yazma duraksaması"
        case .calendar: return "Yaklaşan toplantı"
        }
    }

    /// Settings UI'da açıklayıcı caption.
    public var description: String {
        switch self {
        case .idle: return "Kullanıcı N dakika input vermezse tetiklenir."
        case .appChange: return "Frontmost uygulama her değiştiğinde tetiklenir (60s debounce)."
        case .windowDwell: return "Aynı pencerede N dakika kalındığında (Accessibility izni gerek)."
        case .typedPause: return "Aktif yazma sonrası 8-30 sn duraklamada tetiklenir."
        case .calendar: return "3-10 dakika sonra başlayacak toplantı için uyarı (Calendar izni gerek)."
        }
    }

    /// **Sprint 39:** Bu trigger çalışması için sistem izni gerek mi?
    /// Settings UI permission durum badge'i için kullanılır.
    public var permissionRequirement: PermissionRequirement {
        switch self {
        case .idle, .appChange, .typedPause: return .none
        case .windowDwell: return .accessibility
        case .calendar: return .calendar
        }
    }
}

/// **Sprint 39 (v0.2.66):** Trigger'ın işletim için gerektirdiği permission.
/// Settings UI'da kullanıcıya bilgi vermek + System Preferences deep-link
/// için kullanılır.
public enum PermissionRequirement: String, Sendable {
    case none
    case accessibility
    case calendar

    public var displayName: String {
        switch self {
        case .none: return "İzin yok"
        case .accessibility: return "Accessibility"
        case .calendar: return "Calendar"
        }
    }
}
