import Foundation
import PixelMCPServer

/// **Sprint 45 (v0.2.72):** MCP `ToolDefinition` → Gemini `functionDeclarations`
/// converter + voice-safe whitelist.
///
/// **Format farkı (vs OpenAI):**
/// - OpenAI: `{"type": "function", "name": "...", "description": "...", "parameters": {...}}`
/// - Gemini: `{"name": "...", "description": "...", "parameters": {...}}` (no `type` field)
/// - Gemini ayrıca `tools[]` üst-seviyede gruplandırılmış olarak yollanır:
///   `[{"functionDeclarations": [...]}]`
///
/// **Whitelist** — `OpenAIToolBridge.voiceSafeToolNames` ile aynı (provider
/// fark etmez; whitelist semantic). Aynı reference kullan.
public enum GeminiToolBridge {

    /// **Sprint 45:** Tek MCP tool → Gemini function declaration.
    public static func convert(_ tool: ToolDefinition) -> GeminiFunctionDeclaration {
        GeminiFunctionDeclaration(
            name: tool.name,
            description: tool.description,
            parameters: AnyEncodable(tool.inputSchema)
        )
    }

    /// **Sprint 45 / Sprint 46 (v0.2.74):** Registry'den kullanıcı'nın aktive
    /// ettiği tool'ları çıkar + convert + Gemini `tools[]` spec'ine paketle.
    /// `VoiceToolPreferences` ile filter (OpenAIToolBridge ile aynı pattern).
    ///
    /// `includeAll: true` — TEST için preferences bypass.
    public static func voiceTools(
        from registry: ToolRegistry,
        preferences: VoiceToolPreferences = VoiceToolPreferences(),
        includeAll: Bool = false
    ) -> [GeminiTools] {
        let allTools = registry.all()
        let filtered = includeAll
            ? allTools
            : allTools.filter { preferences.isEnabled($0.name) }
        guard !filtered.isEmpty else { return [] }
        let declarations = filtered.map(convert)
        return [GeminiTools(functionDeclarations: declarations)]
    }
}
