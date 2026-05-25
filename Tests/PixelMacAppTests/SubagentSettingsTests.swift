import Foundation
import XCTest

@testable import PixelMacApp

final class SubagentSettingsTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() async throws {
        suiteName = "pixel.subagent.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - SubagentSettings struct

    func testDefaultValues() {
        let s = SubagentSettings.default
        XCTAssertEqual(s.maxDurationSeconds, 60)
        XCTAssertNil(s.maxOutputBytes)
        XCTAssertEqual(s.maxParallelCap, 3)
        XCTAssertEqual(s.defaultBackend, "claude")
    }

    func testMaxDurationClampedToMinimum() {
        XCTAssertEqual(SubagentSettings(maxDurationSeconds: 0).maxDurationSeconds, 5)
        XCTAssertEqual(SubagentSettings(maxDurationSeconds: -10).maxDurationSeconds, 5)
        XCTAssertEqual(SubagentSettings(maxDurationSeconds: 60).maxDurationSeconds, 60)
    }

    func testMaxParallelCapClampedToValidRange() {
        XCTAssertEqual(SubagentSettings(maxParallelCap: 0).maxParallelCap, 1)
        XCTAssertEqual(SubagentSettings(maxParallelCap: 100).maxParallelCap, 10)
        XCTAssertEqual(SubagentSettings(maxParallelCap: 5).maxParallelCap, 5)
    }

    func testMaxOutputBytesClampedToMinimum() {
        XCTAssertEqual(SubagentSettings(maxOutputBytes: 0).maxOutputBytes, 1024)
        XCTAssertEqual(SubagentSettings(maxOutputBytes: 4096).maxOutputBytes, 4096)
        XCTAssertNil(SubagentSettings(maxOutputBytes: nil).maxOutputBytes)
    }

    // MARK: - UserDefaults persistence

    func testLoadReturnsDefaultsWhenEmpty() {
        let s = SubagentSettingsStore.load(defaults: defaults)
        XCTAssertEqual(s, SubagentSettings.default)
    }

    func testSaveLoadRoundTrip() {
        let original = SubagentSettings(
            maxDurationSeconds: 120,
            maxOutputBytes: 8192,
            maxParallelCap: 5,
            defaultBackend: "codex"
        )
        SubagentSettingsStore.save(original, defaults: defaults)
        let loaded = SubagentSettingsStore.load(defaults: defaults)
        XCTAssertEqual(loaded, original)
    }

    func testNilOutputBytesPersistsAsSentinel() {
        let original = SubagentSettings(
            maxDurationSeconds: 60,
            maxOutputBytes: nil,
            maxParallelCap: 3,
            defaultBackend: "claude"
        )
        SubagentSettingsStore.save(original, defaults: defaults)
        XCTAssertEqual(
            defaults.integer(forKey: SubagentSettingsStore.maxOutputBytesKey),
            SubagentSettingsStore.noOutputLimitSentinel
        )
        let loaded = SubagentSettingsStore.load(defaults: defaults)
        XCTAssertNil(loaded.maxOutputBytes)
    }

    func testResetClearsAllKeys() {
        let modified = SubagentSettings(maxDurationSeconds: 300, maxOutputBytes: 16384, maxParallelCap: 8, defaultBackend: "gemini")
        SubagentSettingsStore.save(modified, defaults: defaults)

        SubagentSettingsStore.reset(defaults: defaults)
        let after = SubagentSettingsStore.load(defaults: defaults)
        XCTAssertEqual(after, SubagentSettings.default)
    }
}
