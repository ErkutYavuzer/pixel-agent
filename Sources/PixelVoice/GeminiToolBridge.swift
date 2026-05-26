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

    /// **Sprint 45:** Registry'den voice-safe tool'ları çıkar + convert +
    /// `tools[]` array'inde tek `functionDeclarations` grubunda paketle.
    /// `includeAll: true` whitelist bypass (Sprint 45+ opt-in).
    public static func voiceTools(from registry: ToolRegistry, includeAll: Bool = false) -> [GeminiTools] {
        let allTools = registry.all()
        let filtered = includeAll
            ? allTools
            : allTools.filter { OpenAIToolBridge.voiceSafeToolNames.contains($0.name) }
        guard !filtered.isEmpty else { return [] }
        let declarations = filtered.map(convert)
        return [GeminiTools(functionDeclarations: declarations)]
    }
}
