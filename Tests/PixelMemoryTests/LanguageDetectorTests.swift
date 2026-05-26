import XCTest
import NaturalLanguage
@testable import PixelMemory

/// **Sprint 37 (v0.2.64):** LanguageDetector edge cases.
final class LanguageDetectorTests: XCTestCase {

    func testDetectEmptyReturnsNil() {
        XCTAssertNil(LanguageDetector.detect(""))
    }

    func testDetectShortTextReturnsNil() {
        // Probe'da gözlemlendi: "Call me Erkut" kısa için TR döndürüyor —
        // bu yüzden min uzunluk eşiği (12) altında nil zorlanır.
        XCTAssertNil(LanguageDetector.detect("PR review"))
        XCTAssertNil(LanguageDetector.detect("Bu kısa"))
    }

    func testDetectLongEnglishReturnsEnglish() {
        let text = "The quick brown fox jumps over the lazy dog repeatedly."
        XCTAssertEqual(LanguageDetector.detect(text), .english)
    }

    func testDetectLongTurkishReturnsTurkish() {
        let text = "Bu uzun bir Türkçe örnek cümle örneğidir, dil tespiti çalışmalı."
        XCTAssertEqual(LanguageDetector.detect(text), .turkish)
    }

    func testDetectSharedSameLanguage() {
        let a = "The quick brown fox jumps over the lazy dog"
        let b = "A swift fox jumped over the sleeping dog yesterday"
        XCTAssertEqual(LanguageDetector.detectShared(a, b), .english)
    }

    func testDetectSharedDifferentLanguagesReturnsNil() {
        let en = "The quick brown fox jumps over the lazy dog repeatedly here"
        let tr = "Bu uzun bir Türkçe örnek cümle örneğidir burada"
        XCTAssertNil(LanguageDetector.detectShared(en, tr))
    }

    func testDetectSharedOneShortFallsToOther() {
        let short = "PR"
        let long = "The quick brown fox jumps over the lazy dog repeatedly"
        // short nil → other dön
        XCTAssertEqual(LanguageDetector.detectShared(short, long), .english)
    }

    func testDetectSharedBothShortReturnsNil() {
        XCTAssertNil(LanguageDetector.detectShared("PR", "OK"))
    }
}
