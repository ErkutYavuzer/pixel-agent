import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(Vision)
import Vision
#endif

/// **Faz 5c (v0.2.51):** Vision framework `VNRecognizeTextRequest` üzerinden
/// CGImage'da text bounding box'larını çıkarır. `BadgePlacement.contentAware`
/// ile `OCRBadgePlacement.bestPlacement` için input sağlar.
///
/// **Async pattern:** Vision API senkron `perform()` ile çalışır; ağır iş
/// background queue'ya dispatch'lenir, `CheckedContinuation` ile bekletilir.
/// Best-effort — hata durumunda boş array döner (caller `.labelAware`
/// fallback'ine düşer).
///
/// **Koordinat dönüşümü:** Vision normalize edilmiş `0...1` ve `bottom-left`
/// origin verir; image pixel space + top-left origin'e çevrilir (SoMRenderer
/// konvansiyonu).
///
/// **Performans:** `.fast` recognition level — typical retina screenshot
/// (~3000×1800px) ~100-300ms. `.accurate` mode 1-2 saniye sürebilir;
/// content-aware badge placement için aşırı.
public enum OCRTextDetector {

    /// Image'daki tüm text bölgelerini çıkarır. Boş array = hata veya text yok.
    /// Caller bu durumda `.labelAware` fallback'ine düşmeli.
    ///
    /// - Parameter image: PNG/JPEG decode edilmiş CGImage (CoreGraphics).
    /// - Returns: Text bounding box'ları — image pixel coords (origin top-left,
    ///   `0...image.width × 0...image.height`). Sıralama Vision'ın döndüğü
    ///   sırada (genelde okuma sırası, soldan-sağa yukarıdan-aşağıya).
    public static func detectTextRegions(in image: CGImage) async -> [CGRect] {
        #if canImport(Vision)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let regions = performDetection(on: image)
                continuation.resume(returning: regions)
            }
        }
        #else
        return []
        #endif
    }

    #if canImport(Vision)
    /// Senkron Vision performans — background queue'dan çağrılır.
    /// Hata durumunda boş array (best-effort).
    private static func performDetection(on image: CGImage) -> [CGRect] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else {
            return []
        }

        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)

        return observations.compactMap { observation -> CGRect? in
            // Vision'ın normalize box'ı: origin bottom-left, 0-1.
            let n = observation.boundingBox
            // Image pixel space, top-left origin'e çevir.
            let x = n.origin.x * imageW
            let y = (1.0 - n.origin.y - n.height) * imageH
            let w = n.width * imageW
            let h = n.height * imageH
            // Defensive: negatif boyut filtre (corrupt observation).
            guard w > 0, h > 0 else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
    #endif
}
