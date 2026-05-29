import Foundation

/// **Sprint 51 (v0.2.80):** Query → top-N relevant skill ranker.
///
/// [[PlaybookLearner]]'ın skill karşılığı. `EmbeddingScorer` (NLEmbedding +
/// char n-gram + Jaccard fallback) yeniden kullanılır — yeni dependency yok.
///
/// **Skor:** `EmbeddingScorer.score(query, trigger + " " + title)`. Steps
/// kasıtlı dahil edilmez (gürültü ekler; trigger+title sinyaldir). `usageCount`
/// küçük bir boost'a dönüşür (`min(usageCount, 5) × 0.02`, max +0.1) — sık
/// kullanılan skill öne çıkar (self-reinforcing).
///
/// `ChatViewModel.send` her user mesajı öncesi `SkillStore.loadActive()` →
/// `SkillRanker.relevant(...)` → `formatPrompt` ile system prompt'a ayrı bir
/// "[İlgili skill'ler]" section'ı enjekte eder.
public enum SkillRanker {
    /// usageCount başına boost; toplam cap'i sınırlamak için min(.,5).
    public static let usageBoostPerUse: Double = 0.02
    public static let usageBoostCap: Int = 5

    public static func relevant(
        query: String,
        in skills: [SkillEntry],
        limit: Int = 2,
        minSimilarity: Double = 0.35
    ) -> [SkillEntry] {
        guard !query.isEmpty, !skills.isEmpty, limit > 0 else { return [] }

        let scored: [(skill: SkillEntry, score: Double)] = skills.compactMap { skill in
            guard !skill.deleted else { return nil }
            let base = EmbeddingScorer.score(query, skill.trigger + " " + skill.title)
            guard base >= minSimilarity else { return nil }
            let boost = Double(min(skill.usageCount, usageBoostCap)) * usageBoostPerUse
            return (skill: skill, score: base + boost)
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.skill }
    }

    /// **Sprint 51:** System prompt'a enjekte edilecek skill section'ı.
    /// Boş skill list → boş string (caller ignore eder).
    public static func formatPrompt(_ skills: [SkillEntry]) -> String {
        guard !skills.isEmpty else { return "" }
        var lines: [String] = ["[İlgili kayıtlı skill'ler — uygunsa adımları izle]"]
        for skill in skills {
            let usage = skill.usageCount > 0 ? " (\(skill.usageCount)× kullanıldı)" : ""
            let steps = skill.steps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: " ")
            lines.append("- \"\(skill.title)\"\(usage): \(steps)")
        }
        return lines.joined(separator: "\n")
    }
}
