import XCTest

@testable import PixelRemote

final class PairingCodeTests: XCTestCase {
    func testGenerateProducesValidCode() {
        for _ in 0..<20 {
            let code = PairingCode.generate()
            XCTAssertEqual(code.count, PairingCode.length)
            XCTAssertTrue(PairingCode.isValid(code), "generated code \(code) failed isValid")
        }
    }

    func testIsValidAcceptsKnownGoodCodes() {
        XCTAssertTrue(PairingCode.isValid("ABC234"))
        XCTAssertTrue(PairingCode.isValid("XYZ789"))
        XCTAssertTrue(PairingCode.isValid("JKM567"))
    }

    func testIsValidRejectsWrongLength() {
        XCTAssertFalse(PairingCode.isValid(""))
        XCTAssertFalse(PairingCode.isValid("ABC23"))
        XCTAssertFalse(PairingCode.isValid("ABCD234"))
    }

    func testIsValidRejectsLowercase() {
        XCTAssertFalse(PairingCode.isValid("abc234"))
        XCTAssertFalse(PairingCode.isValid("AbC234"))
    }

    func testIsValidRejectsConfusingCharacters() {
        XCTAssertFalse(PairingCode.isValid("0BC234"))
        XCTAssertFalse(PairingCode.isValid("1BC234"))
        XCTAssertFalse(PairingCode.isValid("OBC234"))
        XCTAssertFalse(PairingCode.isValid("IBC234"))
        XCTAssertFalse(PairingCode.isValid("LBC234"))
    }

    func testIsValidRejectsSpecialCharacters() {
        XCTAssertFalse(PairingCode.isValid("ABC-23"))
        XCTAssertFalse(PairingCode.isValid("ABC 23"))
        XCTAssertFalse(PairingCode.isValid("ABC.23"))
    }

    func testGenerateProducesDifferentCodes() {
        var codes = Set<String>()
        for _ in 0..<30 {
            codes.insert(PairingCode.generate())
        }
        XCTAssertGreaterThan(codes.count, 27, "duplicate rate too high")
    }
}
