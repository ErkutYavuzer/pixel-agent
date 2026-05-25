import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **Faz 5c follow-up (v0.2.52):** Per-element OCR crop için element rect'i
/// genişletir. `BadgePlacement.contentAware` + `.perElement` modunda her
/// element için OCR Vision pass'i bu genişletilmiş bölge üzerinde çalışır;
/// badge candidate position'ları + civar text bağlamı kapsanır.
///
/// **Geometri:** Element rect outside badge için badge boyutu kadar tüm
/// yönlerde genişler (`.topLeftOutside` badge'i element minX - badgeSize'a
/// taşar). Ek `padding` adjacent text'i de yakalamak için (badge'in yakınında
/// olabilecek label text).
///
/// **Bounds clamping:** Genişletilmiş rect image dışına taşarsa içeri çekilir;
/// nil dönmez (caller her zaman valid crop rect alır).
///
/// Saf math — Vision/View dependency yok.
public enum ElementRegionExpander {

    /// Default ek padding (pixel). Badge'in yakınındaki text'i de OCR
    /// kapsamasına almak için.
    public static let defaultPadding: CGFloat = 8

    /// Element rect'i badge boyutu + padding kadar tüm yönlerde genişletir,
    /// image bounds'a clamp eder. Sonuç crop rect'i için kullanılabilir
    /// (`CGImage.cropping(to:)`).
    ///
    /// **Defensive:** elementRect tamamen image dışındaysa nil — caller skip
    /// edebilir. Bu MarkLayout zaten benzer guard yapıyor; defensive duplicate.
    public static func expandedRect(
        elementRect: CGRect,
        badgeSize: CGFloat,
        imagePixelSize: CGSize,
        padding: CGFloat = defaultPadding
    ) -> CGRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }

        // Element + badge size (outside positions) + padding her yönde.
        let inset = badgeSize + padding
        let expanded = elementRect.insetBy(dx: -inset, dy: -inset)

        let imageRect = CGRect(
            x: 0, y: 0,
            width: imagePixelSize.width,
            height: imagePixelSize.height
        )
        let clamped = expanded.intersection(imageRect)

        // Tamamen image dışında veya negatif boyut → nil.
        guard !clamped.isNull, !clamped.isEmpty,
              clamped.width > 0, clamped.height > 0 else {
            return nil
        }
        return clamped
    }
}
