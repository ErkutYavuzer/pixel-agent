import Foundation

/// **Sprint 41 (v0.2.68):** Kullanıcı mesajında "memory capture niyetli"
/// cümle var mı tespit eden saf helper.
///
/// Agent her cevap öncesi `save_memory` aracını çağırmayı düşünmek zorunda
/// kalmasın — capture niyetli mesajlarda system prompt'a contextual hint
/// eklenir, agent o anda explicit olarak "kullanıcı tercih bildiriyor" diye
/// uyarılır. Yanlış pozitiflerden kaçınmak için pattern listesi conservative.
///
/// **Türkçe ve İngilizce** pattern listesi — substring case-insensitive
/// match. Embedding gerekmiyor (Sprint 37'den ders: TR sentence embedding
/// yok; basit pattern hızlı + yüksek precision).
///
/// **Category hint:** Detect edilen pattern'a göre ilgili `MemoryCategory`
/// önerilir (profil/tercih/proje/görev) — agent doğru kategoriyi seçer.
public enum CaptureIntentDetector {
    /// Türkçe niyet keyword'leri — substring case-insensitive lookup.
    public static let turkishPatterns: [String] = [
        // profile (kimlik, ad)
        "benim adım", "ben x olarak", "diye çağır", "diye seslen",
        // preference (tercih, stil)
        "tercih ediyorum", "seviyorum", "tercih edersin", "tercihim",
        "her zaman", "asla", "kuralım", "kuralın",
        "bundan sonra", "şundan sonra", "şöyle yap", "böyle yap",
        // task (recipe)
        "şunu hatırla", "bunu hatırla", "şunu kaydet", "bunu kaydet",
        "her seferinde", "her keresinde", "yöntemim", "yöntemin",
        // project (aktif iş)
        "şu anki projem", "üzerinde çalıştığım", "şu an çalışıyorum",
    ]

    /// İngilizce niyet keyword'leri — kullanıcı karışık dil yazabilir.
    public static let englishPatterns: [String] = [
        // profile
        "my name is", "call me", "i'm called", "i am called",
        // preference
        "i prefer", "i like", "i don't like", "i hate",
        "always", "never", "from now on", "remember that",
        "rule:", "my rule",
        // task
        "remember this", "save this", "keep in mind",
        "every time", "whenever",
        // project
        "i'm working on", "my current project", "working on",
    ]

    /// **Sprint 41:** Mesajda niyet pattern var mı?
    /// Case-insensitive substring match. Hızlı + yüksek precision.
    public static func hasCaptureIntent(_ message: String) -> Bool {
        let lowered = message.lowercased()
        for pattern in turkishPatterns where lowered.contains(pattern) { return true }
        for pattern in englishPatterns where lowered.contains(pattern) { return true }
        return false
    }

    /// **Sprint 41:** Match olan pattern hangi kategori?
    /// Agent doğru `MemoryCategory.rawValue` ile `save_memory` çağırsın diye.
    /// nil ise capture niyet detect edilmedi.
    public static func detectCategory(_ message: String) -> MemoryCategory? {
        let lowered = message.lowercased()

        // Profile — kimlik, ad
        let profileKeywords = [
            "benim adım", "ben x olarak", "diye çağır", "diye seslen",
            "my name is", "call me", "i'm called", "i am called",
        ]
        if profileKeywords.contains(where: { lowered.contains($0) }) {
            return .profile
        }

        // Project — aktif iş bağlamı
        let projectKeywords = [
            "şu anki projem", "üzerinde çalıştığım", "şu an çalışıyorum",
            "i'm working on", "my current project", "working on",
        ]
        if projectKeywords.contains(where: { lowered.contains($0) }) {
            return .project
        }

        // Task — recipe / tekrarlayan iş
        let taskKeywords = [
            "şunu hatırla", "her seferinde", "her keresinde",
            "remember this", "save this", "every time", "whenever",
        ]
        if taskKeywords.contains(where: { lowered.contains($0) }) {
            return .task
        }

        // Preference — stil/ton tercihleri
        let preferenceKeywords = [
            "tercih ediyorum", "seviyorum", "tercih edersin", "tercihim",
            "her zaman", "asla", "kuralım", "kuralın",
            "bundan sonra", "şundan sonra", "şöyle yap", "böyle yap",
            "i prefer", "i like", "always", "never", "from now on",
            "remember that", "rule:", "my rule",
        ]
        if preferenceKeywords.contains(where: { lowered.contains($0) }) {
            return .preference
        }

        return nil
    }

    // MARK: - Skill intent (Sprint 51)

    /// **Sprint 51 (v0.2.80):** Çok-adımlı workflow ("skill") niyeti pattern'leri.
    /// `detectCategory`'nin tek-satır preference'ından farklı — burada
    /// **adım dizisi / iş akışı / rutin** sinyali aranır. `create_skill`
    /// aracının tetiklenmesi için contextual hint'e dönüşür.
    public static let skillTurkishPatterns: [String] = [
        "şu adımlar", "şu adımları", "şu iş akış", "iş akışı", "şu sırayla",
        "adım adım", "şu rutin", "şu prosedür", "her seferinde şunları",
        "şu workflow", "şu akışı izle", "şu şekilde sırayla",
    ]

    public static let skillEnglishPatterns: [String] = [
        "these steps", "the following steps", "step by step", "this workflow",
        "this routine", "this procedure", "in this order", "follow this flow",
        "every time do these", "whenever, do",
    ]

    /// **Sprint 51:** Mesaj çok-adımlı bir skill bildiriyor mu?
    /// Case-insensitive substring. Conservative — FP'den kaçın.
    public static func detectSkillIntent(_ message: String) -> Bool {
        let lowered = message.lowercased()
        for pattern in skillTurkishPatterns where lowered.contains(pattern) { return true }
        for pattern in skillEnglishPatterns where lowered.contains(pattern) { return true }
        return false
    }

    /// **Sprint 51:** Mesajdan kaba adım listesi çıkar (best-effort hint —
    /// gerçek adım çıkarımını LLM yapar). Öncelik: numaralı satırlar
    /// (`1.` / `1)` / `2-`) → satır bazlı; yoksa sıra bağlaçları
    /// (`önce`/`sonra`/`ardından`/`then`/`next`). Boş → adım bulunamadı.
    public static func extractStepHints(_ message: String) -> [String] {
        // 1) Numaralı işaretçileri yakala (satır içi de olabilir).
        let numberedPattern = #"(?:(?<=\s)|^)\d+\s*[.)\-]\s+"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern) {
            let ns = message as NSString
            let matches = regex.matches(in: message, range: NSRange(location: 0, length: ns.length))
            if matches.count >= 2 {
                var steps: [String] = []
                for (i, m) in matches.enumerated() {
                    let start = m.range.location + m.range.length
                    let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
                    let piece = ns.substring(with: NSRange(location: start, length: end - start))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !piece.isEmpty { steps.append(piece) }
                }
                if steps.count >= 2 { return steps }
            }
        }
        return []
    }
}
