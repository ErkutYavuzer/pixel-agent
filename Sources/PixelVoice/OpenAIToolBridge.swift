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

    /// **Sprint 44:** Voice modunda agent'in çağırabileceği tool'lar
    /// (whitelist). Sprint 45+'da Settings opt-in toggle ile genişler.
    public static let voiceSafeToolNames: Set<String> = [
        // Saf-data / bilgi (yan etkisiz)
        "get_clipboard",
        "set_clipboard",
        "get_current_time",
        "get_active_app",
        "get_lan_ip",
        // Memory (Sprint 36-37 — agent öğrensin)
        "save_memory",
        "search_memory",
        // Notification (ufak yan etki)
        "notify",
        "play_sound",
    ]

    /// **Sprint 44:** Tek tool MCP → OpenAI dönüşümü.
    public static func convert(_ tool: ToolDefinition) -> OpenAITool {
        OpenAITool(
            name: tool.name,
            description: tool.description,
            parameters: AnyEncodable(tool.inputSchema)
        )
    }

    /// **Sprint 44:** Registry'den voice-safe tool'ları çıkar + convert.
    /// `includeAll: true` ise whitelist atlanır (Sprint 45+ opt-in için).
    public static func voiceTools(from registry: ToolRegistry, includeAll: Bool = false) -> [OpenAITool] {
        let allTools = registry.all()
        let filtered = includeAll
            ? allTools
            : allTools.filter { voiceSafeToolNames.contains($0.name) }
        return filtered.map(convert)
    }
}

// **Sprint 44 (v0.2.71):** `JSONValue` zaten `Encodable` (PixelMCPServer/
// JSONValue.swift:30). `Sendable` mark JSONValue.swift'te yapılır eğer
// gerekirse — burada ek conformance yok (`@retroactive` aynı modülden retro
// markup yasak; ana tanımda olmalı).
