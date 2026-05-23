import XCTest

@testable import PixelComputerUse

/// **Faz 3b (ADR-0029):** `ModifierFlags` OptionSet ve `parse(_:)` testleri.
final class ModifierFlagsTests: XCTestCase {

    // MARK: - OptionSet basics

    func testEmptyHasNoFlags() {
        let m: ModifierFlags = []
        XCTAssertTrue(m.isEmpty)
    }

    func testIndividualFlags() {
        XCTAssertTrue(ModifierFlags.command.contains(.command))
        XCTAssertFalse(ModifierFlags.command.contains(.option))
        XCTAssertFalse(ModifierFlags.command.contains(.shift))
        XCTAssertFalse(ModifierFlags.command.contains(.control))
    }

    func testCombineMultipleFlags() {
        let combo: ModifierFlags = [.command, .shift]
        XCTAssertTrue(combo.contains(.command))
        XCTAssertTrue(combo.contains(.shift))
        XCTAssertFalse(combo.contains(.option))
    }

    // MARK: - parse(_:)

    func testParseCanonicalNames() {
        XCTAssertEqual(ModifierFlags.parse(["command"]), .command)
        XCTAssertEqual(ModifierFlags.parse(["option"]), .option)
        XCTAssertEqual(ModifierFlags.parse(["shift"]), .shift)
        XCTAssertEqual(ModifierFlags.parse(["control"]), .control)
    }

    func testParseAliases() {
        XCTAssertEqual(ModifierFlags.parse(["cmd"]), .command)
        XCTAssertEqual(ModifierFlags.parse(["opt"]), .option)
        XCTAssertEqual(ModifierFlags.parse(["alt"]), .option)
        XCTAssertEqual(ModifierFlags.parse(["ctrl"]), .control)
    }

    func testParseGlyphs() {
        XCTAssertEqual(ModifierFlags.parse(["⌘"]), .command)
        XCTAssertEqual(ModifierFlags.parse(["⌥"]), .option)
        XCTAssertEqual(ModifierFlags.parse(["⇧"]), .shift)
        XCTAssertEqual(ModifierFlags.parse(["⌃"]), .control)
    }

    func testParseMixedCase() {
        XCTAssertEqual(ModifierFlags.parse(["CMD", "Shift"]), [.command, .shift])
    }

    func testParseUnknownSilentlySkipped() {
        // Bilinmeyen anahtarlar atlanır; bilinenler set'e girer.
        XCTAssertEqual(ModifierFlags.parse(["xyz", "command"]), .command)
        XCTAssertTrue(ModifierFlags.parse(["nothing"]).isEmpty)
    }

    func testParseEmptyArray() {
        XCTAssertTrue(ModifierFlags.parse([]).isEmpty)
    }

    func testParseDuplicatesIdempotent() {
        XCTAssertEqual(
            ModifierFlags.parse(["command", "command", "command"]),
            .command
        )
    }

    func testParseAllFourCombo() {
        let parsed = ModifierFlags.parse(["cmd", "opt", "shift", "ctrl"])
        XCTAssertEqual(parsed, [.command, .option, .shift, .control])
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original: ModifierFlags = [.command, .shift]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModifierFlags.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
