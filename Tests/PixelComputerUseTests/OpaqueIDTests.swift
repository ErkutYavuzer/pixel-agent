import XCTest

@testable import PixelComputerUse

/// **Faz 3a:** `OpaqueID` encoder/decoder testleri. AX bağımsız — pure value
/// transform, deterministic.
final class OpaqueIDTests: XCTestCase {

    // MARK: - Encode

    func testEncodeBundleAndSimplePath() {
        let oid = OpaqueID.encode(
            bundleID: "com.apple.Safari",
            path: ["AXApplication", "AXWindow", "AXButton"],
            discriminators: [nil, "Welcome", "Sign In"]
        )
        XCTAssertEqual(oid, "com.apple.Safari|AXApplication|AXWindow:Welcome|AXButton:Sign In")
    }

    func testEncodeFrontmostHasEmptyBundlePrefix() {
        let oid = OpaqueID.encode(
            bundleID: nil,
            path: ["AXApplication", "AXButton"],
            discriminators: [nil, "OK"]
        )
        XCTAssertEqual(oid, "|AXApplication|AXButton:OK")
    }

    func testEncodeAllNilDiscriminators() {
        let oid = OpaqueID.encode(
            bundleID: "x",
            path: ["AXWindow", "AXGroup"],
            discriminators: [nil, nil]
        )
        XCTAssertEqual(oid, "x|AXWindow|AXGroup")
    }

    func testEncodeEscapesPipeInDiscriminator() {
        let oid = OpaqueID.encode(
            bundleID: "app",
            path: ["AXMenu"],
            discriminators: ["File | Open"]
        )
        // Pipe karakter `\u{1}` ile yer değiştirir; decoder unescape eder
        XCTAssertTrue(oid.contains("\u{1}"))
        XCTAssertFalse(oid.contains("File | Open"))
    }

    func testEncodeEscapesColonInDiscriminator() {
        let oid = OpaqueID.encode(
            bundleID: "app",
            path: ["AXButton"],
            discriminators: ["10:30 AM"]
        )
        XCTAssertTrue(oid.contains("\u{2}"))
    }

    // MARK: - Decode

    func testDecodeRoundTripsSimplePath() {
        let original = OpaqueID.encode(
            bundleID: "com.apple.Safari",
            path: ["AXApplication", "AXWindow", "AXButton"],
            discriminators: [nil, "Welcome", "Sign In"]
        )
        guard let parsed = OpaqueID.decode(original) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(parsed.bundleID, "com.apple.Safari")
        XCTAssertEqual(parsed.path.count, 3)
        XCTAssertEqual(parsed.path[0].role, "AXApplication")
        XCTAssertNil(parsed.path[0].discriminator)
        XCTAssertEqual(parsed.path[1].role, "AXWindow")
        XCTAssertEqual(parsed.path[1].discriminator, "Welcome")
        XCTAssertEqual(parsed.path[2].role, "AXButton")
        XCTAssertEqual(parsed.path[2].discriminator, "Sign In")
    }

    func testDecodeRoundTripsEscapedCharacters() {
        let oid = OpaqueID.encode(
            bundleID: "app",
            path: ["AXMenuItem"],
            discriminators: ["File | Open: New"]
        )
        guard let parsed = OpaqueID.decode(oid) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(parsed.path[0].discriminator, "File | Open: New")
    }

    func testDecodeFrontmostBundleNilWhenEmptyPrefix() {
        guard let parsed = OpaqueID.decode("|AXApplication|AXButton:OK") else {
            return XCTFail("decode failed")
        }
        XCTAssertNil(parsed.bundleID)
        XCTAssertEqual(parsed.path[1].discriminator, "OK")
    }

    func testDecodeOnlyBundleNoPath() {
        guard let parsed = OpaqueID.decode("com.apple.Safari") else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(parsed.bundleID, "com.apple.Safari")
        XCTAssertTrue(parsed.path.isEmpty)
    }

    func testDecodeStepWithEmptyDiscriminatorTreatedAsNil() {
        // `AXButton:` → discriminator empty → nil
        guard let parsed = OpaqueID.decode("app|AXButton:") else {
            return XCTFail("decode failed")
        }
        XCTAssertNil(parsed.path[0].discriminator)
    }
}
