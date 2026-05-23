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

    /// UI picker'ında listelenecek tipik modeller. Kullanıcı bunun dışında bir
    /// model isterse "Özel..." girişiyle elle yazar.
    public static func knownModels(for kind: CLIKind) -> [String] {
        switch kind {
        case .claude:
            // Anthropic Claude family (May 2026 itibarıyla)
            return [
                "claude-opus-4-7",
                "claude-opus-4-7-20251101",
                "claude-sonnet-4-7",
                "claude-sonnet-4-7-20251101",
                "claude-haiku-4-7",
            ]
        case .codex:
            // OpenAI Codex / GPT family
            return [
                "gpt-5.5",
                "gpt-5",
                "o3",
                "o3-mini",
                "o1",
                "o1-mini",
            ]
        case .gemini:
            // Google Gemini family — kullanıcı tercihi: 3.5 Flash + 3.1 Pro ilk
            // sırada (v0.2.23'te eklendi). 2.5/2.0/1.5 family fallback için
            // listede; CLI sürümü 3.x'i tanımıyorsa kullanıcı buradan dener.
            return [
                "gemini-3.5-flash",
                "gemini-3.1-pro",
                "gemini-2.5-flash",
                "gemini-2.5-pro",
                "gemini-2.0-flash",
                "gemini-2.0-flash-exp",
                "gemini-1.5-flash",
                "gemini-1.5-pro",
            ]
        }
    }
}
