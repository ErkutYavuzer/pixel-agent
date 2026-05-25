import Foundation

/// **Sprint 11 (v0.2.36):** ConnectionLostBanner countdown display için
/// saf formatter. View'dan ayrık → gelecekte iOS test target eklenirse
/// doğrudan test edilebilir.
///
/// `nextAt` `nil` → "Yeniden bağlanılıyor…" (bağlanmıyor veya in-flight).
/// `nextAt > now` → "X sn sonra tekrar deneme…" (saniye cinsinden ceil).
/// `nextAt <= now` → "Bağlanılıyor…" (sleep bitti, sıra establishConnection'da).
enum ReconnectCountdownFormatter {
    static let idleMessage = "Bağlantı koptu. Yeniden bağlanılıyor…"
    static let connectingMessage = "Bağlanılıyor…"

    /// `nextAt` parametresine göre banner text'i.
    static func message(nextAt: Date?, now: Date = Date()) -> String {
        guard let nextAt else { return idleMessage }
        let remaining = nextAt.timeIntervalSince(now)
        if remaining <= 0 { return connectingMessage }
        let seconds = Int(remaining.rounded(.up))
        return "\(seconds) sn sonra tekrar deneme…"
    }
}
