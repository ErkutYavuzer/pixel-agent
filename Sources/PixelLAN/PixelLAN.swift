/// Bonjour + Network.framework üzerinden Mac ↔ iOS arası **relay-bypass** LAN
/// transport'u. Cloudflare Worker'a uğramadan, doğrudan TCP üzerinden iletişim.
///
/// Faz 1 (bu modül): library + framing + Bonjour advertise/browse.
/// Faz 2 (gelecek): RemoteHost / RemoteSession entegrasyonu, otomatik fallback.
public enum PixelLAN {
    public static let version = "0.2.8"
}
