import XCTest
import PixelMCPServer
@testable import PixelVoice

/// **Sprint 46 (v0.2.74):** VoiceToolPreferences per-tool override + default
/// + risky classification tests.
final class VoiceToolPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var prefs: VoiceToolPreferences!

    override func setUp() {
        super.setUp()
        suiteName = "test.voicetools.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        prefs = VoiceToolPreferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Default classification

    func testDefaultEnabledToolsContainsSafeSet() {
        // Sprint 44 whitelist — Sprint 46'da backward-compat olarak korundu.
        XCTAssertTrue(VoiceToolPreferences.defaultEnabledToolNames.contains("get_current_time"))
        XCTAssertTrue(VoiceToolPreferences.defaultEnabledToolNames.contains("save_memory"))
        XCTAssertTrue(VoiceToolPreferences.defaultEnabledToolNames.contains("notify"))
    }

    func testRiskyToolsContainsUITools() {
        XCTAssertTrue(VoiceToolPreferences.riskyToolNames.contains("ui_click"))
        XCTAssertTrue(VoiceToolPreferences.riskyToolNames.contains("ui_type"))
        XCTAssertTrue(VoiceToolPreferences.riskyToolNames.contains("dispatch_subagent"))
    }

    func testDefaultAndRiskyDisjoint() {
        let intersection = VoiceToolPreferences.defaultEnabledToolNames
            .intersection(VoiceToolPreferences.riskyToolNames)
        XCTAssertTrue(intersection.isEmpty, "Default ve risky kategoriler ayrı")
    }

    func testIsDefaultEnabledHelper() {
        XCTAssertTrue(VoiceToolPreferences.isDefaultEnabled("get_current_time"))
        XCTAssertFalse(VoiceToolPreferences.isDefaultEnabled("ui_click"))
        XCTAssertFalse(VoiceToolPreferences.isDefaultEnabled("unknown_tool"))
    }

    func testIsRiskyHelper() {
        XCTAssertTrue(VoiceToolPreferences.isRisky("ui_click"))
        XCTAssertFalse(VoiceToolPreferences.isRisky("get_current_time"))
        XCTAssertFalse(VoiceToolPreferences.isRisky("unknown_tool"))
    }

    // MARK: - isEnabled decision chain

    func testEnabledByDefaultWithoutOverride() {
        XCTAssertTrue(prefs.isEnabled("get_current_time"))
        XCTAssertTrue(prefs.isEnabled("save_memory"))
    }

    func testRiskyDisabledByDefault() {
        XCTAssertFalse(prefs.isEnabled("ui_click"))
        XCTAssertFalse(prefs.isEnabled("dispatch_subagent"))
    }

    func testUnknownToolDisabledByDefault() {
        XCTAssertFalse(prefs.isEnabled("nonexistent_tool"))
    }

    // MARK: - setEnabled override

    func testSetEnabledOverridesDefault() {
        prefs.setEnabled("ui_click", true)
        XCTAssertTrue(prefs.isEnabled("ui_click"), "Override true risky tool'ı aktive eder")
    }

    func testSetEnabledDisablesDefault() {
        prefs.setEnabled("get_current_time", false)
        XCTAssertFalse(prefs.isEnabled("get_current_time"), "Override false default-enabled tool'ı kapatır")
    }

    func testSetEnabledPersistsAcrossInstances() {
        prefs.setEnabled("ui_click", true)
        let prefs2 = VoiceToolPreferences(defaults: defaults)
        XCTAssertTrue(prefs2.isEnabled("ui_click"))
    }

    // MARK: - clearOverride

    func testClearOverrideRestoresDefault() {
        prefs.setEnabled("ui_click", true)
        XCTAssertTrue(prefs.isEnabled("ui_click"))
        prefs.clearOverride("ui_click")
        XCTAssertFalse(prefs.isEnabled("ui_click"), "Risky tool default'a (false) dönüyor")
    }

    func testClearOverrideOnDefaultEnabled() {
        prefs.setEnabled("get_current_time", false)
        XCTAssertFalse(prefs.isEnabled("get_current_time"))
        prefs.clearOverride("get_current_time")
        XCTAssertTrue(prefs.isEnabled("get_current_time"), "Default-enabled tool default'a (true) dönüyor")
    }

    // MARK: - resetAllOverrides

    func testResetAllOverridesClearsEverything() {
        prefs.setEnabled("ui_click", true)
        prefs.setEnabled("get_current_time", false)
        prefs.setEnabled("save_memory", false)
        prefs.resetAllOverrides()
        // Hepsi default'a döner
        XCTAssertFalse(prefs.isEnabled("ui_click"))
        XCTAssertTrue(prefs.isEnabled("get_current_time"))
        XCTAssertTrue(prefs.isEnabled("save_memory"))
    }

    // MARK: - Sprint 44 backward-compat

    func testOpenAIBridgeAliasMatchesDefaults() {
        // OpenAIToolBridge.voiceSafeToolNames Sprint 46'da alias oldu.
        XCTAssertEqual(
            OpenAIToolBridge.voiceSafeToolNames,
            VoiceToolPreferences.defaultEnabledToolNames
        )
    }
}
