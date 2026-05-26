import Foundation

/// **Sprint 38 (v0.2.65):** Proaktif trigger mute store.
///
/// İki seviye:
/// - **Kind-level mute**: Tüm `idle` veya `appChange` bildirimleri suspans
///   edilir (kullanıcı "ben kendim çağırırım" diyor).
/// - **Bundle-level mute**: Belirli `bundleID` için `appChange` (örn Slack
///   her dakika bildirim atmasın).
///
/// UserDefaults-backed; pixel-agent'ın sandbox dizininde standart Defaults.
/// İki ayrı key:
/// - `pixel.proactive.suppressedKinds` → JSON array of TriggerKind raw values
/// - `pixel.proactive.suppressedBundles` → JSON array of bundle IDs
///
/// `Sendable` value type; mutating methods güncel state'in yeni snapshot'ını
/// döner — caller `ProactiveEngine` actor içinde tutar.
public struct SuppressionStore: Sendable, Equatable {
    public static let suppressedKindsDefaultsKey = "pixel.proactive.suppressedKinds"
    public static let suppressedBundlesDefaultsKey = "pixel.proactive.suppressedBundles"

    public private(set) var suppressedKinds: Set<TriggerKind>
    public private(set) var suppressedBundles: Set<String>

    public init(
        suppressedKinds: Set<TriggerKind> = [],
        suppressedBundles: Set<String> = []
    ) {
        self.suppressedKinds = suppressedKinds
        self.suppressedBundles = suppressedBundles
    }

    /// **Sprint 38:** Bu trigger için bildirim suppress edilmeli mi?
    /// - Trigger'ın `kind`'ı suppressed set'te ise → true
    /// - Trigger'ın `bundleSuppressionKey`'i suppressed set'te ise → true
    /// - Aksi halde → false
    public func shouldSuppress(_ trigger: ProactiveTrigger) -> Bool {
        if suppressedKinds.contains(trigger.kind) { return true }
        if let bundle = trigger.bundleSuppressionKey {
            // Bundle ID'leri normalize edilmiş set'te tutulur — trigger'dan
            // gelen ID'yi de aynı normalizasyondan geçir.
            let normalized = bundle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if suppressedBundles.contains(normalized) {
                return true
            }
        }
        return false
    }

    /// **Sprint 38:** Kind mute ekle/çıkar. Idempotent.
    public mutating func setKind(_ kind: TriggerKind, suppressed: Bool) {
        if suppressed {
            suppressedKinds.insert(kind)
        } else {
            suppressedKinds.remove(kind)
        }
    }

    /// **Sprint 38:** Bundle mute ekle/çıkar. Trim + lowercase normalize.
    public mutating func setBundle(_ bundleID: String, suppressed: Bool) {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        if suppressed {
            suppressedBundles.insert(normalized)
        } else {
            suppressedBundles.remove(normalized)
        }
    }

    // MARK: - UserDefaults persistence

    /// **Sprint 38:** UserDefaults'tan yükle. Eksik/bozuk veri → boş set
    /// fallback (defensive). Caller `init` sonrası bir kez çağırır.
    public static func load(from defaults: UserDefaults = .standard) -> SuppressionStore {
        var store = SuppressionStore()
        if let raw = defaults.array(forKey: suppressedKindsDefaultsKey) as? [String] {
            let kinds = raw.compactMap { TriggerKind(rawValue: $0) }
            store.suppressedKinds = Set(kinds)
        }
        if let raw = defaults.array(forKey: suppressedBundlesDefaultsKey) as? [String] {
            store.suppressedBundles = Set(raw)
        }
        return store
    }

    /// **Sprint 38:** Güncel state'i UserDefaults'a yaz. Caller mutate'den
    /// sonra çağırır — atomic değil ama best-effort.
    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(
            Array(suppressedKinds).map(\.rawValue).sorted(),
            forKey: Self.suppressedKindsDefaultsKey
        )
        defaults.set(
            Array(suppressedBundles).sorted(),
            forKey: Self.suppressedBundlesDefaultsKey
        )
    }
}
