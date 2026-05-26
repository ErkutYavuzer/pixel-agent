import Foundation
import PixelMCPServer

/// **Sprint 44 (v0.2.71):** MCP `ToolDefinition` → OpenAI `OpenAITool`
/// converter + voice-safe whitelist.
///
/// **Voice-safe whitelist:** Voice modunda agent ekranı görmeden tool
/// çağırırsa risk var (örn ui_click yanlış yere bastığında undo zor). MVP'de
/// **saf-data + memory + bilgi** araçlarına izin ver; UI manipülasyonu olan
/// tool'lar (ui_click, ui_type, dispatch_subagent, dock_badge) Sprint 45+'da
/// kullanıcı opt-in.
///
/// **Tool definition format farkı:**
/// - MCP: `{"name": "X", "description": "...", "inputSchema": {...}}`
/// - OpenAI: `{"type": "function", "name": "X", "description": "...", "parameters": {...}}`
///
/// `parameters` MCP `inputSchema` JSON object'in aynısı (`type: object` +
/// `properties` + `required`).
public enum OpenAIToolBridge {

    /// **Sprint 44:** Default whitelist — backward-compat alias.
    /// **Sprint 46 (v0.2.74):** Gerçek seçim artık `VoiceToolPreferences` ile;
    /// bu alias `VoiceToolPreferences.defaultEnabledToolNames` ile aynı.
    public static let voiceSafeToolNames: Set<String> = VoiceToolPreferences.defaultEnabledToolNames

    /// **Sprint 44:** Tek tool MCP → OpenAI dönüşümü.
    public static func convert(_ tool: ToolDefinition) -> OpenAITool {
        OpenAITool(
            name: tool.name,
            description: tool.description,
            parameters: AnyEncodable(tool.inputSchema)
        )
    }

    /// **Sprint 46 (v0.2.74):** Registry'den kullanıcı'nın aktive ettiği
    /// tool'ları çıkar + convert. `VoiceToolPreferences` UserDefaults
    /// override'ları + default whitelist'i sırasıyla check eder.
    ///
    /// `includeAll: true` — TEST için tüm tool'ları döndürür (preferences
    /// bypass). Production'da kullanılmamalı.
    public static func voiceTools(
        from registry: ToolRegistry,
        preferences: VoiceToolPreferences = VoiceToolPreferences(),
        includeAll: Bool = false
    ) -> [OpenAITool] {
        let allTools = registry.all()
        let filtered = includeAll
            ? allTools
            : allTools.filter { preferences.isEnabled($0.name) }
        return filtered.map(convert)
    }
}

// **Sprint 44 (v0.2.71):** `JSONValue` zaten `Encodable` (PixelMCPServer/
// JSONValue.swift:30). `Sendable` mark JSONValue.swift'te yapılır eğer
// gerekirse — burada ek conformance yok (`@retroactive` aynı modülden retro
// markup yasak; ana tanımda olmalı).
