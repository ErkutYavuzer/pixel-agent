import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **Faz 5 (v0.2.38):** Badge'in element rect'ine göre konumlandırılması için
/// saf helper. Strategy'ye göre 4 köşeden birine yerleştirir; image bounds'a
/// taşan badge'i içeri çeker (clamping).
///
/// View/SoMRenderer'dan ayrık → unit test friendly.
public enum BadgeLayout {

    /// Verilen element rect + badge boyutu + image pixel size için badge'in
    /// final konumunu hesaplar. Image bounds dışına taşmayı engeller
    /// (clamping). Eğer element rect tamamen image dışındaysa nil
    /// (caller MarkLayout'la zaten filtreliyor olmalı).
    public static func computeBadgeRect(
        elementRect: CGRect,
        badgeSize: CGFloat,
        imagePixelSize: CGSize,
        placement: BadgePlacement
    ) -> CGRect? {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return nil }
        guard badgeSize > 0 else { return nil }

        let resolved = resolveStrategy(
            placement: placement,
            elementRect: elementRect,
            badgeSize: badgeSize,
            imagePixelSize: imagePixelSize
        )

        let raw = rawBadgeRect(
            elementRect: elementRect,
            badgeSize: badgeSize,
            placement: resolved
        )

        return clampToImageBounds(rect: raw, imagePixelSize: imagePixelSize)
    }

    /// `.smartCorner` için: badge `.topLeftOutside` ile element üstüne taşar →
    /// rect sol-üst köşesinden bir badge yüksekliği yukarı + bir badge
    /// genişliği sola gider. Bu yer image bounds dışına taşıyorsa
    /// `.topLeftInside`'a fallback.
    static func resolveStrategy(
        placement: BadgePlacement,
        elementRect: CGRect,
        badgeSize: CGFloat,
        imagePixelSize: CGSize
    ) -> BadgePlacement {
        guard placement == .smartCorner else { return placement }

        let outsideTL = rawBadgeRect(
            elementRect: elementRect,
            badgeSize: badgeSize,
            placement: .topLeftOutside
        )
        let withinBounds = outsideTL.minX >= 0 && outsideTL.minY >= 0
        return withinBounds ? .topLeftOutside : .topLeftInside
    }

    /// Strategy'e göre clamping öncesi raw rect.
    static func rawBadgeRect(
        elementRect: CGRect,
        badgeSize: CGFloat,
        placement: BadgePlacement
    ) -> CGRect {
        let size = CGSize(width: badgeSize, height: badgeSize)
        switch placement {
        case .topLeftInside:
            return CGRect(origin: CGPoint(x: elementRect.minX, y: elementRect.minY), size: size)
        case .topLeftOutside:
            return CGRect(
                origin: CGPoint(x: elementRect.minX - badgeSize / 2, y: elementRect.minY - badgeSize / 2),
                size: size
            )
        case .topRightInside:
            return CGRect(
                origin: CGPoint(x: elementRect.maxX - badgeSize, y: elementRect.minY),
                size: size
            )
        case .topRightOutside:
            return CGRect(
                origin: CGPoint(x: elementRect.maxX - badgeSize / 2, y: elementRect.minY - badgeSize / 2),
                size: size
            )
        case .smartCorner, .labelAware:
            // resolveStrategy / LabelAwarePlacementResolver concrete bir case'e
            // çevirir; bu satıra düşmemeli. Defensive: topLeftInside fallback.
            return CGRect(origin: CGPoint(x: elementRect.minX, y: elementRect.minY), size: size)
        }
    }

    /// Image bounds dışına taşan rect'i içeri çeker (origin clamp). Boyut
    /// korunur — taşan kenardan çekilir. Hâlâ tamamen bounds dışındaysa nil.
    static func clampToImageBounds(rect: CGRect, imagePixelSize: CGSize) -> CGRect? {
        let maxX = max(0, imagePixelSize.width - rect.width)
        let maxY = max(0, imagePixelSize.height - rect.height)
        let clampedX = min(max(0, rect.origin.x), maxX)
        let clampedY = min(max(0, rect.origin.y), maxY)
        let clamped = CGRect(
            origin: CGPoint(x: clampedX, y: clampedY),
            size: rect.size
        )
        // Final visibility check — image içinde mi?
        guard clamped.maxX > 0,
              clamped.maxY > 0,
              clamped.minX < imagePixelSize.width,
              clamped.minY < imagePixelSize.height else {
            return nil
        }
        return clamped
    }
}
