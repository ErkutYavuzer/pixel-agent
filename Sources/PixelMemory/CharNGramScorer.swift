import Foundation

/// **Sprint 37 (v0.2.64):** Character n-gram Jaccard similarity scorer.
///
/// **Niçin?** Sprint 36 `TextSimilarityScorer` (word Jaccard) Türkçe gibi
/// dillerde morfolojik benzerlikleri yakalayamıyordu — "Erkut" + "Erkut'a"
/// farklı token sayılır. Apple `NLEmbedding` sadece İngilizce sentence
/// embedding sağlıyor (Türkçe word/sentence destek YOK). CoreML multilingual
/// model bundle'a 135MB+ ekler.
///
/// **Çözüm:** Character n-gram (n=3 default) — metni karakter trigram set'ine
/// böl, Jaccard. Morfolojik suffix'ler ortak trigram paylaşır:
/// - "erkut" → {"erk", "rku", "kut"}
/// - "erkut'a" → {"erk", "rku", "kut", "ut'", "t'a"}
/// - intersection = 3, union = 5, similarity = 0.6
///
/// **Zero-cost multilingual** — Apple framework dep yok, saf string. 50+ dil
/// (Latin, Cyrillic, Greek, hatta CJK karakter bazında çalışır).
///
/// **Performans:** O(N) tokenization + O(|A|+|B|) Jaccard = sub-millisecond
/// her metin çifti. 500 entry × ~0.1ms = 50ms toplam tarama.
public enum CharNGramScorer {
    /// Default n=3 trigram — kısa metinler için optimal. n=2 çok gürültülü
    /// (her kelime çakışır), n=4 çok seçici (kısa metin az gram üretir).
    public static let defaultN: Int = 3

    /// Minimum metin uzunluğu n'den az ise tek gram olarak metnin kendisi
    /// kullanılır (defensive padding yerine).
    public static let minTextLength: Int = 1

    /// **Sprint 37:** İki metin arasında character n-gram Jaccard similarity.
    ///
    /// - Both empty / boş gram set → 0.0
    /// - Identical → 1.0
    /// - Tek bir tarafta gram yok → 0.0
    ///
    /// Lowercased; whitespace n-gram'a dahil (boşluk bilgisi anlamlıdır).
    public static func score(_ a: String, _ b: String, n: Int = defaultN) -> Double {
        let gramsA = ngrams(of: a, n: n)
        let gramsB = ngrams(of: b, n: n)
        guard !gramsA.isEmpty, !gramsB.isEmpty else { return 0.0 }
        let intersection = gramsA.intersection(gramsB)
        let union = gramsA.union(gramsB)
        guard !union.isEmpty else { return 0.0 }
        return Double(intersection.count) / Double(union.count)
    }

    /// **Sprint 37:** Metni karakter n-gram set'ine ayır.
    /// Lowercased + whitespace included (anlamlı bilgi). Public — test'lerden
    /// erişilebilir, future scoring algoritmaları için yeniden kullanılabilir.
    public static func ngrams(of text: String, n: Int = defaultN) -> Set<String> {
        let lowered = text.lowercased()
        let chars = Array(lowered)
        guard chars.count >= minTextLength else { return [] }
        // Metin n'den kısaysa kendisi tek gram
        guard chars.count >= n else { return [String(lowered)] }
        var set = Set<String>()
        // Sliding window
        for i in 0...(chars.count - n) {
            let gram = String(chars[i..<(i+n)])
            set.insert(gram)
        }
        return set
    }
}
