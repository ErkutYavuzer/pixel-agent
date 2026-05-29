import Foundation
import PixelMemory

/// **Sprint 51 (v0.2.80):** MCP server'a expose edilen skill tool'ları.
///
/// `MemoryTools` paterniyle aynı — standalone (`PixelMemory.SkillStore` direkt,
/// bridge yok). Mac app çalışmıyor olsa bile agent skill kaydedebilir/uygulayabilir.
///
/// **Skill = çok-adımlı, versiyonlu, kullanım-takipli workflow.** `save_memory`
/// atomik fact içindir; bu tool'lar tekrarlanabilir prosedürler içindir.
public enum SkillTools {
    public static let createSkill = ToolDefinition(
        name: "create_skill",
        description: """
        Yeniden kullanılabilir, çok-adımlı bir workflow ("skill") kaydeder.
        Cross-session persiste edilir; sonraki sohbetlerde ilgili görevlerde
        otomatik olarak prompt'a enjekte edilir.

        **NE ZAMAN ÇAĞIR:**
        Kullanıcı tekrarlanabilir bir prosedür/iş akışı tarif ettiğinde, sessizce çağır:
        - "PR review için şu adımları izle: 1… 2… 3…"
        - "Her release'te şu workflow'u uygula"
        - "Follow these steps every time / step by step"

        **NE ZAMAN ÇAĞIRMA:**
        - Tek-adımlı / tek-seferlik işler (onlar `save_memory` task'i olabilir)
        - Atomik fact'ler (ad, tercih → `save_memory`)
        - Belirsiz / yanlış anlamış olabileceğin durumlar

        **Format kuralı:** Kayıt sonrası ana cevabında tek satır "(Skill kaydedildi:
        <başlık>)" notu bırak. Dönüş değerindeki `lineage_id`'yi sakla — sonra
        `update_skill`/`apply_skill` ile referans vereceksin.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("Kısa skill başlığı (örn 'PR review akışı')."),
                ]),
                "trigger": .object([
                    "type": .string("string"),
                    "description": .string("Ne zaman uygulanmalı — relevance eşleşmesi bu metinle yapılır (örn 'pull request açarken')."),
                ]),
                "steps": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Sıralı adımlar. Her eleman bir adım."),
                ]),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Opsiyonel tag'lar."),
                ]),
            ]),
            "required": .array([.string("title"), .string("trigger"), .string("steps")]),
        ]),
        handler: { params in
            guard let title = params?["title"]?.stringValue, !title.trimmingCharacters(in: .whitespaces).isEmpty else {
                return ToolResultBuilder.error("`title` boş olmamalı.")
            }
            guard let trigger = params?["trigger"]?.stringValue, !trigger.trimmingCharacters(in: .whitespaces).isEmpty else {
                return ToolResultBuilder.error("`trigger` boş olmamalı.")
            }
            guard let stepsRaw = params?["steps"]?.arrayValue else {
                return ToolResultBuilder.error("`steps` bir dizi olmalı.")
            }
            let steps = stepsRaw.compactMap { $0.stringValue }
            guard !steps.isEmpty else {
                return ToolResultBuilder.error("`steps` en az bir adım içermeli.")
            }
            let tags = params?["tags"]?.arrayValue?.compactMap { $0.stringValue } ?? []
            do {
                let store = try SkillStore()
                let skill = try await store.create(title: title, trigger: trigger, steps: steps, tags: tags)
                return ToolResultBuilder.text("Skill kaydedildi (lineage_id: \(skill.lineageID.uuidString), v\(skill.version), \(skill.steps.count) adım).")
            } catch {
                return ToolResultBuilder.error("Skill kaydedilemedi: \(error.localizedDescription)")
            }
        }
    )

    public static let updateSkill = ToolDefinition(
        name: "update_skill",
        description: """
        Mevcut bir skill'i yeni bir versiyona günceller (self-improve). Eski
        versiyon arşivde kalır; aktif versiyon yenisidir.

        **NE ZAMAN ÇAĞIR:** Bir skill'i uygularken eksik/yanlış adım fark ettiğinde
        veya kullanıcı "şunu da ekle / şu adımı düzelt" dediğinde.

        `steps` verilirse adımlar tamamen değişir; `append_steps` verilirse sona
        eklenir. Sadece değiştirmek istediğin alanları gönder.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "lineage_id": .object([
                    "type": .string("string"),
                    "description": .string("create_skill / list_skills'ten alınan lineage_id (UUID)."),
                ]),
                "title": .object(["type": .string("string"), "description": .string("Yeni başlık (opsiyonel).")]),
                "trigger": .object(["type": .string("string"), "description": .string("Yeni trigger (opsiyonel).")]),
                "steps": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Adımları tamamen değiştir (opsiyonel)."),
                ]),
                "append_steps": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Mevcut adımların sonuna ekle (opsiyonel)."),
                ]),
                "tags": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "description": .string("Tag'ları değiştir (opsiyonel)."),
                ]),
            ]),
            "required": .array([.string("lineage_id")]),
        ]),
        handler: { params in
            guard let idRaw = params?["lineage_id"]?.stringValue, let lineageID = UUID(uuidString: idRaw) else {
                return ToolResultBuilder.error("`lineage_id` geçerli bir UUID olmalı.")
            }
            let title = params?["title"]?.stringValue
            let trigger = params?["trigger"]?.stringValue
            let steps = params?["steps"]?.arrayValue?.compactMap { $0.stringValue }
            let appendSteps = params?["append_steps"]?.arrayValue?.compactMap { $0.stringValue }
            let tags = params?["tags"]?.arrayValue?.compactMap { $0.stringValue }
            do {
                let store = try SkillStore()
                let updated = try await store.update(
                    lineageID: lineageID, title: title, trigger: trigger,
                    steps: steps, appendSteps: appendSteps, tags: tags
                )
                return ToolResultBuilder.text("Skill güncellendi (v\(updated.version), \(updated.steps.count) adım).")
            } catch SkillStoreError.skillNotFound {
                return ToolResultBuilder.error("Skill bulunamadı (lineage_id: \(idRaw)). Silinmiş olabilir.")
            } catch {
                return ToolResultBuilder.error("Skill güncellenemedi: \(error.localizedDescription)")
            }
        }
    )

    public static let listSkills = ToolDefinition(
        name: "list_skills",
        description: """
        Kayıtlı skill'leri listeler. `query` verilirse relevance'a göre (SkillRanker),
        verilmezse en çok kullanılan/en yeni aktif skill'ler. Çok-adımlı bir göreve
        başlamadan önce ilgili skill var mı diye çağır.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "description": .string("Opsiyonel arama — boşsa tümü.")]),
                "limit": .object([
                    "type": .string("integer"),
                    "description": .string("Maksimum sonuç (default 5, max 20)."),
                ]),
            ]),
        ]),
        handler: { params in
            let limit: Int = {
                if let raw = params?["limit"]?.intValue { return min(max(raw, 1), 20) }
                return 5
            }()
            do {
                let store = try SkillStore()
                let active = try await store.loadActive()
                let results: [SkillEntry]
                if let query = params?["query"]?.stringValue, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    results = SkillRanker.relevant(query: query, in: active, limit: limit, minSimilarity: 0.3)
                } else {
                    results = Array(active
                        .sorted { ($0.usageCount, $0.updatedAt) > ($1.usageCount, $1.updatedAt) }
                        .prefix(limit))
                }
                if results.isEmpty {
                    return ToolResultBuilder.text("Kayıtlı skill bulunamadı (toplam \(active.count) aktif skill).")
                }
                var lines: [String] = ["[\(results.count) skill]"]
                for s in results {
                    let stepsStr = s.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
                    lines.append("- [\(s.lineageID.uuidString)] \"\(s.title)\" (\(s.usageCount)× · \(s.trigger)): \(stepsStr)")
                }
                return ToolResultBuilder.text(lines.joined(separator: "\n"))
            } catch {
                return ToolResultBuilder.error("Skill listesi alınamadı: \(error.localizedDescription)")
            }
        }
    )

    public static let applySkill = ToolDefinition(
        name: "apply_skill",
        description: """
        Bir skill'in adımlarını döndürür ve kullanım sayacını (usageCount) artırır.
        Bir skill'i uygulamaya başlamadan önce çağır — adımları alırsın, sık
        kullanılan skill'ler relevance ranking'inde öne çıkar.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "lineage_id": .object([
                    "type": .string("string"),
                    "description": .string("list_skills / create_skill'ten alınan lineage_id (UUID)."),
                ]),
            ]),
            "required": .array([.string("lineage_id")]),
        ]),
        handler: { params in
            guard let idRaw = params?["lineage_id"]?.stringValue, let lineageID = UUID(uuidString: idRaw) else {
                return ToolResultBuilder.error("`lineage_id` geçerli bir UUID olmalı.")
            }
            do {
                let store = try SkillStore()
                let skill = try await store.recordUsage(lineageID: lineageID)
                let stepsStr = skill.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                return ToolResultBuilder.text("\"\(skill.title)\" (v\(skill.version), \(skill.usageCount)× kullanıldı):\n\(stepsStr)")
            } catch SkillStoreError.skillNotFound {
                return ToolResultBuilder.error("Skill bulunamadı (lineage_id: \(idRaw)). Silinmiş olabilir.")
            } catch {
                return ToolResultBuilder.error("Skill uygulanamadı: \(error.localizedDescription)")
            }
        }
    )
}
