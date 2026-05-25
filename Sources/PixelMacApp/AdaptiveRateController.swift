import Foundation

/// **Sprint 21 (v0.2.46):** Stream rate adaptive controller. Mevcut interval +
/// son ölçülen send latency'sinden yeni interval önerir. iOS feedback yok —
/// Mac side latency-aware proxy: send (capture + JPEG + transport.send)
/// `interval * 0.5`'i aşıyorsa network/CPU yorgun → büyüt; `interval * 0.1`
/// altında ise rahat → küçült (kullanıcının `baseMs` tercihine kadar).
///
/// Saf math helper — Coordinator/View bağımsız, test edilebilir.
///
/// **Algoritma:**
/// - `latency > current * 0.5` → `current = min(maxMs, current * 1.5)`
///   (slow lane: backoff exponential, ama max-cap'li).
/// - `latency < current * 0.1` ve `current > baseMs` → `current = max(baseMs, current * 0.8)`
///   (rahat lane: hızlan baseMs'e kadar).
/// - Aksi halde `current` korunur (hysteresis — gereksiz osilasyon önler).
public enum AdaptiveRateController {

    /// Yeni interval önerisi. Tüm parametreler ms cinsinden.
    public static func nextInterval(
        currentMs: Int,
        lastSendLatencyMs: Int,
        baseMs: Int,
        minMs: Int = 250,
        maxMs: Int = 5000
    ) -> Int {
        // Defensive clamping — bozuk girdiyle çağrılırsa sınırla.
        let current = max(minMs, min(maxMs, currentMs))
        let base = max(minMs, min(maxMs, baseMs))
        let latency = max(0, lastSendLatencyMs)

        let backoffThreshold = current / 2
        let speedupThreshold = current / 10

        if latency > backoffThreshold {
            // Slow lane: 1.5x backoff, max-cap.
            return min(maxMs, Int(Double(current) * 1.5))
        }

        if latency < speedupThreshold && current > base {
            // Rahat lane: 0.8x speedup, base alt sınır.
            return max(base, Int(Double(current) * 0.8))
        }

        // Hysteresis zone: değişiklik yok.
        return current
    }
}
