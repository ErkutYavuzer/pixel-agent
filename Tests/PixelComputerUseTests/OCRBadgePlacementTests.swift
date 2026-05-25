import Foundation
import XCTest

#if canImport(CoreGraphics)
import CoreGraphics
#endif

@testable import PixelComputerUse

/// **Faz 5c (v0.2.51):** OCR-based badge placement scoring helper testleri.
/// Vision dependency yok — text region listesi mock'lanır, saf math test edilir.
final class OCRBadgePlacementTests: XCTestCase {

    // MARK: - overlapArea

    func testOverlapAreaEmptyTextRegionsReturnsZero() {
        let badge = CGRect(x: 10, y: 10, width: 30, height: 30)
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: [])
        XCTAssertEqual(score, 0)
    }

    func testOverlapAreaDisjointRectsReturnsZero() {
        // Badge sol-üst köşede; text sağ-alt köşede — çakışma yok.
        let badge = CGRect(x: 0, y: 0, width: 20, height: 20)
        let text = CGRect(x: 100, y: 100, width: 50, height: 50)
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: [text])
        XCTAssertEqual(score, 0)
    }

    func testOverlapAreaFullyContainedReturnsFullArea() {
        // Text badge'i tamamen kaplıyor — score = badge alanı.
        let badge = CGRect(x: 10, y: 10, width: 20, height: 20) // 400 px²
        let text = CGRect(x: 0, y: 0, width: 100, height: 100)
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: [text])
        XCTAssertEqual(score, 400)
    }

    func testOverlapAreaPartialOverlap() {
        // Badge 10x10, text 10x10, ortak 5x5 = 25 px².
        let badge = CGRect(x: 0, y: 0, width: 10, height: 10)
        let text = CGRect(x: 5, y: 5, width: 10, height: 10)
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: [text])
        XCTAssertEqual(score, 25)
    }

    func testOverlapAreaMultipleTextRegionsSum() {
        // Badge 20x20; iki text rect — her biri 5x5 ortak alan = 25+25 = 50.
        let badge = CGRect(x: 0, y: 0, width: 20, height: 20)
        let texts = [
            CGRect(x: 0, y: 0, width: 5, height: 5),
            CGRect(x: 15, y: 15, width: 10, height: 10), // ortak 5x5 = 25
        ]
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: texts)
        XCTAssertEqual(score, 25 + 25)
    }

    func testOverlapAreaTouchingEdgeIsZero() {
        // Sıfır-alan kesişim — CGRect.intersection edge-touching durumunda
        // boş rect döner. score = 0.
        let badge = CGRect(x: 0, y: 0, width: 10, height: 10)
        let text = CGRect(x: 10, y: 10, width: 5, height: 5) // sadece köşe değiyor
        let score = OCRBadgePlacement.overlapArea(badgeRect: badge, textRegions: [text])
        XCTAssertEqual(score, 0)
    }

    // MARK: - scorePlacements

    func testScorePlacementsReturnsCandidatesWithinBounds() {
        // 100x100 element, ortada; image 1000x1000.
        let elementRect = CGRect(x: 450, y: 450, width: 100, height: 100)
        let imageSize = CGSize(width: 1000, height: 1000)
        let scored = OCRBadgePlacement.scorePlacements(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: [],
            candidates: OCRBadgePlacement.defaultCandidates
        )
        XCTAssertEqual(scored.count, 4, "Tüm 4 köşe image içinde olmalı")
        for (_, score) in scored {
            XCTAssertEqual(score, 0, "Text yoksa tüm score'lar 0")
        }
    }

    func testScorePlacementsFiltersOutOfBoundsCandidates() {
        // Element image'in sol-üst köşesinde — topLeftOutside taşar (badge
        // negatif koordinatlara gider, clamping yine içeri çekebilir).
        // Bu test her durumda compute nil dönerse filtreleneceğini doğrular.
        let elementRect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let imageSize = CGSize(width: 100, height: 100)
        let scored = OCRBadgePlacement.scorePlacements(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: [],
            candidates: [.topLeftInside, .topLeftOutside, .topRightInside, .topRightOutside]
        )
        // En azından bir candidate döner (clamping image bounds'a çeker).
        XCTAssertGreaterThan(scored.count, 0)
    }

    // MARK: - bestPlacement

    func testBestPlacementWithNoTextPicksFirstCandidate() {
        // Text yok → tüm score'lar 0 → ilk aday kazanır (deterministic).
        let elementRect = CGRect(x: 450, y: 450, width: 100, height: 100)
        let imageSize = CGSize(width: 1000, height: 1000)
        let best = OCRBadgePlacement.bestPlacement(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: [],
            candidates: [.topLeftInside, .topRightOutside]
        )
        XCTAssertEqual(best, .topLeftInside,
            "Eşit score'da defaultCandidates'in ilk elemanı (deterministic)")
    }

    func testBestPlacementAvoidsTextOverlap() {
        // Button gibi geniş element (200x40); sol-üst köşesinde text bbox var.
        // → topLeftInside text ile çakışır, sağ köşeler temiz olmalı.
        let elementRect = CGRect(x: 100, y: 100, width: 200, height: 40)
        let imageSize = CGSize(width: 1000, height: 1000)
        // Element'in sol-üst köşesinde geniş text bbox (element içinde).
        let textRegions = [
            CGRect(x: 100, y: 100, width: 50, height: 40), // sol kısım metin
        ]
        let best = OCRBadgePlacement.bestPlacement(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: textRegions,
            candidates: [.topLeftInside, .topRightInside, .topLeftOutside, .topRightOutside]
        )
        // topLeftInside text ile çakışır; sağ veya outside seçilmeli.
        XCTAssertNotEqual(best, .topLeftInside,
            "Text sol kısımda → topLeftInside skip; sağ köşe seçilmeli")
    }

    func testBestPlacementPicksMinimumScore() {
        // Element 200x40; 3 candidate'tan birinde tam çakışma var.
        // Diğer iki candidate'ın score'u 0, biri çakışır — kazanan minimum.
        let elementRect = CGRect(x: 100, y: 100, width: 200, height: 40)
        let imageSize = CGSize(width: 1000, height: 1000)
        // topLeftInside badge: (100, 100, 36, 36). Bu alanı kaplayan text.
        let textRegions = [
            CGRect(x: 100, y: 100, width: 36, height: 36), // tam topLeftInside
        ]
        let best = OCRBadgePlacement.bestPlacement(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: textRegions,
            candidates: [.topLeftInside, .topRightInside]
        )
        XCTAssertEqual(best, .topRightInside,
            "topLeftInside tam çakışma (1296) > topRightInside (0)")
    }

    func testBestPlacementEmptyCandidatesReturnsNil() {
        let best = OCRBadgePlacement.bestPlacement(
            elementRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            badgeSize: 5,
            imagePixelSize: CGSize(width: 100, height: 100),
            textRegions: [],
            candidates: []
        )
        XCTAssertNil(best)
    }

    func testBestPlacementStableTieBreaking() {
        // Eşit score'da array sırası galip (manuel min loop).
        let elementRect = CGRect(x: 200, y: 200, width: 100, height: 100)
        let imageSize = CGSize(width: 1000, height: 1000)
        let result1 = OCRBadgePlacement.bestPlacement(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: [],
            candidates: [.topRightInside, .topLeftInside]
        )
        XCTAssertEqual(result1, .topRightInside, "İlk aday eşit score'da kazanır")

        let result2 = OCRBadgePlacement.bestPlacement(
            elementRect: elementRect,
            badgeSize: 36,
            imagePixelSize: imageSize,
            textRegions: [],
            candidates: [.topLeftInside, .topRightInside]
        )
        XCTAssertEqual(result2, .topLeftInside, "Sıra değişirse ilk aday değişir")
    }

    // MARK: - defaultCandidates

    func testDefaultCandidatesCoversFourCorners() {
        // Tüm 4 köşe inside + outside set'i — comprehensive default.
        let set = Set(OCRBadgePlacement.defaultCandidates)
        XCTAssertEqual(set.count, 4)
        XCTAssertTrue(set.contains(.topLeftInside))
        XCTAssertTrue(set.contains(.topLeftOutside))
        XCTAssertTrue(set.contains(.topRightInside))
        XCTAssertTrue(set.contains(.topRightOutside))
    }
}
