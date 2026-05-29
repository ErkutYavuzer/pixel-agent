import XCTest

@testable import PixelMCPServer

/// Hermetic: yalnızca parametre validasyonu (store'a dokunmadan dönen error
/// path'leri). Happy-path SkillStore'a yazdığı için (default dir) burada test
/// edilmez — store davranışı `SkillStoreTests`'te kapsanır (MemoryTools deseni).
final class SkillToolsTests: XCTestCase {
    private func isError(_ result: JSONValue) -> Bool {
        result["isError"]?.boolValue ?? false
    }

    func testCreateSkillMissingTitleErrors() async {
        let r = await SkillTools.createSkill.handler(.object([
            "trigger": .string("t"), "steps": .array([.string("a")]),
        ]))
        XCTAssertTrue(isError(r))
    }

    func testCreateSkillMissingTriggerErrors() async {
        let r = await SkillTools.createSkill.handler(.object([
            "title": .string("T"), "steps": .array([.string("a")]),
        ]))
        XCTAssertTrue(isError(r))
    }

    func testCreateSkillEmptyStepsErrors() async {
        let r = await SkillTools.createSkill.handler(.object([
            "title": .string("T"), "trigger": .string("t"), "steps": .array([]),
        ]))
        XCTAssertTrue(isError(r))
    }

    func testUpdateSkillInvalidLineageErrors() async {
        let r = await SkillTools.updateSkill.handler(.object([
            "lineage_id": .string("not-a-uuid"), "title": .string("x"),
        ]))
        XCTAssertTrue(isError(r))
    }

    func testUpdateSkillMissingLineageErrors() async {
        let r = await SkillTools.updateSkill.handler(.object([:]))
        XCTAssertTrue(isError(r))
    }

    func testApplySkillInvalidLineageErrors() async {
        let r = await SkillTools.applySkill.handler(.object(["lineage_id": .string("nope")]))
        XCTAssertTrue(isError(r))
    }

    func testToolNamesStable() {
        XCTAssertEqual(SkillTools.createSkill.name, "create_skill")
        XCTAssertEqual(SkillTools.updateSkill.name, "update_skill")
        XCTAssertEqual(SkillTools.listSkills.name, "list_skills")
        XCTAssertEqual(SkillTools.applySkill.name, "apply_skill")
    }
}
