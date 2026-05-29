import Foundation
import PixelMemory

/// **Sprint 52 (v0.2.81) — F1.** Standalone makro tool'u (`list_macros`).
/// `MacroStore`'u doğrudan okur (process-bağımsız, JSONL). `replay_macro`
/// bridge tool'u `BuiltInTools`'tadır (Mac app'te AX replay gerekir).
public enum MacroTools {
    public static let listMacros = ToolDefinition(
        name: "list_macros",
        description: """
        Kayıtlı computer-use makrolarını listeler (id + başlık + adım sayısı).
        Bir makroyu çalıştırmak için dönen `macro_id` ile `replay_macro` çağır.
        Makrolar kullanıcı tarafından Settings → Makrolar'dan kaydedilir.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        handler: { _ in
            do {
                let store = try MacroStore()
                let macros = try await store.loadActive()
                if macros.isEmpty {
                    return ToolResultBuilder.text("Kayıtlı makro yok.")
                }
                var lines: [String] = ["[\(macros.count) makro]"]
                for m in macros {
                    lines.append("- [\(m.id.uuidString)] \"\(m.title)\" (\(m.stepCount) adım)")
                }
                return ToolResultBuilder.text(lines.joined(separator: "\n"))
            } catch {
                return ToolResultBuilder.error("Makro listesi alınamadı: \(error.localizedDescription)")
            }
        }
    )
}
