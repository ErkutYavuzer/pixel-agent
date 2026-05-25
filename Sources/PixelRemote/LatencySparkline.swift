import Foundation

/// **Sprint 25 (v0.2.50):** Wire latency timeline grafiği için saf normalize
/// helper. iOS Mac Paneli badge'in yanında inline sparkline (son N frame'in
/// wire latency trendi) çizmek için kullanılır.
///
/// **Tasarım kararı:** Helper SwiftUI veya CoreGraphics'e bağımlı değil —
/// normalize edilmiş 0-1 koordinatlar döner. View katmanı `proxy.size`
/// ile çarpıp `CGPoint`'e çevirir ve Y'yi flip eder (SwiftUI top-down).
///
/// **Ring buffer:** `push(_:into:maxCount:)` ile son N latency tutulur.
/// Stream durunca caller buffer'ı temizler.
public enum LatencySparkline {

    /// Normalize edilmiş bir nokta (0-1 koordinatlar).
    /// - `x`: 0 = sol kenar, 1 = sağ kenar. Uniform spacing.
    /// - `y`: 0 = düşük latency (alt), 1 = yüksek latency (üst).
    ///   View katmanı (SwiftUI) `1 - y` ile flip eder (top-down ekrana).
    public struct NormalizedPoint: Sendable, Equatable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Latency dizisini normalize edilmiş noktalara çevir.
    /// - Empty array → boş; view path çizmez.
    /// - Tek değer → tek nokta `(0.5, 0.5)` (görsel olarak ortada).
    /// - Tüm değerler aynı → düz çizgi y=0.5 (range=0 div-by-zero korumalı).
    /// - Diğer: min latency → y=0; max latency → y=1; aralarda linear.
    ///
    /// Caller minimum/maksimum sabit eşik vermek isterse `minLatency`/
    /// `maxLatency` parametreleri ile override edebilir; o zaman değerler
    /// 0-1 dışına da çıkabilir (caller kendi clamp'lar).
    public static func points(
        latencies: [Int],
        minLatency: Int? = nil,
        maxLatency: Int? = nil
    ) -> [NormalizedPoint] {
        guard !latencies.isEmpty else { return [] }

        if latencies.count == 1 {
            return [NormalizedPoint(x: 0.5, y: 0.5)]
        }

        let minVal = minLatency ?? (latencies.min() ?? 0)
        let maxVal = maxLatency ?? (latencies.max() ?? minVal)
        let range = maxVal - minVal

        let n = latencies.count
        let xStep = 1.0 / Double(n - 1)

        return latencies.enumerated().map { i, latency in
            let x = Double(i) * xStep
            let y: Double
            if range <= 0 {
                // Tüm değerler aynı veya min > max (defensive) → orta hat.
                y = 0.5
            } else {
                y = Double(latency - minVal) / Double(range)
            }
            return NormalizedPoint(x: x, y: y)
        }
    }

    /// Ring buffer push: yeni latency'yi append et; max'i aşarsa baştan kırp.
    /// Caller her envelope'da çağırır; stream durunca buffer'ı `.removeAll()`
    /// ile temizler.
    public static func push(
        _ value: Int,
        into buffer: inout [Int],
        maxCount: Int
    ) {
        buffer.append(value)
        if buffer.count > maxCount {
            buffer.removeFirst(buffer.count - maxCount)
        }
    }
}
