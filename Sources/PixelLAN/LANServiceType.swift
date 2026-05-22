import Foundation

/// Bonjour servis bilgileri.
public enum LANServiceType {
    /// `_pixel-agent._tcp.local.` — RFC 6335'e uygun kısa isim (≤15 char, ASCII).
    public static let bonjour = "_pixel-agent._tcp"

    /// Bonjour'da `.local.` domain'i — IETF mDNS link-local.
    public static let domain = "local."

    /// Listener varsayılan port: 0 (OS atasın). Sabit port kullanıldığında collision riski.
    public static let defaultPort: UInt16 = 0

    /// TXT record alanları (bonjour service metadata):
    /// - `pk`: ed25519 public key base64 — pairing öncesi handshake doğrulaması için
    /// - `v`: protokol versiyonu (PixelRemote.protocolVersion)
    public enum TXTKey {
        public static let publicKey = "pk"
        public static let protocolVersion = "v"
    }
}
