import XCTest
@testable import PixelMemory

/// **Sprint 36 (v0.2.63):** MemoryConsolidator duplicate detection + merge testleri.
final class MemoryConsolidatorTests: XCTestCase {
    func testIdenticalContentFlaggedAsDuplicate() {
        let now = Date()
        let a = MemoryEntry(category: .note, content: "Aynı metin tekrar yazılmış", createdAt: now)
        let b = MemoryEntry(category: .note, content: "Aynı metin tekrar yazılmış", createdAt: now.addingTimeInterval(60))
        let pairs = MemoryConsolidator.findDuplicates(in: [a, b])
        XCTAssertEqual(pairs.count, 1)
    }

    func testCompletelyDifferentNotFlagged() {
        let a = MemoryEntry(category: .note, content: "Kedi mavi köpek")
        let b = MemoryEntry(category: .note, content: "Araba otobüs uçak")
        let pairs = MemoryConsolidator.findDuplicates(in: [a, b])
        XCTAssertTrue(pairs.isEmpty)
    }

    func testDifferentCategoriesNotFlaggedEvenIfSimilar() {
        // Aynı content ama farklı kategori → muhtemelen niyetli; flag yok.
        let a = MemoryEntry(category: .profile, content: "Aynı metin burada")
        let b = MemoryEntry(category: .task, content: "Aynı metin burada")
        let pairs = MemoryConsolidator.findDuplicates(in: [a, b])
        XCTAssertTrue(pairs.isEmpty)
    }

    func testOrderByUpdatedAt() {
        let older = MemoryEntry(category: .note, content: "Aynı şey burada tekrar", createdAt: Date(timeIntervalSince1970: 1000))
        let newer = MemoryEntry(category: .note, content: "Aynı şey burada tekrar", createdAt: Date(timeIntervalSince1970: 2000))
        let pairs = MemoryConsolidator.findDuplicates(in: [newer, older])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.older.id, older.id)
        XCTAssertEqual(pairs.first?.newer.id, newer.id)
    }

    func testMergePreservesNewerContent() {
        let older = MemoryEntry(category: .note, content: "Eski versiyon metin")
        let newer = MemoryEntry(category: .note, content: "Yeni versiyon metin")
        let merged = MemoryConsolidator.merge(older: older, newer: newer)
        XCTAssertEqual(merged.id, newer.id)
        XCTAssertEqual(merged.content, "Yeni versiyon metin")
    }

    func testMergeUnionsTagsAndNormalizes() {
        let older = MemoryEntry(category: .task, content: "X", tags: ["Recipe", "review"])
        let newer = MemoryEntry(category: .task, content: "Y", tags: ["RECIPE", "improve"])
        let merged = MemoryConsolidator.merge(older: older, newer: newer)
        // recipe (dedup'lı), review, improve
        XCTAssertEqual(Set(merged.tags), Set(["recipe", "review", "improve"]))
    }

    func testMergeUpdatesUpdatedAt() {
        let earlierDate = Date(timeIntervalSinceNow: -100)
        let older = MemoryEntry(category: .note, content: "A", createdAt: earlierDate)
        let newer = MemoryEntry(category: .note, content: "B", createdAt: earlierDate.addingTimeInterval(50))
        let merged = MemoryConsolidator.merge(older: older, newer: newer)
        XCTAssertGreaterThan(merged.updatedAt, newer.updatedAt)
    }

    func testMergeKeepsEarliestCreatedAt() {
        let earliest = Date(timeIntervalSinceNow: -200)
        let older = MemoryEntry(category: .note, content: "A", createdAt: earliest)
        let newer = MemoryEntry(category: .note, content: "B", createdAt: earliest.addingTimeInterval(100))
        let merged = MemoryConsolidator.merge(older: older, newer: newer)
        XCTAssertEqual(merged.createdAt, earliest)
    }

    func testCustomThresholdRespected() {
        let a = MemoryEntry(category: .note, content: "PR review template kullan")
        let b = MemoryEntry(category: .note, content: "PR review template uygula")
        // Yüksek threshold (1.0) → flag yok
        let strictPairs = MemoryConsolidator.findDuplicates(in: [a, b], threshold: 1.0)
        XCTAssertTrue(strictPairs.isEmpty)
        // Düşük threshold (0.3) → flag
        let loosePairs = MemoryConsolidator.findDuplicates(in: [a, b], threshold: 0.3)
        XCTAssertEqual(loosePairs.count, 1)
    }
}
