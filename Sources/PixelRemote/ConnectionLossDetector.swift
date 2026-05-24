import Foundation

/// Bağlantı durumu Bool transition'ını "kayıp event" olup olmadığına göre
/// sınıflandıran saf yardımcı (Sprint 5 — iOS pulse paralel).
///
/// Mac tarafında `ConnectionPillState`-tabanlı bir versiyon var (4 state);
/// iOS basit Bool olduğu için ayrı bir helper'la simetri kuruyoruz.
/// İkisi aynı semantiği taşır: yalnızca `true → false` geçişi pulse
/// tetikler. Reconnect veya kalıcı disconnected durumlar değişiklik üretmez.
public enum ConnectionLossDetector {

    /// `wasConnected=true, isConnected=false` → true.
    /// Diğer üç kombinasyon → false (idempotent re-render güvenli).
    public static func isLossEvent(wasConnected: Bool, isConnected: Bool) -> Bool {
        wasConnected && !isConnected
    }
}
