import Foundation

/// **Sprint 36 (v0.2.63):** Embedding-free text similarity scorer.
///
/// MVP yaklaşımı: **Jaccard token similarity** — iki metni token kümesine
/// böl, `|intersection| / |union|` döndür. Hızlı, deterministic, dependency
/// yok. CoreML/SwiftNLP embedding modeli v0.3+ aday (model download +
/// inference overhead'i MVP scope'unu aştı).
///
/// Türkçe/İngilizce karışık metinlerde basit Latin tokenization yeterli;
/// gelecek revision'da TR-spesifik stopword filter eklenebilir.
///
/// **Sonuç aralığı:** `0.0` (hiç ortak token yok) - `1.0` (özdeş token kümesi).
/// Tek metin boş → `0.0`; ikisi de boş → `0.0` (defensive).
public enum TextSimilarityScorer {
    /// Minimum token uzunluğu — 1-2 karakterli token'lar (örn "ve", "a")
    /// genelde gürültü; filtre dışı bırakılır.
    public static let minTokenLength: Int = 3

    /// Türkçe + İngilizce ortak stopword listesi. Lowercased, alfabetik.
    /// Bu küçük set ile Jaccard skoru anlamlı içerik'e odaklanır.
    public static let stopwords: Set<String> = [
        // Türkçe
        "ama", "ben", "bir", "bize", "biz", "bu", "bunu", "çok", "daha",
        "değil", "diye", "için", "ile", "kadar", "mi", "ne", "olan",
        "olduğu", "olur", "şey", "siz", "şu", "var", "ve", "veya", "zaten",
        // İngilizce
        "and", "are", "but", "for", "from", "have", "into", "not", "the",
        "that", "this", "was", "were", "what", "when", "where", "which",
        "who", "with", "would", "your"
    ]

    /// **Sprint 36:** İki metin arasında Jaccard similarity hesapla.
    /// Tokenization Latin alphanumeric'e split, lowercase, stopword filter,
    /// min-length filter.
    public static func score(_ a: String, _ b: String) -> Double {
        let tokensA = tokenize(a)
        let tokensB = tokenize(b)

        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0.0 }

        let intersection = tokensA.intersection(tokensB)
        let union = tokensA.union(tokensB)

        guard !union.isEmpty else { return 0.0 }
        return Double(intersection.count) / Double(union.count)
    }

    /// **Sprint 36:** Metni Latin alphanumeric token'lara ayır, lowercase,
    /// stopword filter, min-length filter. Public — test edilebilir +
    /// future PlaybookLearner direct kullanımı için.
    public static func tokenize(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        // Latin alphanumeric'ten herhangi bir şey değilse split.
        // Türkçe karakterler (ç/ğ/ı/ö/ş/ü) Unicode letter'a girer.
        let scalars = lowered.unicodeScalars
        var tokens = Set<String>()
        var current = ""
        for scalar in scalars {
            if CharacterSet.letters.contains(scalar) ||
               CharacterSet.decimalDigits.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                appendIfValid(current, into: &tokens)
                current = ""
            }
        }
        if !current.isEmpty {
            appendIfValid(current, into: &tokens)
        }
        return tokens
    }

    private static func appendIfValid(_ token: String, into set: inout Set<String>) {
        guard token.count >= minTokenLength else { return }
        guard !stopwords.contains(token) else { return }
        set.insert(token)
    }
}
