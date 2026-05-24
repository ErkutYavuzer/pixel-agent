import Foundation

/// ed25519 base64-encoded public key'i okunabilir gruplara böler (B8).
///
/// Mac ↔ iOS arasında shared (PixelRemote her iki tarafta dep). Saf yardımcı —
/// herhangi bir ortamdan kullanılabilir, hermetik test edilebilir.
public enum PublicKeyFormatter {

    /// `pk` boşsa "—" döner. Aksi halde `groupSize` karakterli parçalara böler
    /// ve aralarına boşluk koyar — fingerprint görsel doğrulaması için.
    /// Default `groupSize = 8` (base64 anahtar ~43 char, 6 grup × 8 + 4 = okurluk).
    public static func format(_ pk: String, groupSize: Int = 8) -> String {
        guard !pk.isEmpty else { return "—" }
        guard groupSize > 0 else { return pk }
        var groups: [String] = []
        var i = pk.startIndex
        while i < pk.endIndex {
            let end = pk.index(i, offsetBy: groupSize, limitedBy: pk.endIndex) ?? pk.endIndex
            groups.append(String(pk[i..<end]))
            i = end
        }
        return groups.joined(separator: " ")
    }
}
