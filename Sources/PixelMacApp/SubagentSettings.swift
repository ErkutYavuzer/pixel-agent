import Foundation

/// **Faz 4 (v0.2.39):** Subagent davranışı için kullanıcı tercihleri.
/// UserDefaults-backed (ChatHost'taki `@AppStorage` paterniyle aynı), Settings
/// sekmesinden değiştirilir; `dispatch_subagent` MCP tool varsayılan değerler
/// için bu store'u sorgular.
///
/// Saf struct + statik UserDefaults helper'ları → test edilebilir (test
/// suite UserDefaults izolasyonu için suiteName override eder).
public struct SubagentSettings: Sendable, Equatable {
    /// Tek bir subagent'in alabileceği maksimum süre (saniye). Varsayılan 60.
    public var maxDurationSeconds: Double
    /// Tek bir subagent'in üretebileceği maksimum çıktı (byte). nil = limit
    /// yok. Varsayılan nil.
    public var maxOutputBytes: Int?
    /// Aynı anda çalışabilecek maksimum subagent sayısı (cap). Varsayılan 3.
    public var maxParallelCap: Int
    /// `dispatch_subagent` MCP tool'unda kullanıcı backend belirtmediyse
    /// default. Varsayılan "claude".
    public var defaultBackend: String

    public init(
        maxDurationSeconds: Double = 60,
        maxOutputBytes: Int? = nil,
        maxParallelCap: Int = 3,
        defaultBackend: String = "claude"
    ) {
        // Validation — UI'dan invalid değer gelirse silently clamp.
        self.maxDurationSeconds = max(5, maxDurationSeconds)
        self.maxOutputBytes = maxOutputBytes.map { max(1024, $0) }  // min 1 KB
        self.maxParallelCap = max(1, min(maxParallelCap, 10))  // 1-10 arası
        self.defaultBackend = defaultBackend
    }

    public static let `default` = SubagentSettings()
}

// MARK: - UserDefaults persistence

public enum SubagentSettingsStore {
    public static let maxDurationKey = "pixel.subagent.maxDurationSeconds"
    public static let maxOutputBytesKey = "pixel.subagent.maxOutputBytes"
    public static let maxParallelCapKey = "pixel.subagent.maxParallelCap"
    public static let defaultBackendKey = "pixel.subagent.defaultBackend"
    /// Sentinel: maxOutputBytes UserDefaults'ta yoksa veya -1 ise → nil
    /// (Codable enum yerine basit Int sentinel; @AppStorage Int? doğrudan
    /// desteklemiyor).
    public static let noOutputLimitSentinel: Int = -1

    public static func load(defaults: UserDefaults = .standard) -> SubagentSettings {
        let duration = defaults.object(forKey: maxDurationKey) as? Double
        let bytesRaw = defaults.object(forKey: maxOutputBytesKey) as? Int
        let cap = defaults.object(forKey: maxParallelCapKey) as? Int
        let backend = defaults.string(forKey: defaultBackendKey)

        let bytes: Int? = {
            guard let raw = bytesRaw else { return nil }
            return raw == noOutputLimitSentinel ? nil : raw
        }()

        return SubagentSettings(
            maxDurationSeconds: duration ?? SubagentSettings.default.maxDurationSeconds,
            maxOutputBytes: bytes,
            maxParallelCap: cap ?? SubagentSettings.default.maxParallelCap,
            defaultBackend: backend ?? SubagentSettings.default.defaultBackend
        )
    }

    public static func save(_ settings: SubagentSettings, defaults: UserDefaults = .standard) {
        defaults.set(settings.maxDurationSeconds, forKey: maxDurationKey)
        defaults.set(settings.maxOutputBytes ?? noOutputLimitSentinel, forKey: maxOutputBytesKey)
        defaults.set(settings.maxParallelCap, forKey: maxParallelCapKey)
        defaults.set(settings.defaultBackend, forKey: defaultBackendKey)
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: maxDurationKey)
        defaults.removeObject(forKey: maxOutputBytesKey)
        defaults.removeObject(forKey: maxParallelCapKey)
        defaults.removeObject(forKey: defaultBackendKey)
    }
}
