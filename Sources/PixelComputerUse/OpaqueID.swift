import Foundation

/// **Faz 3a:** `UIElement.opaqueID` serileştirme — re-resolve için stable handle.
///
/// Format:
/// ```
/// <bundleID>|<role>[:<discriminator>]|<role>[:<discriminator>]|...
/// ```
///
/// - `bundleID` boş ise (`""`) frontmost application'a referans.
/// - `discriminator`: identifier > title (varsa). `|` ve `:` karakterleri
///   `\u{1}` ve `\u{2}` ile escape edilir (encoder'da; decoder unescape).
///
/// Örnek:
/// ```
/// com.apple.Safari|AXApplication|AXWindow:Welcome|AXToolbar|AXButton:Sign In
/// ```
///
/// AX-bağımsız — pure value transform; test'te direkt kullanılır.
enum OpaqueID {

    /// Tek path adımı: role + opsiyonel discriminator (identifier veya title).
    struct Step: Sendable, Equatable, Hashable {
        let role: String
        let discriminator: String?
    }

    /// Parse sonucu.
    struct Parsed: Sendable, Equatable {
        let bundleID: String?  // nil = frontmost (encoder'da boş string olarak yazılır)
        let path: [Step]
    }

    // MARK: - Encode

    /// `bundleID + path + discriminators` → opaqueID string.
    ///
    /// `discriminators` `path` ile aynı uzunlukta; her index için o adımın
    /// discriminator'ı (nil = role yeter).
    static func encode(bundleID: String?, path: [String], discriminators: [String?]) -> String {
        var parts: [String] = [escape(bundleID ?? "")]
        let count = min(path.count, discriminators.count)
        for i in 0..<count {
            let role = path[i]
            if let disc = discriminators[i], !disc.isEmpty {
                parts.append("\(escape(role)):\(escape(disc))")
            } else {
                parts.append(escape(role))
            }
        }
        return parts.joined(separator: "|")
    }

    // MARK: - Decode

    /// opaqueID string → Parsed. Geçersiz format ise nil.
    static func decode(_ raw: String) -> Parsed? {
        let segments = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 1 else { return nil }

        let bundleEscaped = segments[0]
        let bundle = unescape(bundleEscaped)
        let bundleID: String? = bundle.isEmpty ? nil : bundle

        var path: [Step] = []
        for raw in segments.dropFirst() {
            // role[:discriminator]
            // Sadece ilk `:`'a kadar split (discriminator içinde `:` olabilir;
            // escape edilmiş olarak gelir, unescape'le çözülür).
            if let colonRange = raw.range(of: ":") {
                let role = unescape(String(raw[..<colonRange.lowerBound]))
                let disc = unescape(String(raw[colonRange.upperBound...]))
                path.append(Step(role: role, discriminator: disc.isEmpty ? nil : disc))
            } else {
                path.append(Step(role: unescape(raw), discriminator: nil))
            }
        }

        // Boş path = sadece bundleID; resolve edilmez ama format geçerli.
        return Parsed(bundleID: bundleID, path: path)
    }

    // MARK: - Escape

    /// `|` ve `:` ayraçlar — değerlerde geçerse `\u{1}` ve `\u{2}` placeholder'a çevir.
    /// Unicode escape değil; control character substitusyonu yeterli.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\u{1}")
            .replacingOccurrences(of: ":", with: "\u{2}")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1}", with: "|")
            .replacingOccurrences(of: "\u{2}", with: ":")
    }
}
