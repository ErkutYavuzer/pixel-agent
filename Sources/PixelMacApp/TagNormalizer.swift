import Foundation

/// Sprint 7 (B2): Tag input → kanonik form.
///
/// Kurallar:
/// - Whitespace trim
/// - Lowercase (Türkçe locale-independent — `lowercased()` Foundation default'u)
/// - Max length 30 char (UI overflow + sidecar dosya boyutu için makul)
/// - Empty after trim → reject (nil döner; caller skip)
///
/// Liste için:
/// - Tek tek normalize
/// - Reject'leri at
/// - Dedup (Set + sorted)
public enum TagNormalizer {
    public static let maxLength = 30

    /// Tek tag'i kanonik forma çevir; geçersizse nil.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength))
    }

    /// Liste için normalize: her bir öğeyi sanitize et, nil'leri at,
    /// dedup, alfabetik sırala. Sidecar'a yazılmadan önce çağrılır.
    public static func normalize(_ raws: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in raws {
            guard let normalized = normalize(raw) else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out.sorted()
    }
}
