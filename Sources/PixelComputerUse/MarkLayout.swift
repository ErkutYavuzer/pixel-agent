import CoreGraphics
import Foundation

/// **Faz 4 (ADR-0031):** Set-of-Mark annotation için saf koordinat çevirimi.
/// ScreenCaptureKit/AppKit bağımsız — unit-test friendly.
///
/// **Konvansiyon:**
/// - AX `kAXPositionAttribute` → top-left origin, screen-global, logical points.
/// - Capture edilmiş image → top-left origin, pixel cinsinden, retina-scaled.
/// - Caller bu helper'la her `UIElement.frame`'i image-içi pixel rect'ine çevirir.
enum MarkLayout {

    /// Element'in capture edilmiş image koordinatlarındaki (pixel) rect'i.
    ///
    /// - `elementFrame`: screen-global logical points (AX top-left).
    /// - `imageScreenOrigin`: image'in temsil ettiği bölgenin screen-global top-left
    ///   origin'i — `.window`/`.windowContent` için window.frame.origin (+offset).
    /// - `imageLogicalSize`: bölgenin logical points cinsinden boyutu.
    /// - `imagePixelSize`: image'in fiili pixel boyutu (retina scale dahil).
    ///
    /// Element bölgenin tamamen dışındaysa `nil` döner; kısmen dışındaysa rect
    /// olduğu gibi döner — renderer CG clipping ile kesin.
    static func computeMarkRect(
        elementFrame: CGRect,
        imageScreenOrigin: CGPoint,
        imageLogicalSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect? {
        guard imageLogicalSize.width > 0,
              imageLogicalSize.height > 0,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            return nil
        }

        // Logical points: element pos relative to image origin.
        let relX = elementFrame.origin.x - imageScreenOrigin.x
        let relY = elementFrame.origin.y - imageScreenOrigin.y

        // Bounding-box image dışında tamamen mi? (kısmi overlap kabul)
        guard relX + elementFrame.width > 0,
              relY + elementFrame.height > 0,
              relX < imageLogicalSize.width,
              relY < imageLogicalSize.height else {
            return nil
        }

        // Sıfır-boyutlu element: işaretlenebilir nokta sayılır — vermesi anlamsız.
        guard elementFrame.width > 0, elementFrame.height > 0 else {
            return nil
        }

        let scaleX = imagePixelSize.width / imageLogicalSize.width
        let scaleY = imagePixelSize.height / imageLogicalSize.height

        return CGRect(
            x: relX * scaleX,
            y: relY * scaleY,
            width: elementFrame.width * scaleX,
            height: elementFrame.height * scaleY
        )
    }
}
