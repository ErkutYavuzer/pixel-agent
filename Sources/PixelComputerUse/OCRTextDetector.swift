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
    /// - Parameter minConfidence: **v0.2.54:** 0.0-1.0 arası eşik; bu değerin
    ///   altındaki observations filter. Default 0.0 (Sprint 26 davranışı).
    /// - Returns: Text bounding box'ları — image pixel coords (origin top-left,
    ///   `0...image.width × 0...image.height`). Sıralama Vision'ın döndüğü
    ///   sırada (genelde okuma sırası, soldan-sağa yukarıdan-aşağıya).
    public static func detectTextRegions(
        in image: CGImage,
        minConfidence: Double = 0.0
    ) async -> [CGRect] {
        #if canImport(Vision)
        // **v0.2.54 cancellation:** Task cancel edildiyse Vision pass'i hiç
        // başlatma — çağıran zaten sonucu beklemeyecek.
        if Task.isCancelled { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if Task.isCancelled {
                    continuation.resume(returning: [])
                    return
                }
                let regions = performDetection(
                    on: image,
                    cropOffset: .zero,
                    minConfidence: minConfidence
                )
                continuation.resume(returning: regions)
            }
        }
        #else
        return []
        #endif
    }

    /// **Faz 5c follow-up (v0.2.52):** Image'ın belirli bir bölgesinde OCR.
    /// Per-element crop mode için: element + badge alanı civarındaki text'i
    /// çıkar. Sonuç koordinatları image-global'a translate edilir (`cropRect`
    /// origin'i eklenerek), böylece caller union/filter işlemlerinde flat
    /// liste kullanabilir.
    ///
    /// - Parameter image: source CGImage.
    /// - Parameter cropRect: image-global pixel coords (top-left origin).
    ///   `ElementRegionExpander.expandedRect`'ten gelir. `image.cropping(to:)`
    ///   ile crop edilir.
    /// - Parameter minConfidence: **v0.2.54:** confidence eşiği (default 0.0).
    /// - Returns: Image-global text bbox'ları. Crop edilemezse veya OCR
    ///   başarısız → boş array (best-effort, Sprint 26 davranışı).
    public static func detectTextRegions(
        in image: CGImage,
        cropRect: CGRect,
        minConfidence: Double = 0.0
    ) async -> [CGRect] {
        #if canImport(Vision)
        // **v0.2.54 cancellation:** Cancellation check + crop skip.
        if Task.isCancelled { return [] }
        guard let cropped = image.cropping(to: cropRect) else {
            return []
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                if Task.isCancelled {
                    continuation.resume(returning: [])
                    return
                }
                let localRegions = performDetection(
                    on: cropped,
                    cropOffset: cropRect.origin,
                    minConfidence: minConfidence
                )
                continuation.resume(returning: localRegions)
            }
        }
        #else
        return []
        #endif
    }

    #if canImport(Vision)
    /// Senkron Vision performans — background queue'dan çağrılır.
    /// Hata durumunda boş array (best-effort). `cropOffset` ile crop modunda
    /// sonuç koordinatları image-global'a translate edilir (whole-image
    /// modunda `.zero` geçilir, no-op).
    /// **v0.2.54:** `minConfidence` 0.0-1.0 arası eşik — observation.confidence
    /// bu değerin altındaysa filter (`.fast` recognition noise azaltır).
    private static func performDetection(
        on image: CGImage,
        cropOffset: CGPoint,
        minConfidence: Double
    ) -> [CGRect] {
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
        let threshold = Float(minConfidence)

        return observations.compactMap { observation -> CGRect? in
            // **v0.2.54:** Low-confidence observations filter.
            guard observation.confidence >= threshold else { return nil }
            // Vision'ın normalize box'ı: origin bottom-left, 0-1.
            let n = observation.boundingBox
            // Image pixel space, top-left origin'e çevir.
            let x = n.origin.x * imageW + cropOffset.x
            let y = (1.0 - n.origin.y - n.height) * imageH + cropOffset.y
            let w = n.width * imageW
            let h = n.height * imageH
            // Defensive: negatif boyut filtre (corrupt observation).
            guard w > 0, h > 0 else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
    #endif
}
