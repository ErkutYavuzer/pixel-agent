import Foundation

/// **Sprint 29 (v0.2.54):** Wire latency sparkline rendering preferences —
/// kullanıcı UI'dan değiştirir (`@AppStorage`). Saf constants + clamping
/// helper; view layer'dan ayrı tutulur.
enum SparklinePreferences {
    /// UserDefaults key. `@AppStorage` tüm view'lar tarafından paylaşılır.
    static let widthKey = "pixel.sparkline.width"

    /// Default genişlik (pt). Sprint 25 hardcoded 80pt'in eşi — backward
    /// compatible "ilk kurulum" değeri.
    static let defaultWidth: Double = 80

    /// Slider alt sınır — çok dar olunca trend okunaksız.
    static let minWidth: Double = 40

    /// Slider üst sınır — Mac Paneli badge satırı taşmasın.
    static let maxWidth: Double = 160

    /// Out-of-range değerleri snap'le (defensive: bozuk UserDefaults
    /// veya legacy override).
    static func clamped(_ value: Double) -> Double {
        min(maxWidth, max(minWidth, value))
    }
}
