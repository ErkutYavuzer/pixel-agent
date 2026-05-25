import SwiftUI
import PixelRemote

/// **Sprint 25 (v0.2.50):** Mac Paneli wire latency badge'in yanında inline
/// trend grafiği. `LatencySparkline.points` (Sources/PixelRemote, saf helper)
/// normalize edilmiş koordinatları döner; bu view SwiftUI `Path` ile çizer.
///
/// **Davranış:**
/// - Boş history → boş view (Path çizilmez).
/// - Tek nokta → tek nokta (helper (0.5, 0.5) döner — ortada).
/// - Çoklu nokta → polyline; uniform x spacing, y min-max'e göre normalize.
///
/// **Y flip:** Helper y=0 alt, y=1 üst döner; SwiftUI top-down (y=0 üst) için
/// `1 - point.y` ile flip edilir.
struct WireLatencySparklineView: View {
    let latencies: [Int]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let normalized = LatencySparkline.points(latencies: latencies)
            let cgPoints = normalized.map { point in
                CGPoint(
                    x: point.x * proxy.size.width,
                    y: (1.0 - point.y) * proxy.size.height
                )
            }

            Path { path in
                guard let first = cgPoints.first else { return }
                path.move(to: first)
                cgPoints.dropFirst().forEach { path.addLine(to: $0) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Latency trend grafiği")
    }
}
