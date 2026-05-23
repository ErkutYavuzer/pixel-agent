import Foundation

/// **v0.2.22:** Her CLI backend için bilinen model ID'leri kataloğu + UserDefaults
/// persistence anahtarları. UI model picker'ı catalog'dan listeyi alır.
///
/// Catalog statik — yeni model çıktığında bu dosya güncellenir. Kullanıcı
/// listede olmayan bir model'i "Özel..." girişiyle elle de yazabilir; o değer
/// UserDefaults'a yazılır ve `CLIBackend.defaultModelID` öncelik sırasıyla
/// kullanır: **UserDefaults > env (`PIXEL_<KIND>_MODEL`) > hardcoded fallback**.
public enum ModelCatalog {

    /// UserDefaults key prefix'i. Tam key: `pixel.model.claude`, `pixel.model.codex`,
    /// `pixel.model.gemini`.
    public static let userDefaultsKeyPrefix = "pixel.model"

    /// Verilen CLI için UserDefaults anahtarı.
    public static func userDefaultsKey(for kind: CLIKind) -> String {
        "\(userDefaultsKeyPrefix).\(kind.rawValue)"
    }

    /// UI picker'ında listelenecek tipik modeller. **En iyi/en güncel üstte.**
    /// Kullanıcı bunun dışında bir model isterse "Özel ID…" girişiyle elle yazar.
    ///
    /// **Claude:** CLI doc'undaki alias'lar (`opus`/`sonnet`/`haiku`) her zaman
    /// güncel sürüme resolve eder. Versionlu ID'ler belirli sürüme pinlemek için.
    ///
    /// **Codex / Gemini:** Alias sistemi yok; tam ID listeleniyor.
    public static func knownModels(for kind: CLIKind) -> [String] {
        switch kind {
        case .claude:
            // Alias'lar üstte — CLI 2.1.128 help'ten doğrulandı:
            //   "Provide an alias for the latest model (e.g. 'sonnet' or 'opus')"
            // Alias seçince kullanıcı her zaman güncel modele bağlanır.
            return [
                "opus",         // alias → güncel Opus
                "sonnet",       // alias → güncel Sonnet
                "haiku",        // alias → güncel Haiku
                "claude-opus-4-7",
                "claude-sonnet-4-7",
                "claude-haiku-4-7",
                "claude-opus-4-6",
                "claude-sonnet-4-6",
                "claude-haiku-4-6",
            ]
        case .codex:
            // OpenAI Codex / GPT family — en yeni/en güçlü üstte.
            return [
                "gpt-5.5",
                "gpt-5",
                "o3",
                "o3-mini",
                "o1",
                "o1-mini",
            ]
        case .gemini:
            // Google Gemini family — Pro variants > Flash same version (kalite > hız).
            return [
                "gemini-3.1-pro-preview",
                "gemini-3-pro-preview",
                "gemini-3-flash-preview",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.0-flash",
                "gemini-2.0-flash-exp",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
            ]
        }
    }
}
