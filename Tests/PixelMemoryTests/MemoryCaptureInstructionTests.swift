import XCTest
@testable import PixelMemory

/// **Sprint 41 (v0.2.68):** MemoryCaptureInstruction assembly + UserDefaults
/// toggle testleri.
final class MemoryCaptureInstructionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.capture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - baseInstruction

    func testBaseInstructionMentionsAllCategories() {
        let inst = MemoryCaptureInstruction.baseInstruction
        XCTAssertTrue(inst.contains("profile"))
        XCTAssertTrue(inst.contains("preference"))
        XCTAssertTrue(inst.contains("task"))
        XCTAssertTrue(inst.contains("project"))
        XCTAssertTrue(inst.contains("save_memory"))
    }

    func testBaseInstructionMentionsRecipeTag() {
        XCTAssertTrue(MemoryCaptureInstruction.baseInstruction.contains("recipe"))
    }

    func testBaseInstructionHasNotificationLine() {
        XCTAssertTrue(MemoryCaptureInstruction.baseInstruction.contains("(Hafızaya kaydedildim"))
    }

    // MARK: - isAutoCaptureEnabled

    func testAutoCaptureDefaultsTrueWhenUnset() {
        XCTAssertTrue(MemoryCaptureInstruction.isAutoCaptureEnabled(defaults: defaults))
    }

    func testAutoCaptureRespectsFalse() {
        defaults.set(false, forKey: MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)
        XCTAssertFalse(MemoryCaptureInstruction.isAutoCaptureEnabled(defaults: defaults))
    }

    func testAutoCaptureRespectsTrue() {
        defaults.set(true, forKey: MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)
        XCTAssertTrue(MemoryCaptureInstruction.isAutoCaptureEnabled(defaults: defaults))
    }

    // MARK: - contextualPrefix

    func testContextualPrefixNilForNonIntent() {
        XCTAssertNil(MemoryCaptureInstruction.contextualPrefix(for: "Bugün hava güzel"))
    }

    func testContextualPrefixForIntentWithCategoryHint() {
        let prefix = MemoryCaptureInstruction.contextualPrefix(for: "Benim adım Erkut")
        XCTAssertNotNil(prefix)
        XCTAssertTrue(prefix?.contains("profile") ?? false)
        XCTAssertTrue(prefix?.contains("save_memory") ?? false)
    }

    func testContextualPrefixForPreferenceIntent() {
        let prefix = MemoryCaptureInstruction.contextualPrefix(for: "I prefer concise answers")
        XCTAssertNotNil(prefix)
        XCTAssertTrue(prefix?.contains("preference") ?? false)
    }

    // MARK: - assembleSystemPrompt

    func testAssembleWithoutPlaybookOrIntent() {
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "",
            userMessage: "Hello",
            defaults: defaults
        )
        // Auto-capture ON by default → at least baseInstruction
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("save_memory"))
    }

    func testAssembleWithPlaybookAndNoIntent() {
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "[Memory] Erkut user.",
            userMessage: "Code review",
            defaults: defaults
        )
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("[Memory]"))
        XCTAssertTrue(prompt!.contains("save_memory"))
        // Intent yok → contextualPrefix yok
        XCTAssertFalse(prompt!.contains("Capture niyet sinyali"))
    }

    func testAssembleWithIntentIncludesContextualPrefix() {
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "",
            userMessage: "Benim adım Erkut",
            defaults: defaults
        )
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("save_memory"))
        XCTAssertTrue(prompt!.contains("Capture niyet sinyali"))
        XCTAssertTrue(prompt!.contains("profile"))
    }

    func testAssembleDisabledStripsInstruction() {
        defaults.set(false, forKey: MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "[Memory] X",
            userMessage: "Benim adım Erkut",
            defaults: defaults
        )
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("[Memory]"))
        // Auto-capture OFF → no save_memory instruction, no contextual prefix
        XCTAssertFalse(prompt!.contains("save_memory"))
        XCTAssertFalse(prompt!.contains("Capture niyet sinyali"))
    }

    func testAssembleDisabledWithEmptyPlaybookReturnsNil() {
        defaults.set(false, forKey: MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "",
            userMessage: "Hello",
            defaults: defaults
        )
        XCTAssertNil(prompt, "Disabled + no playbook → no system prompt")
    }

    func testAssembleSectionsOrderedCorrectly() {
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "[PLAYBOOK]",
            userMessage: "Benim adım Erkut",
            defaults: defaults
        )!
        // Order: playbook → base → contextual
        let playbookRange = prompt.range(of: "[PLAYBOOK]")!
        let baseRange = prompt.range(of: "Memory capture talimatı")!
        let prefixRange = prompt.range(of: "Capture niyet sinyali")!
        XCTAssertLessThan(playbookRange.lowerBound, baseRange.lowerBound)
        XCTAssertLessThan(baseRange.lowerBound, prefixRange.lowerBound)
    }

    // MARK: - Sprint 51: skill section + skill intent

    func testAssembleIncludesSkillSectionInOrder() {
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "[PLAYBOOK]",
            skillSection: "[SKILLS]",
            userMessage: "Hello",
            defaults: defaults
        )!
        XCTAssertTrue(prompt.contains("[PLAYBOOK]"))
        XCTAssertTrue(prompt.contains("[SKILLS]"))
        // Sıra: playbook → skills → base
        let pb = prompt.range(of: "[PLAYBOOK]")!
        let sk = prompt.range(of: "[SKILLS]")!
        let base = prompt.range(of: "Memory capture talimatı")!
        XCTAssertLessThan(pb.lowerBound, sk.lowerBound)
        XCTAssertLessThan(sk.lowerBound, base.lowerBound)
    }

    func testAssembleDisabledKeepsSkillSection() {
        defaults.set(false, forKey: MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)
        let prompt = MemoryCaptureInstruction.assembleSystemPrompt(
            playbookSection: "",
            skillSection: "[SKILLS]",
            userMessage: "Hello",
            defaults: defaults
        )
        XCTAssertEqual(prompt, "[SKILLS]")  // disabled → sadece context section'lar
    }

    func testContextualPrefixSkillIntentMentionsCreateSkill() {
        let prefix = MemoryCaptureInstruction.contextualPrefix(
            for: "Deploy için şu adımları izle: 1. build 2. test"
        )
        XCTAssertNotNil(prefix)
        XCTAssertTrue(prefix?.contains("create_skill") ?? false)
    }
}
