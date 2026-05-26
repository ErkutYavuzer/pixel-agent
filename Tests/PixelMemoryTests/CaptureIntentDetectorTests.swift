import XCTest
@testable import PixelMemory

/// **Sprint 41 (v0.2.68):** CaptureIntentDetector pattern match + category
/// detection testleri.
final class CaptureIntentDetectorTests: XCTestCase {

    // MARK: - hasCaptureIntent: Türkçe patterns

    func testTurkishProfilePattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Benim adım Erkut"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Beni Erkut diye çağır"))
    }

    func testTurkishPreferencePattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Kısa cevap tercih ediyorum"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Her zaman Türkçe yaz"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Bundan sonra emoji kullanma"))
    }

    func testTurkishTaskPattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Şunu hatırla: PR review'lerde inline yorum"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Her seferinde önce test yaz"))
    }

    func testTurkishProjectPattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Şu anki projem pixel-agent"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Üzerinde çalıştığım kod base Swift"))
    }

    // MARK: - hasCaptureIntent: English patterns

    func testEnglishProfilePattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("My name is John"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Call me Sarah please"))
    }

    func testEnglishPreferencePattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("I prefer concise answers"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Always use TypeScript"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("From now on, no emojis"))
    }

    func testEnglishTaskPattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Remember this for next time"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Every time we work on PRs, do X"))
    }

    func testEnglishProjectPattern() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("I'm working on pixel-agent"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("My current project is X"))
    }

    // MARK: - hasCaptureIntent: negative cases

    func testCasualMessageNotCaptured() {
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent("Bugün hava güzel"))
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent("Bunun ne anlama geldiğini söyler misin?"))
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent("How does X work?"))
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent("Code review yapar mısın?"))
    }

    func testEmptyAndWhitespace() {
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent(""))
        XCTAssertFalse(CaptureIntentDetector.hasCaptureIntent("   "))
    }

    // MARK: - hasCaptureIntent: case insensitivity

    func testCaseInsensitive() {
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("MY NAME IS X"))
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent("Benim AdıM Erkut"))
    }

    // MARK: - detectCategory

    func testDetectProfileCategory() {
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Benim adım Erkut"), .profile)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("My name is John"), .profile)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Beni Erkut diye çağır"), .profile)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Call me Sarah"), .profile)
    }

    func testDetectPreferenceCategory() {
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Kısa cevap tercih ediyorum"), .preference)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("I prefer concise"), .preference)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Her zaman Türkçe"), .preference)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Always use TypeScript"), .preference)
    }

    func testDetectTaskCategory() {
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Şunu hatırla"), .task)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Remember this"), .task)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Her seferinde test yaz"), .task)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Every time we deploy"), .task)
    }

    func testDetectProjectCategory() {
        XCTAssertEqual(CaptureIntentDetector.detectCategory("Şu anki projem pixel-agent"), .project)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("I'm working on pixel-agent"), .project)
        XCTAssertEqual(CaptureIntentDetector.detectCategory("My current project is X"), .project)
    }

    func testDetectCategoryNilForNonIntent() {
        XCTAssertNil(CaptureIntentDetector.detectCategory("Bugün hava güzel"))
        XCTAssertNil(CaptureIntentDetector.detectCategory(""))
    }

    // MARK: - Demo regression

    /// Sprint 36 demo senaryosu — "Beni Erkut diye çağır" artık
    /// otomatik olarak profile category ile yakalanır.
    func testDemoRegressionErkut() {
        let msg = "Beni Erkut diye çağır"
        XCTAssertTrue(CaptureIntentDetector.hasCaptureIntent(msg))
        XCTAssertEqual(CaptureIntentDetector.detectCategory(msg), .profile)
    }
}
