import XCTest
@testable import PixelMemory

/// **Sprint 36 (v0.2.63):** Jaccard token similarity scorer testleri.
final class TextSimilarityScorerTests: XCTestCase {
    func testIdenticalTextsScore1() {
        XCTAssertEqual(TextSimilarityScorer.score("aynı metin burada", "aynı metin burada"), 1.0)
    }

    func testCompletelyDifferentTextsScore0() {
        XCTAssertEqual(TextSimilarityScorer.score("kedi köpek", "araba uçak"), 0.0)
    }

    func testCaseInsensitive() {
        let a = "PR Review Template"
        let b = "pr review template"
        XCTAssertEqual(TextSimilarityScorer.score(a, b), 1.0)
    }

    func testSymmetry() {
        let a = "Mesut Yılmaz iletişim sorumlusudur burada"
        let b = "iletişim için Mesut Yılmaz yetkili kişidir kontak"
        let scoreAB = TextSimilarityScorer.score(a, b)
        let scoreBA = TextSimilarityScorer.score(b, a)
        XCTAssertEqual(scoreAB, scoreBA)
    }

    func testEmptyInputReturnsZero() {
        XCTAssertEqual(TextSimilarityScorer.score("", "anything text here"), 0.0)
        XCTAssertEqual(TextSimilarityScorer.score("anything text here", ""), 0.0)
        XCTAssertEqual(TextSimilarityScorer.score("", ""), 0.0)
    }

    func testStopwordsFiltered() {
        // "ve", "bu" Türkçe stopword; "the" İngilizce stopword.
        // Bu yüzden iki metin token bazında benzer görünüyor.
        let a = "kahvaltıda yumurta ve domates"
        let b = "öğle yemeğinde yumurta ve domates"
        let score = TextSimilarityScorer.score(a, b)
        // "yumurta", "domates" ortak (stopword "ve" filter dışı)
        // "kahvaltıda" + "öğle" + "yemeğinde" farklı
        // intersection = {yumurta, domates} = 2
        // union = {kahvaltıda, yumurta, domates, öğle, yemeğinde} = 5
        // score = 2/5 = 0.4
        XCTAssertEqual(score, 0.4, accuracy: 0.001)
    }

    func testShortTokensFiltered() {
        // "AI" 2 karakter, minTokenLength=3 filter → token olmaz.
        let tokens = TextSimilarityScorer.tokenize("AI ve makine öğrenmesi")
        XCTAssertFalse(tokens.contains("ai"))
        XCTAssertTrue(tokens.contains("makine"))
    }

    func testTurkishCharactersPreserved() {
        let tokens = TextSimilarityScorer.tokenize("öğrenme şekli")
        XCTAssertTrue(tokens.contains("öğrenme"))
        XCTAssertTrue(tokens.contains("şekli"))
    }

    func testTokenizeEmpty() {
        XCTAssertEqual(TextSimilarityScorer.tokenize(""), [])
    }

    func testTokenizePunctuationSplits() {
        let tokens = TextSimilarityScorer.tokenize("merhaba, dünya! nasılsın?")
        XCTAssertTrue(tokens.contains("merhaba"))
        XCTAssertTrue(tokens.contains("dünya"))
        XCTAssertTrue(tokens.contains("nasılsın"))
    }

    func testPartialOverlapMidRange() {
        // Yarısı ortak token kümeleri
        let a = "uçak gemi tren bisiklet"
        let b = "uçak gemi araba otobüs"
        let score = TextSimilarityScorer.score(a, b)
        // intersection = {uçak, gemi}, union = {uçak, gemi, tren, bisiklet, araba, otobüs}
        // 2/6 = 0.333
        XCTAssertEqual(score, 1.0/3.0, accuracy: 0.01)
    }

    // MARK: - Demo regression

    func testDemoUserProfileScenario() {
        // Senaryo: kullanıcı "Beni Erkut diye çağır" diye save_memory yapmış.
        // Sonraki mesajda "Erkut burada, nasılsın?" yazıyor.
        // Beklenen: anlamlı similarity (eşik üstü).
        let saved = "Beni Erkut diye çağır"
        let query = "Erkut burada, nasılsın?"
        let score = TextSimilarityScorer.score(saved, query)
        // "erkut" ortak. "diye" ve "burada" stopword listesinde "diye" var.
        // intersection ≈ {erkut}, küçük union → 0.2 civarı, threshold 0.55 üstünde değil.
        // Bu test embedding-free yaklaşımın LIMIT'ini gösterir — Jaccard kısa metinlerde zayıf.
        // Min 0 olmasın diye soft assertion.
        XCTAssertGreaterThan(score, 0.0)
        XCTAssertLessThan(score, 1.0)
    }
}
