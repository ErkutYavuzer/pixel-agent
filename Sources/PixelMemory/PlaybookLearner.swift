import Foundation

/// **Sprint 36 (v0.2.63):** Query → top-N relevant memory entries ranker.
/// **Sprint 37 (v0.2.64):** `EmbeddingScorer` hybrid scoring (NLEmbedding +
/// char n-gram + word Jaccard fallback) ile genişletildi. Kısa metinlerde
/// (örn "Beni Erkut diye çağır" + "Erkut burada") morfolojik benzerlikler
/// artık yakalanır — Sprint 36'da Jaccard zayıflığı çözüldü.
///
/// `ChatViewModel.send` her user mesajı öncesi `MemoryStore.relevantContext(for:)`
/// çağırır; o da bu helper'ı kullanır. Sonuç entry'ler CLIBackend `priorContext`
/// parametresine "Similar past tasks:" prefix ile enjekte edilir. Agent
/// geçmiş benzer iş örüntülerini görür.
///
/// **Ranking:** `EmbeddingScorer.score(query, entry.content)` × category
/// `promptWeight` (0-4) çarpan. `recipe` tag'i ekstra +0.1 boost — v2
/// `PlaybookLearner` paterniyle uyumlu.
///
/// **Threshold:** Default `minSimilarity = 0.35` (Sprint 37'de 0.55'ten
/// düşürüldü çünkü n-gram skorları sentence embedding'e göre daha düşük
/// aralıkta — "erkut" + "erkut burada" trigram ~0.4 verir). Embedding
/// disable ise eski 0.55 daha uygun ama UI/MCP'de tek default kullanır;
/// kullanıcı ihtiyaç duyarsa Settings'ten ayarlayabilir (gelecek versiyon).
public enum PlaybookLearner {
    /// **Recipe tag boost** — tekrarlayan iş örüntüsü olarak etiketlenen
    /// entry'lere score boost. `task` kategorisindeki "recipe" tag'ı
    /// PlaybookLearner'ın özel niyeti.
    public static let recipeTagBoost: Double = 0.1
    public static let recipeTag: String = "recipe"

    /// **Sprint 36:** Query'ye en relevant entry'leri ranking sırasıyla dön.
    /// Filter chain:
    /// 1. `deleted` olmayan entry'ler (MemoryStore.loadAll zaten filter'lı).
    /// 2. `score(query, content) >= minSimilarity` Jaccard threshold.
    /// 3. `boostedScore = score + categoryWeight × 0.05 + (recipe ? 0.1 : 0)`.
    /// 4. Top-`limit` (default 3) by boosted score descending.
    public static func relevant(
        query: String,
        in entries: [MemoryEntry],
        limit: Int = 3,
        minSimilarity: Double = 0.35
    ) -> [MemoryEntry] {
        guard !query.isEmpty, !entries.isEmpty, limit > 0 else { return [] }

        let scored: [(entry: MemoryEntry, score: Double)] = entries.compactMap { entry in
            guard !entry.deleted else { return nil }
            // Sprint 37: Hybrid scoring — EmbeddingScorer dispatcher tier seçer
            // (İngilizce sentence embedding / multilingual char n-gram / word Jaccard).
            let baseScore = EmbeddingScorer.score(query, entry.content)
            guard baseScore >= minSimilarity else { return nil }
            var boosted = baseScore + Double(entry.category.promptWeight) * 0.05
            if entry.tags.contains(recipeTag) {
                boosted += recipeTagBoost
            }
            return (entry: entry, score: boosted)
        }

        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(limit).map { $0.entry })
    }

    /// **Sprint 36:** CLIBackend `priorContext` parametresine geçilecek
    /// formatlanmış metin — entry'leri bullet list olarak markdown.
    /// Sistem prompt'unda "Aşağıdaki geçmiş kayıtları göz önünde bulundur"
    /// gibi bir context block oluşturur.
    ///
    /// Boş entry list → boş string (caller `priorContext: nil` geçer veya
    /// boş string'i ignore eder).
    public static func formatPrompt(_ entries: [MemoryEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var lines: [String] = ["[Kullanıcı geçmişinden benzer kayıtlar]"]
        for entry in entries {
            let category = entry.category.displayName
            let tagsString = entry.tags.isEmpty ? "" : " #\(entry.tags.joined(separator: " #"))"
            lines.append("- (\(category))\(tagsString): \(entry.content)")
        }
        return lines.joined(separator: "\n")
    }
}
