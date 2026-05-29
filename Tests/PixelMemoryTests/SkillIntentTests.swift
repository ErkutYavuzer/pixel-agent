import XCTest

@testable import PixelMemory

final class SkillIntentTests: XCTestCase {
    func testDetectSkillIntentTurkish() {
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("PR review için şu adımları izle"))
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("Bunu adım adım şöyle yap"))
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("Deploy için şu iş akışını kullan"))
    }

    func testDetectSkillIntentEnglish() {
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("Follow these steps every release"))
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("Do it step by step"))
        XCTAssertTrue(CaptureIntentDetector.detectSkillIntent("Run this workflow before merging"))
    }

    func testDetectSkillIntentNegative() {
        XCTAssertFalse(CaptureIntentDetector.detectSkillIntent("Bugün hava nasıl?"))
        XCTAssertFalse(CaptureIntentDetector.detectSkillIntent("What is the capital of France?"))
    }

    func testExtractStepHintsNumbered() {
        let msg = "Şöyle yap:\n1. repoyu çek\n2. testleri koştur\n3. PR aç"
        let steps = CaptureIntentDetector.extractStepHints(msg)
        XCTAssertEqual(steps, ["repoyu çek", "testleri koştur", "PR aç"])
    }

    func testExtractStepHintsParenStyle() {
        let steps = CaptureIntentDetector.extractStepHints("1) fetch 2) review 3) merge")
        XCTAssertEqual(steps, ["fetch", "review", "merge"])
    }

    func testExtractStepHintsNoneWhenUnstructured() {
        XCTAssertTrue(CaptureIntentDetector.extractStepHints("sadece bir şeyler yap").isEmpty)
        // Tek numaralı işaret yeterli değil (en az 2 gerekir).
        XCTAssertTrue(CaptureIntentDetector.extractStepHints("1. tek adım").isEmpty)
    }
}
