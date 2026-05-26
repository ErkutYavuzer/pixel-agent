import Foundation

/// **Sprint 36 (v0.2.63):** Duplicate detection + merge yardımcısı.
///
/// MemoryStore append-only — kullanıcı bilerek veya bilmeden aynı/çok benzer
/// içerik birden fazla kez kaydedebilir. `MemoryConsolidator` periyodik veya
/// manuel olarak (Settings → "Optimize Et") çalışır, benzer entry'leri
/// tespit eder, birleştirir, store'u kompakt eder.
///
/// v2 (`MemoryConsolidator.swift`) cosine similarity 0.92 threshold
/// kullanıyordu (embedding-aware). v3 MVP'de embedding yok, **Jaccard 0.85**
/// threshold daha gevşek ama anlamlı duplicate'leri yakalıyor (test'lerde
/// doğrulanır). CoreML embedding v0.3+ aday — threshold revize edilir.
public enum MemoryConsolidator {
    /// **Sprint 36:** Default duplicate threshold — Jaccard similarity 0.85.
    /// Çok agresif olmasın; "Beni Mehmet diye çağır" + "Adım Mehmet" Jaccard
    /// 0.85 altında kalır (farklı tokens), ama "Beni Mehmet diye çağır" iki
    /// kez yazılırsa 1.0 → yakalanır.
    public static let defaultDuplicateThreshold: Double = 0.85

    /// **Sprint 36:** Aynı kategori + threshold üstü Jaccard benzeri olan
    /// entry çiftlerini döndür. Her çift `(older, newer)` — `older.updatedAt
    /// <= newer.updatedAt`. Caller `merge`'i çağırır veya UI'da kullanıcıya
    /// onay sorar.
    public static func findDuplicates(in entries: [MemoryEntry], threshold: Double = defaultDuplicateThreshold) -> [(older: MemoryEntry, newer: MemoryEntry)] {
        var pairs: [(older: MemoryEntry, newer: MemoryEntry)] = []
        let sorted = entries.sorted { $0.updatedAt < $1.updatedAt }
        // O(n²) — entry sayısı tipik <500 için kabul edilebilir.
        for i in 0..<sorted.count {
            for j in (i+1)..<sorted.count {
                let a = sorted[i]
                let b = sorted[j]
                // Sadece aynı kategori — `profile` + `task` aynı içerikse
                // muhtemelen farklı semantik (defensive false-positive guard).
                guard a.category == b.category else { continue }
                let similarity = TextSimilarityScorer.score(a.content, b.content)
                if similarity >= threshold {
                    pairs.append((older: a, newer: b))
                }
            }
        }
        return pairs
    }

    /// **Sprint 36:** İki entry'yi tek bir entry'ye birleştir.
    /// - `id`: `newer.id` (en son yazılan kazanır — caller `older`'ı delete
    ///   ile tombstone'lar).
    /// - `content`: `newer.content` (kullanıcının en son ifadesi otorite).
    /// - `tags`: union (normalize + dedup `withNormalizedTags` ile).
    /// - `category`: `newer.category` (kategori değişikliği niyetli olabilir).
    /// - `updatedAt`: `Date()` (merge anı).
    public static func merge(older: MemoryEntry, newer: MemoryEntry) -> MemoryEntry {
        let unionTags = older.tags + newer.tags
        var merged = MemoryEntry(
            id: newer.id,
            category: newer.category,
            content: newer.content,
            tags: unionTags,
            createdAt: min(older.createdAt, newer.createdAt),
            updatedAt: Date(),
            deleted: false
        )
        merged = merged.withNormalizedTags()
        return merged
    }
}
