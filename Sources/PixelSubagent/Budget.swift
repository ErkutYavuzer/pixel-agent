import Foundation

/// Bir subagent çalışmasının kaynak sınırları.
///
/// Yalnızca **wallclock süre** ve **çıktı byte sayısı** sınırlanır. Token sayma
/// CLI subprocess seviyesinde bizim için ulaşılır değil — CLI'lar kendi
/// quota'larını yönetiyor. Wallclock budget pratikte yeterli olmuştur.
public struct Budget: Sendable, Equatable {
    /// Maksimum wallclock süre (saniye). Aşıldığında stream cancel + `budgetExceeded`.
    public let maxDuration: TimeInterval

    /// Toplam çıktıda izin verilen maksimum byte. `nil` ise sınır yok.
    /// UTF-8 byte sayımı.
    public let maxOutputBytes: Int?

    public init(maxDuration: TimeInterval = 60, maxOutputBytes: Int? = nil) {
        precondition(maxDuration > 0, "Budget.maxDuration > 0 olmalı")
        if let b = maxOutputBytes {
            precondition(b > 0, "Budget.maxOutputBytes > 0 olmalı")
        }
        self.maxDuration = maxDuration
        self.maxOutputBytes = maxOutputBytes
    }

    /// 60 saniye, byte sınırı yok. Genel kullanım için makul varsayılan.
    public static let `default` = Budget(maxDuration: 60, maxOutputBytes: nil)

    /// Hızlı keşif/test için kısa budget: 10 saniye, 8 KB.
    public static let exploratory = Budget(maxDuration: 10, maxOutputBytes: 8 * 1024)
}
