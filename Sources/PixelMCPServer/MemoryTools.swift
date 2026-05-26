import Foundation
import PixelMemory

/// **Sprint 36 (v0.2.63):** MCP server'a expose edilen memory tool'ları.
///
/// Mac app çalışmıyor olsa bile Claude/Codex/Gemini CLI doğrudan MCP server'a
/// bağlanıp memory entry kaydedebilir/arayabilir. `MemoryStore` actor
/// file-level sync ile çalışır; multi-process append race minimal (JSONL
/// satır bazlı decode, corrupt satır skip).
///
/// **save_memory**: agent kendi yeni context kaydedebilir (örn kullanıcı
/// "Beni Erkut diye çağır" → save_memory(category: "profile", content: "...")).
///
/// **search_memory**: agent geçmiş entry'lerde arama yapabilir (örn "Daha
/// önce 'PR review' workflow'u kaydetmiş miydim?" → search_memory(query: "PR
/// review")).
public enum MemoryTools {
    public static let saveMemory = ToolDefinition(
        name: "save_memory",
        description: """
        Kullanıcı veya agent için kalıcı bir memory entry kaydeder. Cross-session
        persiste edilir; sonraki sohbetlerde benzer task'lerde otomatik olarak
        prompt'a enjekte edilir (PlaybookLearner).

        **NE ZAMAN ÇAĞIR (Sprint 41 — otomatik öğrenme):**

        Sessizce, kullanıcıya sormadan, şu durumlarda doğrudan çağır:

        - Profil: "Benim adım Erkut" / "Beni X diye çağır" / "I'm a backend developer"
          → category="profile"
        - Tercih: "Kısa cevap tercih ederim" / "Always use TypeScript" / "Türkçe yaz"
          → category="preference"
        - Recipe (tekrarlayan): "PR review için şu template" / "Her seferinde X yap"
          → category="task", tags=["recipe"]
        - Aktif proje: "Şu an pixel-agent üzerinde çalışıyorum" / "I'm working on X"
          → category="project"

        **NE ZAMAN ÇAĞIRMA:**
        - Geçici durumlar ("Bugün biraz yorgunum")
        - Tek seferlik sorular ("Bu ne anlama gelir?")
        - Belirsiz / yanlış anlamış olabileceğin ifadeler
        - search_memory ile zaten kayıtlı olduğunu gördüğün bilgiler (duplicate)

        **Format kuralı:** Kayıt sonrası ana cevabında tek satırlık "(Hafızaya
        kaydedildim: <kısa özet>)" notu bırak. Kullanıcı bilsin.

        Kategoriler:
        - profile: Kullanıcı kimliği, rol, lokasyon, dil
        - preference: İletişim stili, ton tercihleri
        - project: Aktif iş bağlamı, hedefler
        - task: Tekrarlayan iş örüntüleri (tags: ["recipe"] ile boost)
        - note: Uzun-form serbest metin

        Aynı içerik tekrar yazılırsa duplicate olarak işaretlenir
        (MemoryConsolidator periyodik kompakta uygular).
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "category": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("profile"),
                        .string("preference"),
                        .string("project"),
                        .string("task"),
                        .string("note"),
                    ]),
                    "description": .string("Memory kategorisi (5'ten biri)."),
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("Memory içeriği (serbest metin)."),
                ]),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Opsiyonel tag'lar. 'recipe' tag'lı entry'ler PlaybookLearner ranking'inde +0.1 boost alır."),
                ]),
            ]),
            "required": .array([.string("category"), .string("content")]),
        ]),
        handler: { params in
            guard let categoryRaw = params?["category"]?.stringValue,
                  let category = MemoryCategory(rawValue: categoryRaw) else {
                return ToolResultBuilder.error("`category` parametresi geçerli olmalı (profile/preference/project/task/note).")
            }
            guard let content = params?["content"]?.stringValue, !content.trimmingCharacters(in: .whitespaces).isEmpty else {
                return ToolResultBuilder.error("`content` parametresi boş olmamalı.")
            }
            let tags: [String]
            if let tagsArray = params?["tags"]?.arrayValue {
                tags = tagsArray.compactMap { $0.stringValue }
            } else {
                tags = []
            }

            do {
                let store = try MemoryStore()
                let entry = MemoryEntry(category: category, content: content, tags: tags)
                try await store.add(entry)
                return ToolResultBuilder.text("Memory entry kaydedildi (id: \(entry.id.uuidString.prefix(8))…, kategori: \(category.rawValue), \(tags.count) tag).")
            } catch {
                return ToolResultBuilder.error("Memory entry kaydedilemedi: \(error.localizedDescription)")
            }
        }
    )

    public static let searchMemory = ToolDefinition(
        name: "search_memory",
        description: """
        Kalıcı memory'de arama yapar. `query` ile token-similarity (Jaccard) hesaplanır,
        threshold üstündeki entry'ler skorlarına göre döner. Bu tool agent'ın geçmiş
        bilgisini hatırlamasını sağlar — örn "Daha önce kaydettiğim 'PR review'
        workflow'unu hatırlıyor musun?"

        Kategori veya tag ile filter yapmak için opsiyonel `category` / `tag` parametreleri.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Arama metni — Jaccard token similarity ile match."),
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maksimum sonuç sayısı (default: 5, max: 20)."),
                    "minimum": .int(1),
                    "maximum": .int(20),
                ]),
                "category": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("profile"),
                        .string("preference"),
                        .string("project"),
                        .string("task"),
                        .string("note"),
                    ]),
                    "description": .string("Opsiyonel kategori filtresi."),
                ]),
                "tag": .object([
                    "type": .string("string"),
                    "description": .string("Opsiyonel tag filtresi (lowercase exact match)."),
                ]),
                "min_similarity": .object([
                    "type": .string("number"),
                    "description": .string("Jaccard threshold (default: 0.3, min: 0.0, max: 1.0). Düşük → daha gevşek match."),
                ]),
            ]),
            "required": .array([.string("query")]),
        ]),
        handler: { params in
            guard let query = params?["query"]?.stringValue, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                return ToolResultBuilder.error("`query` parametresi boş olmamalı.")
            }
            let limit: Int = {
                if let raw = params?["limit"]?.intValue { return min(max(raw, 1), 20) }
                return 5
            }()
            let minSimilarity: Double = {
                if let raw = params?["min_similarity"]?.doubleValue { return min(max(raw, 0.0), 1.0) }
                return 0.3
            }()

            do {
                let store = try MemoryStore()
                var entries = try await store.loadAll()

                if let categoryRaw = params?["category"]?.stringValue,
                   let category = MemoryCategory(rawValue: categoryRaw) {
                    entries = entries.filter { $0.category == category }
                }
                if let tagRaw = params?["tag"]?.stringValue {
                    let tag = tagRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    entries = entries.filter { $0.tags.contains(tag) }
                }

                let relevant = PlaybookLearner.relevant(
                    query: query,
                    in: entries,
                    limit: limit,
                    minSimilarity: minSimilarity
                )

                if relevant.isEmpty {
                    return ToolResultBuilder.text("Eşleşen memory entry bulunamadı (toplam \(entries.count) entry tarandı, min_similarity=\(minSimilarity)).")
                }

                var lines: [String] = ["[\(relevant.count) eşleşen entry]"]
                for entry in relevant {
                    let tagsStr = entry.tags.isEmpty ? "" : " #\(entry.tags.joined(separator: " #"))"
                    lines.append("- (\(entry.category.rawValue))\(tagsStr): \(entry.content)")
                }
                return ToolResultBuilder.text(lines.joined(separator: "\n"))
            } catch {
                return ToolResultBuilder.error("Memory arama başarısız: \(error.localizedDescription)")
            }
        }
    )
}
