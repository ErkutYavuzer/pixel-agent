import Foundation
import NaturalLanguage

/// **Sprint 37 (v0.2.64):** 3-tier hybrid similarity dispatcher.
///
/// **Tier 1 — `NLEmbedding.sentenceEmbedding(for: .english)`** (yüksek kalite,
/// dim=512): query + content İngilizce ve uzunsa (≥ 12 char) bu kullanılır.
/// Apple framework, sıfır model overhead.
///
/// **Tier 2 — `CharNGramScorer`** (multilingual morphology-aware): Türkçe,
/// karışık veya kısa metinler için. n=3 trigram Jaccard.
///
/// **Tier 3 — `TextSimilarityScorer`** (word Jaccard, mevcut Sprint 36):
/// fallback — herhangi bir tier başarısızlığında veya manuel disable'da.
///
/// **Toggle:** `EmbeddingScorer.isEnabled` UserDefaults flag. Default true.
/// Kullanıcı Settings'ten kapatabilir → her zaman Tier 3 (Sprint 36 davranışı).
///
/// **Tasarım:** `NLEmbedding.sentenceEmbedding(for:)` global cache (process
/// lifetime); model load bir kere ~50ms. Inference query başına ~ms.
public enum EmbeddingScorer {
    /// **UserDefaults toggle anahtarı.** Settings UI bunu okur/yazar.
    /// `nil` ise default `true` (semantic matching aktif).
    public static let enabledDefaultsKey = "pixel.memory.semanticMatching"

    /// **Sprint 37:** İki metin arasında hybrid similarity. Dispatcher.
    ///
    /// `enableEmbedding == false` ise doğrudan Tier 3 (word Jaccard).
    /// Aksi halde dil-based tier seçimi.
    public static func score(
        _ a: String,
        _ b: String,
        enableEmbedding: Bool = currentSemanticToggle()
    ) -> Double {
        guard enableEmbedding else {
            return TextSimilarityScorer.score(a, b)
        }

        // Tier 1: İngilizce sentence embedding
        if let language = LanguageDetector.detectShared(a, b),
           language == .english,
           let cosine = sentenceCosine(a, b, language: .english) {
            return cosine
        }

        // Tier 2: Character n-gram (multilingual)
        let ngramScore = CharNGramScorer.score(a, b)
        if ngramScore > 0 {
            return ngramScore
        }

        // Tier 3: Word Jaccard fallback
        return TextSimilarityScorer.score(a, b)
    }

    /// **Sprint 37:** UserDefaults toggle değerini oku.
    /// Default `true` — semantic matching ON.
    public static func currentSemanticToggle() -> Bool {
        // UserDefaults.standard.object(forKey:) ile nil/false ayrımı.
        if let stored = UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool {
            return stored
        }
        return true
    }

    /// **Sprint 37:** Apple NLEmbedding ile sentence cosine similarity.
    /// Model yoksa veya vector hesaplanamazsa nil → caller fallback'e düşer.
    /// Public testlerden erişilebilir.
    public static func sentenceCosine(
        _ a: String,
        _ b: String,
        language: NLLanguage
    ) -> Double? {
        guard let embedding = sentenceEmbedding(for: language) else { return nil }
        guard let vecA = embedding.vector(for: a),
              let vecB = embedding.vector(for: b) else { return nil }
        return cosineSimilarity(vecA, vecB)
    }

    /// **Sprint 37:** Saf math — cosine similarity iki Double vektör arasında.
    /// Public test edilebilir. Sıfır magnitude → 0.0.
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = sqrt(magA) * sqrt(magB)
        guard denom > 0 else { return 0.0 }
        return dot / denom
    }

    // MARK: - Embedding lookup

    /// **Sprint 37:** `NLEmbedding.sentenceEmbedding(for:)` wrap'i.
    /// nil → o dil için Apple pretrained sentence embedding YOK (örn .turkish).
    ///
    /// **Cache stratejisi:** Apple framework'ü model load'ı internally amortize
    /// eder — ardışık çağrılar hızlı, ek user-space cache gereksiz. NLEmbedding
    /// Sendable değil; cross-thread reference güvenliği için her çağrı kendi
    /// thread'ında lookup yapar (Apple thread-safe lookup garanti eder).
    public static func sentenceEmbedding(for language: NLLanguage) -> NLEmbedding? {
        NLEmbedding.sentenceEmbedding(for: language)
    }
}
