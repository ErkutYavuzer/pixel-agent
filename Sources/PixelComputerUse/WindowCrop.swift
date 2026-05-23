import CoreGraphics
import Foundation

/// **Faz 3c (ADR-0030):** Window content-area crop hesabı — saf fonksiyon,
/// ScreenCaptureKit bağımsız, unit-test friendly.
///
/// Logical (point) → pixel (retina) çevrimi, üst-kenardan offset atma, kalan
/// logical frame hesabı bu enum altında izole edilir; `ScreenshotCapture`
/// gerçek CGImage cropping'i için kullanır.
enum WindowCrop {

    /// Bir pencerenin pixel-uzayında üst kenardan `titlebarOffsetPoints` kadarı
    /// atılmış crop rect'i. CGImage origin top-left olduğu için `y` = pixelOffset.
    ///
    /// `imageWidth/Height` SCScreenshotManager çıktısı (pixel cinsinden, retina
    /// dahil). `windowWidth/Height` logical points cinsinden. Scale factor
    /// `imageWidth / windowWidth` (Retina display'de ≈ 2).
    ///
    /// Eğer `titlebarOffsetPoints` window yüksekliğine eşit veya büyükse `nil`
    /// — caller fallback davranır.
    static func computeCropRect(
        imageWidth: Int,
        imageHeight: Int,
        windowWidth: Double,
        windowHeight: Double,
        titlebarOffsetPoints: Double
    ) -> CGRect? {
        guard windowHeight > 0,
              windowWidth > 0,
              titlebarOffsetPoints >= 0,
              titlebarOffsetPoints < windowHeight else {
            return nil
        }
        // Vertical scale factor (image height per logical point).
        let scaleY = Double(imageHeight) / windowHeight
        let pixelOffset = (titlebarOffsetPoints * scaleY).rounded()
        let pixelHeight = Double(imageHeight) - pixelOffset
        return CGRect(
            x: 0,
            y: pixelOffset,
            width: Double(imageWidth),
            height: pixelHeight
        )
    }

    /// Crop sonrası **logical** frame — orijinal pencere frame'inin üst kenardan
    /// `titlebarOffsetPoints` kadar küçültülmüş hali. Caller'ın ScreenshotResult
    /// metadata'sında verdiği logical_frame için kullanılır.
    static func computeLogicalFrame(
        windowFrame: CGRect,
        titlebarOffsetPoints: Double
    ) -> CGRect {
        let clampedOffset = max(0, min(titlebarOffsetPoints, windowFrame.height))
        return CGRect(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y + clampedOffset,
            width: windowFrame.size.width,
            height: max(0, windowFrame.size.height - clampedOffset)
        )
    }
}
