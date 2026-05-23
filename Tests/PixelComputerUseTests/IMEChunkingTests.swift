import XCTest

@testable import PixelComputerUse

/// **Faz 3b (ADR-0029):** `PointerControl.unicodeChunks(for:)` saf fonksiyon —
/// AX/CGEvent bağımsız. Grapheme cluster sınırlarında parçalanma davranışı
/// test edilir; gerçek CGEvent enjeksiyonu CI'da çalışmaz.
///
/// Önemli olan: bir grapheme cluster ASLA bölünmemeli; aksi takdirde IME
/// pipeline'da kısmi karakter görür (örn. emoji baz + skin-tone modifier
/// ayrı keyDown'larda gönderildiğinde target field iki ayrı emoji görür).
final class IMEChunkingTests: XCTestCase {

    // MARK: - ASCII

    func testASCIIOneChunkPerCharacter() {
        let chunks = PointerControl.unicodeChunks(for: "hello")
        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks.map { $0.count }, [1, 1, 1, 1, 1])
    }

    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(PointerControl.unicodeChunks(for: "").count, 0)
    }

    // MARK: - Turkish (Latin + diakritik)

    func testTurkishLowercaseDottedI() {
        let chunks = PointerControl.unicodeChunks(for: "şğüöçı")
        XCTAssertEqual(chunks.count, 6)
        // Her biri tek BMP code unit
        XCTAssertEqual(chunks.map { $0.count }, [1, 1, 1, 1, 1, 1])
    }

    func testTurkishUppercaseDotlessI() {
        // "İ" — Latin Capital Letter I with Dot Above (U+0130). BMP, tek UTF-16.
        let chunks = PointerControl.unicodeChunks(for: "İSTANBUL")
        XCTAssertEqual(chunks.count, 8)
    }

    func testCombiningDiacriticGroupedAsOneCharacter() {
        // "é" iki şekilde yazılabilir: precomposed (U+00E9) veya
        // "e" + COMBINING ACUTE ACCENT (U+0301). Decomposed form Character
        // tek grapheme olmalı.
        let decomposed = "e\u{0301}"  // 2 scalar, 1 character
        let chunks = PointerControl.unicodeChunks(for: decomposed)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 2)  // 2 UTF-16 code units birlikte
    }

    // MARK: - Emoji

    func testBasicEmojiOneChunk() {
        // "👋" — surrogate pair (2 UTF-16 code units)
        let chunks = PointerControl.unicodeChunks(for: "👋")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 2)  // surrogate pair
    }

    func testEmojiWithSkinToneOneChunk() {
        // "👋🏼" — wave + medium-light skin tone (4 scalar = 4 code unit)
        // Grapheme cluster olarak TEK karakter; tek chunk olmalı.
        let chunks = PointerControl.unicodeChunks(for: "👋🏼")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 4)
    }

    func testZWJSequenceFamilyEmoji() {
        // "👨‍👩‍👧" — man + ZWJ + woman + ZWJ + girl (8 code unit total)
        // Tek grapheme cluster → tek chunk.
        let chunks = PointerControl.unicodeChunks(for: "👨‍👩‍👧")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].count, 8)
    }

    func testMultipleEmojiSeparated() {
        // "👋👍" — iki ayrı grapheme cluster
        let chunks = PointerControl.unicodeChunks(for: "👋👍")
        XCTAssertEqual(chunks.count, 2)
    }

    // MARK: - Mixed

    func testMixedASCIIEmoji() {
        // "Hi 👋!" — H, i, space, wave, ! = 5 grapheme
        let chunks = PointerControl.unicodeChunks(for: "Hi 👋!")
        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks[3].count, 2)  // wave = surrogate pair
    }

    func testCJKCharacters() {
        // "你好" — Chinese, 2 BMP CJK characters
        let chunks = PointerControl.unicodeChunks(for: "你好")
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks.map { $0.count }, [1, 1])
    }

    func testNewlinePreserved() {
        let chunks = PointerControl.unicodeChunks(for: "a\nb")
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[1], [UInt16(0x0A)])  // LF
    }
}
