import XCTest

@testable import PixelMacApp

final class TagNormalizerTests: XCTestCase {

    // MARK: - Single

    func testNormalizeTrimsAndLowercases() {
        XCTAssertEqual(TagNormalizer.normalize("  Önemli  "), "önemli")
    }

    func testNormalizeRejectsEmpty() {
        XCTAssertNil(TagNormalizer.normalize(""))
        XCTAssertNil(TagNormalizer.normalize("   "))
        XCTAssertNil(TagNormalizer.normalize("\n\t"))
    }

    func testNormalizeTruncatesToMaxLength() {
        let long = String(repeating: "a", count: 50)
        let normalized = TagNormalizer.normalize(long)
        XCTAssertEqual(normalized?.count, TagNormalizer.maxLength)
        XCTAssertEqual(normalized, String(repeating: "a", count: TagNormalizer.maxLength))
    }

    func testNormalizeBoundaryMaxLength() {
        let exact = String(repeating: "x", count: TagNormalizer.maxLength)
        XCTAssertEqual(TagNormalizer.normalize(exact), exact)
    }

    // MARK: - List

    func testNormalizeListSanitizesDedupSorts() {
        let raws = ["Work", "  work  ", "important", "Important", "personal", ""]
        let result = TagNormalizer.normalize(raws)
        XCTAssertEqual(result, ["important", "personal", "work"])
    }

    func testNormalizeListDropsAllEmpty() {
        XCTAssertTrue(TagNormalizer.normalize(["", "  ", "\n"]).isEmpty)
    }

    func testNormalizeListEmptyArrayReturnsEmpty() {
        XCTAssertTrue(TagNormalizer.normalize([]).isEmpty)
    }

    func testNormalizeListPreservesTurkishCharacters() {
        XCTAssertEqual(
            TagNormalizer.normalize(["Çok Önemli", "şahsi", "iş"]),
            ["iş", "çok önemli", "şahsi"]
        )
    }

    func testNormalizeListSortStability() {
        XCTAssertEqual(
            TagNormalizer.normalize(["c", "a", "b"]),
            ["a", "b", "c"]
        )
    }
}
