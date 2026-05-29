import XCTest

@testable import PixelMemory

final class SkillEntryTests: XCTestCase {
    func testDefaults() {
        let s = SkillEntry(title: "T", trigger: "when", steps: ["a"])
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.usageCount, 0)
        XCTAssertNil(s.supersedesID)
        XCTAssertFalse(s.deleted)
        XCTAssertEqual(s.origin, .explicit)
        XCTAssertEqual(s.updatedAt, s.createdAt)
    }

    func testCodableRoundTrip() throws {
        let s = SkillEntry(
            lineageID: UUID(), version: 2, supersedesID: UUID(),
            title: "PR review", trigger: "pr açarken", steps: ["1", "2"],
            tags: ["recipe"], usageCount: 3, origin: .auto
        )
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SkillEntry.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testWithNormalizedTrimsAndDedups() {
        let s = SkillEntry(
            title: "  Title  ", trigger: "  trig ",
            steps: ["  step1 ", "", "   ", "step2"],
            tags: ["  Recipe ", "recipe", "WORKFLOW"]
        ).withNormalized()
        XCTAssertEqual(s.title, "Title")
        XCTAssertEqual(s.trigger, "trig")
        XCTAssertEqual(s.steps, ["step1", "step2"])  // boş/whitespace adımlar elendi
        XCTAssertEqual(s.tags, ["recipe", "workflow"])  // trim+lowercase+dedup
    }

    func testOriginDisplayNameAndRawValue() {
        XCTAssertEqual(SkillOrigin.explicit.rawValue, "explicit")
        XCTAssertEqual(SkillOrigin.auto.rawValue, "auto")
        XCTAssertEqual(SkillOrigin.explicit.displayName, "Manuel")
        XCTAssertEqual(SkillOrigin.auto.displayName, "Otomatik")
        XCTAssertEqual(SkillOrigin.allCases.count, 2)
    }
}
