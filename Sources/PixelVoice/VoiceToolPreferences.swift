import Foundation

/// **Sprint 46 (v0.2.74):** Voice modunda agent'ın çağırabileceği MCP tool'ların
/// kullanıcı tarafından opt-in/opt-out kontrolü.
///
/// Sprint 44'te `OpenAIToolBridge.voiceSafeToolNames` static set ile başladı —
/// 9 tool whitelist, UI tools dışlanmış. Sprint 46 kullanıcıya **per-tool
/// override** veriyor: Settings → Sesli Mod → "Voice Tools" listesi.
///
/// **3 kategori:**
/// 1. **Default-enabled (önerilen, 9 tool):** clipboard, time, active_app,
///    lan_ip, memory (save+search), notify, play_sound. Yan etkisiz veya
///    minor (geri alınabilir).
/// 2. **Risky (default-disabled, opt-in, 7 tool):** ui_click, ui_type,
///    ui_screenshot, ui_query, ui_resolve, dispatch_subagent, dock_badge_set.
///    Voice modunda agent ekranı görmeden yanlış yere bastığında recovery
///    zor — kullanıcı bilinçli onay.
/// 3. **Custom override:** Kullanıcı default/risky kararını her tool için
///    bağımsız değiştirir; UserDefaults `pixel.voice.toolOverrides`.
///
/// **Saf helper** — `@unchecked Sendable` (UserDefaults thread-safe).
public struct VoiceToolPreferences: @unchecked Sendable {
    /// UserDefaults key — `[String: Bool]` JSON dict.
    public static let overridesDefaultsKey = "pixel.voice.toolOverrides"

    /// **Sprint 44 whitelist** — voice modunda default açık olan tool'lar.
    /// Yan etkisi olmayan (clipboard, time) veya geri alınabilir (notify,
    /// memory) tool'lar. UI manipulation veya long-running tool'lar dışında.
    public static let defaultEnabledToolNames: Set<String> = [
        // Saf-data / bilgi
        "get_clipboard",
        "set_clipboard",
        "get_current_time",
        "get_active_app",
        "get_lan_ip",
        // Memory (Sprint 36-37)
        "save_memory",
        "search_memory",
        // Notification (ufak yan etki)
        "notify",
        "play_sound",
    ]

    /// **Risky kategori** — default kapalı, kullanıcı opt-in ederse açar.
    /// UI manipulation = ekran görmeden risk; subagent = long-running.
    public static let riskyToolNames: Set<String> = [
        "ui_click",
        "ui_type",
        "ui_screenshot",
        "ui_query",
        "ui_resolve",
        "dispatch_subagent",
        "dock_badge_set",
    ]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// **Sprint 46:** Bu tool voice modunda aktif mi?
    /// Karar zinciri:
    /// 1. UserDefaults override varsa onu kullan.
    /// 2. `defaultEnabledToolNames` içindeyse → true.
    /// 3. Aksi halde (risky veya bilinmeyen) → false.
    public func isEnabled(_ toolName: String) -> Bool {
        if let override = loadOverrides()[toolName] {
            return override
        }
        return Self.defaultEnabledToolNames.contains(toolName)
    }

    /// **Sprint 46:** Tool için override kaydet (true/false). Default davranışa
    /// dönmek için `clearOverride(_:)`.
    public func setEnabled(_ toolName: String, _ enabled: Bool) {
        var overrides = loadOverrides()
        overrides[toolName] = enabled
        saveOverrides(overrides)
    }

    /// **Sprint 46:** Override sil — `defaultEnabledToolNames`'e geri dön.
    public func clearOverride(_ toolName: String) {
        var overrides = loadOverrides()
        overrides.removeValue(forKey: toolName)
        saveOverrides(overrides)
    }

    /// **Sprint 46:** Tüm override'ları sil — default davranışa dön.
    public func resetAllOverrides() {
        defaults.removeObject(forKey: Self.overridesDefaultsKey)
    }

    /// **Sprint 46:** Risk tool mu (UI manipulation / subagent / vs.)?
    /// UI'da turuncu uyarı badge için.
    public static func isRisky(_ toolName: String) -> Bool {
        riskyToolNames.contains(toolName)
    }

    /// **Sprint 46:** Default-enabled set'inde mi (Sprint 44 whitelist)?
    /// UI'da "önerilen" badge için.
    public static func isDefaultEnabled(_ toolName: String) -> Bool {
        defaultEnabledToolNames.contains(toolName)
    }

    // MARK: - Private

    private func loadOverrides() -> [String: Bool] {
        guard let raw = defaults.dictionary(forKey: Self.overridesDefaultsKey) as? [String: Bool] else {
            return [:]
        }
        return raw
    }

    private func saveOverrides(_ overrides: [String: Bool]) {
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.overridesDefaultsKey)
        } else {
            defaults.set(overrides, forKey: Self.overridesDefaultsKey)
        }
    }
}
