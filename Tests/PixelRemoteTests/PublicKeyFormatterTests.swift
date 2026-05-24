import XCTest

@testable import PixelRemote

final class PublicKeyFormatterTests: XCTestCase {

    func testEmptyReturnsDash() {
        XCTAssertEqual(PublicKeyFormatter.format(""), "—")
    }

    func testDefaultGroupSizeEightCharGroups() {
        let input = String(repeating: "A", count: 8)
            + String(repeating: "B", count: 8)
            + String(repeating: "C", count: 8)
        let result = PublicKeyFormatter.format(input)
        XCTAssertEqual(result, "AAAAAAAA BBBBBBBB CCCCCCCC")
    }

    func testNonExactMultipleProducesShorterLastGroup() {
        let input = String(repeating: "A", count: 8)
            + String(repeating: "B", count: 8)
            + String(repeating: "C", count: 4)
        let result = PublicKeyFormatter.format(input)
        XCTAssertEqual(result, "AAAAAAAA BBBBBBBB CCCC")
    }

    func testShortInputSingleGroup() {
        XCTAssertEqual(PublicKeyFormatter.format("abc"), "abc")
        XCTAssertEqual(PublicKeyFormatter.format("12345678"), "12345678")
    }

    func testCustomGroupSize() {
        let input = "123456789012"
        let result = PublicKeyFormatter.format(input, groupSize: 4)
        XCTAssertEqual(result, "1234 5678 9012")
    }

    func testZeroGroupSizeReturnsOriginal() {
        let input = "abcdef"
        XCTAssertEqual(PublicKeyFormatter.format(input, groupSize: 0), input)
    }

    func testReassemblyMatchesOriginal() {
        // Boşlukları kaldırınca orijinal geri gelmeli — fidelity koruma.
        let input = "MCowBQYDK2VwAyEArandompublickeydataforEd25519test01="
        let formatted = PublicKeyFormatter.format(input)
        let stripped = formatted.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(stripped, input)
    }
}
