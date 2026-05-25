import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **Faz 5c follow-up (v0.2.53):** Per-element OCR pass'lerini paralel
/// çalıştırmak için saf orchestration helper. Sprint 27 `.perElement` mode
/// sequential loop kullanıyordu (N pass = N × ~50-150ms wall-clock).
/// Sprint 28 `withTaskGroup` ile her crop rect için ayrı `Task` spawn'lar;
/// wall-clock max(per-element) seviyesine düşer.
///
/// **Saf orchestration:** Vision/CGImage dependency yok — `ocr` closure
/// generic async olarak verilir. Test'lerde mock closure ile parallel
/// execution + union doğrulanabilir; production'da
/// `OCRTextDetector.detectTextRegions(in:cropRect:)` wrap edilir.
///
/// **Ordering:** Union order Task tamamlanma sırasına bağlıdır — non-
/// deterministic. Caller order'a güvenmemeli; CGRect overlap scoring (Sprint
/// 26) sıraya duyarsız.
///
/// **Neural Engine caveat:** Apple Silicon Neural Engine multi-request
/// Vision'ı seri'ye düşürebilir; o durumda speedup ~1x'e yaklaşır ama
/// regresyon olmaz (worst case sequential). `.fast` recognition level CPU
/// path'ini kullanıyor olabilir, paralelizm avantajlıdır.
public enum ParallelCropDetection {

    /// Crop rect listesini paralel OCR pass'lerine dağıt, sonuçları union'la.
    ///
    /// - Parameter cropRects: image-global pixel coords. Caller
    ///   `ElementRegionExpander` ile hazırlar. Boş array → boş sonuç,
    ///   `withTaskGroup` çalışmaz.
    /// - Parameter ocr: closure her crop rect için text region dizisi döner.
    ///   Production: `OCRTextDetector.detectTextRegions(in:cropRect:)`
    ///   wrapper. Test: mock closure (deterministic veya gecikme injection).
    /// - Returns: tüm task sonuçlarının union'u (sıra non-deterministic).
    public static func detect(
        cropRects: [CGRect],
        ocr: @escaping @Sendable (CGRect) async -> [CGRect]
    ) async -> [CGRect] {
        guard !cropRects.isEmpty else { return [] }

        return await withTaskGroup(of: [CGRect].self) { group in
            for rect in cropRects {
                group.addTask { await ocr(rect) }
            }
            var union: [CGRect] = []
            for await regions in group {
                union.append(contentsOf: regions)
            }
            return union
        }
    }
}
