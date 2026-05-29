import XCTest

@testable import PixelMemory

final class SkillRankerTests: XCTestCase {
    func testEmptyQueryReturnsEmpty() {
        let s = SkillEntry(title: "S", trigger: "t", steps: ["a"])
        XCTAssertTrue(SkillRanker.relevant(query: "", in: [s]).isEmpty)
    }

    func testEmptySkillsReturnsEmpty() {
        XCTAssertTrue(SkillRanker.relevant(query: "x", in: []).isEmpty)
    }

    func testUsageCountBreaksTieHigherFirst() {
        // Aynı trigger+title → eşit base score; usageCount boost sıralamayı belirler.
        let q = "her sabah raporu hazırla ve ekibe gönder"
        let low = SkillEntry(title: "R", trigger: q, steps: ["s"], usageCount: 0)
        let high = SkillEntry(title: "R", trigger: q, steps: ["s"], usageCount: 5)
        let result = SkillRanker.relevant(query: q, in: [low, high], limit: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.id, high.id, "yüksek usageCount önce gelmeli")
    }

    func testDeletedExcluded() {
        let q = "her sabah raporu hazırla ve ekibe gönder"
        let deleted = SkillEntry(title: "R", trigger: q, steps: ["s"], deleted: true)
        XCTAssertTrue(SkillRanker.relevant(query: q, in: [deleted]).isEmpty)
    }

    func testLimitRespected() {
        let q = "haftalık denetim raporu hazırla"
        let skills = (0..<4).map { SkillEntry(title: "S\($0)", trigger: q, steps: ["a"]) }
        XCTAssertEqual(SkillRanker.relevant(query: q, in: skills, limit: 2).count, 2)
    }

    func testFormatPromptStructure() {
        let s = SkillEntry(title: "PR review", trigger: "t", steps: ["fetch", "incele"], usageCount: 3)
        let out = SkillRanker.formatPrompt([s])
        XCTAssertTrue(out.contains("[İlgili kayıtlı skill'ler"))
        XCTAssertTrue(out.contains("\"PR review\""))
        XCTAssertTrue(out.contains("3× kullanıldı"))
        XCTAssertTrue(out.contains("1. fetch"))
        XCTAssertTrue(out.contains("2. incele"))
    }

    func testFormatPromptEmptyIsEmptyString() {
        XCTAssertEqual(SkillRanker.formatPrompt([]), "")
    }

    func testFormatPromptOmitsUsageWhenZero() {
        let s = SkillEntry(title: "S", trigger: "t", steps: ["a"], usageCount: 0)
        XCTAssertFalse(SkillRanker.formatPrompt([s]).contains("kullanıldı"))
    }
}
