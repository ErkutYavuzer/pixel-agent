import XCTest
@testable import PixelMemory

/// **Sprint 36 (v0.2.63):** PlaybookLearner ranking + recipe boost +
/// category weight testleri.
final class PlaybookLearnerTests: XCTestCase {
    func testEmptyEntriesReturnsEmpty() {
        let result = PlaybookLearner.relevant(query: "anything text", in: [], limit: 3)
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptyQueryReturnsEmpty() {
        let entry = MemoryEntry(category: .note, content: "some content here")
        let result = PlaybookLearner.relevant(query: "", in: [entry], limit: 3)
        XCTAssertTrue(result.isEmpty)
    }

    func testZeroLimitReturnsEmpty() {
        let entry = MemoryEntry(category: .note, content: "matching content here")
        let result = PlaybookLearner.relevant(query: "matching content", in: [entry], limit: 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testFiltersBelowThreshold() {
        let entries = [
            MemoryEntry(category: .note, content: "tamamen alakasız konu burada"),
            MemoryEntry(category: .note, content: "PR review template kullan"),
        ]
        let result = PlaybookLearner.relevant(query: "PR review template", in: entries, limit: 3, minSimilarity: 0.5)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.content, "PR review template kullan")
    }

    func testIgnoresDeletedEntries() {
        var deleted = MemoryEntry(category: .task, content: "PR review template kullan")
        deleted.deleted = true
        let active = MemoryEntry(category: .task, content: "PR review template kullan")
        let result = PlaybookLearner.relevant(query: "PR review template kullan", in: [deleted, active], limit: 3, minSimilarity: 0.3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, active.id)
    }

    func testLimitRespected() {
        let entries = (0..<10).map { i in
            MemoryEntry(category: .note, content: "ortak token kelimesi her metin örnek \(i)")
        }
        let result = PlaybookLearner.relevant(query: "ortak token kelimesi metin", in: entries, limit: 3, minSimilarity: 0.3)
        XCTAssertEqual(result.count, 3)
    }

    func testRecipeTagBoost() {
        // İki aynı içerikli entry, biri recipe tag'lı.
        // Aynı baseScore, recipe boost +0.1 → recipe önce gelir.
        let recipeEntry = MemoryEntry(category: .task, content: "PR review template kullan ortak", tags: ["recipe"])
        let plainEntry = MemoryEntry(category: .task, content: "PR review template kullan ortak", tags: ["other"])
        let result = PlaybookLearner.relevant(query: "PR review template kullan ortak", in: [plainEntry, recipeEntry], limit: 2, minSimilarity: 0.3)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.tags, ["recipe"])
    }

    func testCategoryWeightAffectsRanking() {
        // Aynı content, farklı kategori. profile (weight 4) > note (weight 0).
        let profile = MemoryEntry(category: .profile, content: "ortak metin içeriği burada")
        let note = MemoryEntry(category: .note, content: "ortak metin içeriği burada")
        let result = PlaybookLearner.relevant(query: "ortak metin içeriği burada", in: [note, profile], limit: 2, minSimilarity: 0.3)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.category, .profile)
    }

    // MARK: - formatPrompt

    func testFormatPromptEmpty() {
        XCTAssertEqual(PlaybookLearner.formatPrompt([]), "")
    }

    func testFormatPromptIncludesAllEntries() {
        let entries = [
            MemoryEntry(category: .profile, content: "Beni Erkut diye çağır"),
            MemoryEntry(category: .task, content: "PR review template", tags: ["recipe"]),
        ]
        let output = PlaybookLearner.formatPrompt(entries)
        XCTAssertTrue(output.contains("Kullanıcı geçmişinden"))
        XCTAssertTrue(output.contains("Beni Erkut diye çağır"))
        XCTAssertTrue(output.contains("PR review template"))
        XCTAssertTrue(output.contains("#recipe"))
        XCTAssertTrue(output.contains("(Profil)"))
        XCTAssertTrue(output.contains("(Görev)"))
    }

    // MARK: - Demo scenario

    func testDemoScenario_RecipeRetrieval() {
        // Kullanıcı "PR review template kullan" task'i save_memory ile recipe
        // olarak kaydetmiş. Sonra "PR review yapacağım" yazıyor — recipe
        // entry'si öne çıkmalı.
        let entries = [
            MemoryEntry(category: .profile, content: "Beni Erkut diye çağır"),
            MemoryEntry(category: .task, content: "PR review template kullan", tags: ["recipe"]),
            MemoryEntry(category: .note, content: "Hava bugün güzel"),
        ]
        let result = PlaybookLearner.relevant(query: "PR review template", in: entries, limit: 2, minSimilarity: 0.3)
        XCTAssertGreaterThanOrEqual(result.count, 1)
        XCTAssertEqual(result.first?.tags.first, "recipe")
    }
}
