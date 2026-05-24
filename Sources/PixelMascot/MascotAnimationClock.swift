import CoreGraphics
import Foundation

/// Mascot view'ın zaman-bazlı animasyon dönüşümlerini hesaplayan saf
/// yardımcı (Sprint 5 — mascot polish).
///
/// SwiftUI'a bağımlı değil; `Foundation` + `CoreGraphics`. View tarafı
/// `TimelineView` ile her tick'te `time: Double` (saniye, monotonic)
/// vererek bu fonksiyonları çağırır. Test'ler hermetic — saf math.
public enum MascotAnimationClock {

    // MARK: - Idle bob

    /// Idle state için yavaş dikey nefes alma efekti.
    /// 4s periyot, ±1.5pt amplitude. `time` saniye, kümülatif (`Date()`'den
    /// app launch'a referans olabilir; mod periyot içeride sin alır).
    public static func idleOffset(time: Double) -> CGSize {
        let amplitude: CGFloat = 1.5
        let frequency: Double = 0.25  // 1/4 Hz = 4s period
        let y = amplitude * CGFloat(sin(time * 2 * .pi * frequency))
        return CGSize(width: 0, height: y)
    }

    // MARK: - Thinking wobble

    /// Thinking state için hafif yatay wobble — kafa sağa-sola hafifçe.
    /// 2s periyot, ±0.8pt amplitude.
    public static func thinkingOffset(time: Double) -> CGSize {
        let amplitude: CGFloat = 0.8
        let frequency: Double = 0.5  // 1/2 Hz = 2s period
        let x = amplitude * CGFloat(sin(time * 2 * .pi * frequency))
        return CGSize(width: x, height: 0)
    }

    // MARK: - Speaking mouth cycle

    /// Speaking state için ağız frame index'i — 0 (open) / 1 (closed)
    /// arası 5Hz'de değişir. `time × 5` → integer mod 2.
    public static func speakingFrameIndex(time: Double) -> Int {
        let cycle = Int(time * 5)
        return abs(cycle) % 2
    }

    // MARK: - Error shake (one-shot, decaying)

    /// Error state'e geçişte one-shot decaying sine shake.
    /// `elapsed` saniye cinsinden state geçişinden bu yana geçen süre.
    /// `0...0.5s` arasında hızla osilasyon, ondan sonra ≈0.
    public static func errorShakeOffset(elapsed: Double) -> CGSize {
        guard elapsed >= 0, elapsed <= 0.5 else { return .zero }
        let amplitude: CGFloat = 3.0
        let frequency: Double = 15  // 15 Hz — hızlı shake
        let decay: Double = max(0, 1.0 - elapsed / 0.5)
        let x = amplitude * CGFloat(sin(elapsed * 2 * .pi * frequency)) * CGFloat(decay)
        return CGSize(width: x, height: 0)
    }
}
