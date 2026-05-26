import Foundation
import NaturalLanguage

/// **Sprint 37 (v0.2.64):** Dil tespiti — `NLLanguageRecognizer` wrap'i.
///
/// **Probe ile gözlemlendi:** Kısa metinler (3-4 kelime) için
/// `NLLanguageRecognizer` güvenilmez — "Call me Erkut" için `.turkish`
/// döndürdü. Bu yüzden minimum karakter eşiği var (default 12) — eşik
/// altında nil döner, caller fallback'e düşer.
///
/// `EmbeddingScorer` bu sonuca göre tier seçer:
/// - `.english` → NLEmbedding sentence (yüksek kalite)
/// - diğer / nil → CharNGramScorer (multilingual morphology)
public enum LanguageDetector {
    /// Altında dil tespiti yapılmaz — özellikle kısa metinlerde
    /// NLLanguageRecognizer wrong-language bias gösteriyor.
    public static let minLengthForDetection: Int = 12

    /// **Sprint 37:** Metnin dominant dilini tespit et.
    /// nil → metin çok kısa veya dil belirlenemiyor.
    public static func detect(_ text: String) -> NLLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLengthForDetection else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let lang = recognizer.dominantLanguage else { return nil }
        // Yüksek confidence isteme — ama eski API'de hypotheses zorunlu, bu
        // pragmatik check (probe'da %50+ doğru gibi).
        return lang
    }

    /// **Sprint 37:** İki metinden ortak/dominant dili belirle. Query +
    /// content çiftinde tek kararlı dil tespiti için.
    /// Aynı sonuç → o dil; farklı → nil (caller fallback).
    public static func detectShared(_ a: String, _ b: String) -> NLLanguage? {
        let langA = detect(a)
        let langB = detect(b)
        guard let langA, let langB else { return langA ?? langB }
        return langA == langB ? langA : nil
    }
}
