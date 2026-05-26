import XCTest
import PixelMCPServer
@testable import PixelVoice

/// **Sprint 46 (v0.2.74):** OpenAI + Gemini ToolBridge'lerin
/// VoiceToolPreferences ile filter etkileşimi.
final class ToolBridgePreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var prefs: VoiceToolPreferences!
    private var registry: ToolRegistry!

    override func setUp() {
        super.setUp()
        suiteName = "test.bridge.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        prefs = VoiceToolPreferences(defaults: defaults)
        registry = BuiltInTools.makeRegistry()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - OpenAI bridge

    func testOpenAIDefaultFiltersToWhitelist() {
        let tools = OpenAIToolBridge.voiceTools(from: registry, preferences: prefs)
        let names = Set(tools.map { $0.name })
        XCTAssertTrue(names.contains("get_current_time"))
        XCTAssertTrue(names.contains("save_memory"))
        XCTAssertFalse(names.contains("ui_click"))
    }

    func testOpenAIRiskyOptInIncludesUITool() {
        prefs.setEnabled("ui_click", true)
        let tools = OpenAIToolBridge.voiceTools(from: registry, preferences: prefs)
        let names = Set(tools.map { $0.name })
        XCTAssertTrue(names.contains("ui_click"), "Risky tool opt-in sonrası dahil")
    }

    func testOpenAIDefaultDisabledExcludesGetTime() {
        prefs.setEnabled("get_current_time", false)
        let tools = OpenAIToolBridge.voiceTools(from: registry, preferences: prefs)
        let names = Set(tools.map { $0.name })
        XCTAssertFalse(names.contains("get_current_time"), "Default-enabled tool opt-out sonrası hariç")
    }

    func testOpenAIIncludeAllBypassesPreferences() {
        let allTools = OpenAIToolBridge.voiceTools(from: registry, preferences: prefs, includeAll: true)
        let names = Set(allTools.map { $0.name })
        XCTAssertTrue(names.contains("ui_click"), "includeAll preferences'ı bypass eder")
    }

    // MARK: - Gemini bridge

    func testGeminiDefaultFiltersToWhitelist() {
        let tools = GeminiToolBridge.voiceTools(from: registry, preferences: prefs)
        XCTAssertEqual(tools.count, 1, "Tek functionDeclarations grubu")
        let names = Set(tools[0].functionDeclarations.map { $0.name })
        XCTAssertTrue(names.contains("get_current_time"))
        XCTAssertFalse(names.contains("ui_click"))
    }

    func testGeminiRiskyOptInIncludesUITool() {
        prefs.setEnabled("ui_screenshot", true)
        let tools = GeminiToolBridge.voiceTools(from: registry, preferences: prefs)
        let names = Set(tools[0].functionDeclarations.map { $0.name })
        XCTAssertTrue(names.contains("ui_screenshot"))
    }

    func testGeminiAllOptedOutReturnsEmpty() {
        // Tüm default tool'ları opt-out — sonuç boş array (Gemini setup'ta
        // tools field omit edilmeli).
        for name in VoiceToolPreferences.defaultEnabledToolNames {
            prefs.setEnabled(name, false)
        }
        let tools = GeminiToolBridge.voiceTools(from: registry, preferences: prefs)
        XCTAssertTrue(tools.isEmpty)
    }

    // MARK: - Cross-provider consistency

    func testOpenAIAndGeminiSameToolSet() {
        let openai = OpenAIToolBridge.voiceTools(from: registry, preferences: prefs)
        let gemini = GeminiToolBridge.voiceTools(from: registry, preferences: prefs)
        let openaiNames = Set(openai.map { $0.name })
        let geminiNames = Set(gemini[0].functionDeclarations.map { $0.name })
        XCTAssertEqual(openaiNames, geminiNames, "Aynı preferences her iki provider için aynı tool seti")
    }
}
