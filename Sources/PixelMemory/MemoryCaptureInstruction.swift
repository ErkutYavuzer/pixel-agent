import Foundation

/// **Sprint 41 (v0.2.68):** Agent'a otomatik memory capture talimatı.
///
/// Sprint 36'da `MemoryStore + PlaybookLearner` MVP eklendi (manuel `save_memory`
/// MCP tool). Sprint 41 system prompt'a kalıcı bir talimat ekleyerek agent'ın
/// kendi pasif olarak capture etmesini sağlar.
///
/// Sistem prompt iki katmanlı:
/// 1. **`baseInstruction`** — her mesajda eklenen kalıcı talimat: "save_memory
///    aracın var; profil/tercih/görev/proje bilgisi yakaladığında çağır".
/// 2. **`contextualPrefix(for:)`** — kullanıcı mesajında `CaptureIntentDetector`
///    pattern bulduğunda ek uyarı: "kullanıcı şu anda muhtemelen X bildirimi
///    yapıyor; doğrudan save_memory'i değerlendir".
///
/// **Toggle:** `MemoryCaptureInstruction.isAutoCaptureEnabled` UserDefaults
/// flag. Default true. Kullanıcı kapatırsa instruction inject edilmez —
/// agent sadece eski Sprint 36 explicit user request ile capture eder.
public enum MemoryCaptureInstruction {
    public static let autoCaptureEnabledDefaultsKey = "pixel.memory.autoCaptureEnabled"

    /// **Sprint 41:** Kalıcı agent talimatı — her sistem prompt'unda
    /// görünür (PlaybookLearner output'tan sonra append edilir).
    public static let baseInstruction: String = """
    [Memory capture talimatı]
    Sende `save_memory` MCP aracı var. Kullanıcı şu durumlardan birini bildirirse, doğrudan ve sessizce bu aracı çağır (kullanıcıya "kaydedeyim mi?" sormadan):
    - Profil bilgisi: ad, rol, dil, lokasyon (örn "Beni Erkut diye çağır" → save_memory category=profile)
    - Tercih: iletişim stili, ton, format (örn "Kısa cevap tercih ederim" → category=preference)
    - Tekrarlayan iş örüntüsü ("recipe"): tag=recipe (örn "PR review için şu template'i kullan" → category=task, tags=["recipe"])
    - Aktif proje bağlamı (örn "Şu anki projem pixel-agent" → category=project)
    Bir kayıt yaparsan, ana cevabın içinde tek satırlık "(Hafızaya kaydedildim: …)" notu bırak — kullanıcı bilsin. Aynı bilgiyi tekrar kaydetme (search_memory ile önce kontrol et). Belirsizse kaydetme.
    """

    /// **Sprint 41:** UserDefaults toggle — auto capture açık mı?
    /// nil → default true.
    public static func isAutoCaptureEnabled(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: autoCaptureEnabledDefaultsKey) as? Bool {
            return stored
        }
        return true
    }

    /// **Sprint 41:** Kullanıcı mesajında niyet pattern bulunursa,
    /// system prompt'a eklenen contextual hint. nil → niyet yok, base
    /// instruction yeterli.
    public static func contextualPrefix(for userMessage: String) -> String? {
        let hasCapture = CaptureIntentDetector.hasCaptureIntent(userMessage)
        let hasSkill = CaptureIntentDetector.detectSkillIntent(userMessage)
        guard hasCapture || hasSkill else { return nil }
        var parts: [String] = []
        if hasCapture {
            let categoryHint = CaptureIntentDetector.detectCategory(userMessage)
                .map { "Önerilen kategori: `\($0.rawValue)`." } ?? ""
            parts.append("Kullanıcı şu anda muhtemelen kalıcı bir bilgi bildiriyor — `save_memory` aracını bu turda özellikle değerlendir. \(categoryHint)")
        }
        if hasSkill {
            // Sprint 51: çok-adımlı workflow niyeti → create_skill nudge.
            parts.append("Kullanıcı çok-adımlı, tekrarlanabilir bir workflow tarif ediyor olabilir — uygunsa `create_skill` aracını çağır (başlık + trigger + adımlar).")
        }
        return "[Capture niyet sinyali]\n" + parts.joined(separator: " ")
    }

    /// **Sprint 41:** Tam system prompt assembly — PlaybookLearner output
    /// (varsa) + baseInstruction + contextualPrefix (varsa).
    /// `playbookSection` `PlaybookLearner.formatPrompt()` çıktısı; boş ise
    /// boş string. Eğer auto-capture disabled ise sadece playbookSection
    /// döndürür (Sprint 36 davranışı).
    /// **Sprint 51 (v0.2.80):** `skillSection` (SkillRanker.formatPrompt çıktısı)
    /// eklendi. Section sırası: playbook → skills → baseInstruction → contextual.
    /// `skillSection` default "" → mevcut caller'lar değişmeden çalışır.
    public static func assembleSystemPrompt(
        playbookSection: String,
        skillSection: String = "",
        userMessage: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        let contextSections = [playbookSection, skillSection].filter { !$0.isEmpty }
        guard isAutoCaptureEnabled(defaults: defaults) else {
            return contextSections.isEmpty ? nil : contextSections.joined(separator: "\n\n")
        }
        var sections = contextSections
        sections.append(baseInstruction)
        if let prefix = contextualPrefix(for: userMessage) {
            sections.append(prefix)
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }
}
