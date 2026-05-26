import XCTest
@testable import PixelMemory

/// **Sprint 37 (v0.2.64):** CharNGramScorer (n=3 trigram Jaccard) testleri.
final class CharNGramScorerTests: XCTestCase {

    // MARK: - ngrams helper

    func testNgramsEmptyText() {
        XCTAssertEqual(CharNGramScorer.ngrams(of: ""), [])
    }

    func testNgramsShorterThanN() {
        // "ab" (2 char) < n=3 → kendisi tek gram olarak
        let grams = CharNGramScorer.ngrams(of: "ab", n: 3)
        XCTAssertEqual(grams, ["ab"])
    }

    func testNgramsExactN() {
        // "abc" → tek gram
        XCTAssertEqual(CharNGramScorer.ngrams(of: "abc", n: 3), ["abc"])
    }

    func testNgramsSlidingWindow() {
        // "abcd" → {"abc", "bcd"}
        XCTAssertEqual(CharNGramScorer.ngrams(of: "abcd", n: 3), ["abc", "bcd"])
    }

    func testNgramsLowercases() {
        XCTAssertEqual(CharNGramScorer.ngrams(of: "ABCD", n: 3),
                       CharNGramScorer.ngrams(of: "abcd", n: 3))
    }

    func testNgramsIncludesWhitespace() {
        // "ab cd" 5 char → 3 grams: "ab ", "b c", " cd"
        let grams = CharNGramScorer.ngrams(of: "ab cd", n: 3)
        XCTAssertEqual(grams, ["ab ", "b c", " cd"])
    }

    func testNgramsTurkishCharacters() {
        let grams = CharNGramScorer.ngrams(of: "öğrenme", n: 3)
        XCTAssertTrue(grams.contains("öğr"))
        XCTAssertTrue(grams.contains("ğre"))
        XCTAssertTrue(grams.contains("ren"))
    }

    // MARK: - score

    func testScoreIdentical() {
        XCTAssertEqual(CharNGramScorer.score("merhaba", "merhaba"), 1.0)
    }

    func testScoreCompletelyDifferent() {
        XCTAssertEqual(CharNGramScorer.score("xyz", "abc"), 0.0)
    }

    func testScoreEmpty() {
        XCTAssertEqual(CharNGramScorer.score("", "abc"), 0.0)
        XCTAssertEqual(CharNGramScorer.score("abc", ""), 0.0)
    }

    func testScoreSymmetry() {
        let a = "merhaba dünya"
        let b = "dünya merhaba"
        XCTAssertEqual(CharNGramScorer.score(a, b), CharNGramScorer.score(b, a))
    }

    func testScorePartialOverlap() {
        // "erkut" + "erkut'a" — morfolojik suffix
        let s = CharNGramScorer.score("erkut", "erkut'a")
        // grams("erkut")   = {"erk", "rku", "kut"}                  → 3
        // grams("erkut'a") = {"erk", "rku", "kut", "ut'", "t'a"}    → 5
        // intersection = 3, union = 5 → 0.6
        XCTAssertEqual(s, 0.6, accuracy: 0.01)
    }

    func testScoreCaseInsensitive() {
        let s1 = CharNGramScorer.score("Erkut", "erkut")
        XCTAssertEqual(s1, 1.0)
    }

    // MARK: - Sprint 36 regression (kısa metin)

    /// Sprint 36 word Jaccard'da bu çift düşük skor veriyordu (1 ortak token).
    /// CharNGramScorer ile karakter trigram'ları çok daha zengin ortak alan
    /// yakalar — ranker artık bu çifti meaningful olarak tanır.
    func testSprint36RegressionShortNames() {
        let saved = "Beni Erkut diye çağır"
        let query = "Erkut burada nasılsın"
        let s = CharNGramScorer.score(saved, query)
        // "erkut" trigram'ları (erk, rku, kut) iki tarafta da var.
        // 3 ortak trigram, daha geniş diğerleri farklı.
        // Bu testin amacı: skor MIN 0.1 olmalı (anlamlı match).
        XCTAssertGreaterThan(s, 0.1, "Sprint 36 regression — 'Erkut' isim eşleşmesi character n-gram ile anlamlı skor vermeli")
    }
}
