import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// **Faz 5c (v0.2.51):** OCR text bounding box'larıyla `BadgePlacement`
/// scoring helper'ı. Vision framework'ünden gelen text region listesini
/// alır, her aday köşe için badge rect'inin text region'larla çakışma
/// alanını hesaplar, en az çakışanı döner.
///
/// Saf math — Vision dependency yok. Test edilebilir.
///
/// **Tasarım:** AX heuristic ("button → topRight outside") gerçek text
/// yerine *konvansiyon* tabanlı. OCR-based content-aware bunun ötesinde —
/// gerçek text bounding box'larıyla score'lar, kustom layout'larda da
/// doğru köşe bulur.
public enum OCRBadgePlacement {

    /// Default aday placement seti: 4 köşe (inside + outside). `.smartCorner`
    /// ve `.labelAware` da bu set'e expand edilirse OCRBadgePlacement
    /// kendileri de bu listede aday olabilir; ama "concrete" aday'lar
    /// yeterli — her biri pixel-tam rect döner.
    public static let defaultCandidates: [BadgePlacement] = [
        .topLeftInside,
        .topLeftOutside,
        .topRightInside,
        .topRightOutside,
    ]

    /// Bir badge rect'inin text region listesiyle toplam çakışma alanını
    /// hesaplar (pixel² cinsinden). Düşük değer = az çakışma = iyi yerleşim.
    public static func overlapArea(
        badgeRect: CGRect,
        textRegions: [CGRect]
    ) -> CGFloat {
        textRegions.reduce(0) { accumulated, textRect in
            let intersection = badgeRect.intersection(textRect)
            // `.intersection` boşsa `.null` (negatif boyut) döner — guard'la 0.
            if intersection.isNull || intersection.isEmpty { return accumulated }
            return accumulated + (intersection.width * intersection.height)
        }
    }

    /// Element için tüm aday placement'ları skorlar. `BadgeLayout.computeBadgeRect`
    /// ile her aday için badge rect üretilir; image bounds dışı kalan adaylar
    /// skor listesinden çıkarılır (bunlar zaten kullanılamaz).
    public static func scorePlacements(
        elementRect: CGRect,
        badgeSize: CGFloat,
        imagePixelSize: CGSize,
        textRegions: [CGRect],
        candidates: [BadgePlacement] = defaultCandidates
    ) -> [(placement: BadgePlacement, score: CGFloat)] {
        candidates.compactMap { placement in
            guard let badgeRect = BadgeLayout.computeBadgeRect(
                elementRect: elementRect,
                badgeSize: badgeSize,
                imagePixelSize: imagePixelSize,
                placement: placement
            ) else { return nil }
            let score = overlapArea(badgeRect: badgeRect, textRegions: textRegions)
            return (placement, score)
        }
    }

    /// En az çakışan aday placement'ı döner. Tüm adaylar image dışındaysa
    /// (compute nil dönerse) veya `candidates` boşsa nil. Eşitlik durumunda
    /// `candidates` array'indeki ilk aday kazanır (deterministic).
    public static func bestPlacement(
        elementRect: CGRect,
        badgeSize: CGFloat,
        imagePixelSize: CGSize,
        textRegions: [CGRect],
        candidates: [BadgePlacement] = defaultCandidates
    ) -> BadgePlacement? {
        let scored = scorePlacements(
            elementRect: elementRect,
            badgeSize: badgeSize,
            imagePixelSize: imagePixelSize,
            textRegions: textRegions,
            candidates: candidates
        )
        guard !scored.isEmpty else { return nil }
        // Stable min: aynı score'da array sırası galip (Array.min is not stable
        // by default — manuel reduce).
        var bestIndex = 0
        for i in 1..<scored.count {
            if scored[i].score < scored[bestIndex].score {
                bestIndex = i
            }
        }
        return scored[bestIndex].placement
    }
}
