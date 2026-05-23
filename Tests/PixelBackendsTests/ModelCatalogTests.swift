import XCTest

@testable import PixelBackends

/// **v0.2.22:** `ModelCatalog` + `CLIBackend.defaultModelID` UserDefaults
/// önceliği test edilir. Her test'in başında ve sonunda test-spesifik
/// UserDefaults key'leri temizlenir.
final class ModelCatalogTests: XCTestCase {

    private func clearAllStoredModels() {
        for kind in CLIKind.allCases {
            UserDefaults.standard.removeObject(forKey: ModelCatalog.userDefaultsKey(for: kind))
        }
    }

    override func setUp() {
        super.setUp()
        clearAllStoredModels()
    }

    override func tearDown() {
        clearAllStoredModels()
        super.tearDown()
    }

    // MARK: - UserDefaults key

    func testUserDefaultsKeyFormat() {
        XCTAssertEqual(ModelCatalog.userDefaultsKey(for: .claude), "pixel.model.claude")
        XCTAssertEqual(ModelCatalog.userDefaultsKey(for: .codex), "pixel.model.codex")
        XCTAssertEqual(ModelCatalog.userDefaultsKey(for: .gemini), "pixel.model.gemini")
    }

    func testUserDefaultsKeyPrefixConstant() {
        XCTAssertEqual(ModelCatalog.userDefaultsKeyPrefix, "pixel.model")
    }

    // MARK: - knownModels

    func testKnownModelsClaudeIncludesOpus47() {
        let models = ModelCatalog.knownModels(for: .claude)
        XCTAssertTrue(models.contains("claude-opus-4-7"))
        XCTAssertFalse(models.isEmpty)
    }

    func testKnownModelsCodexIncludesGPT5() {
        let models = ModelCatalog.knownModels(for: .codex)
        XCTAssertTrue(models.contains("gpt-5"))
        XCTAssertTrue(models.contains("gpt-5.5"))
    }

    func testKnownModelsGeminiIncludesFlashFamily() {
        let models = ModelCatalog.knownModels(for: .gemini)
        XCTAssertTrue(models.contains("gemini-2.5-flash"))
        XCTAssertTrue(models.contains("gemini-2.0-flash"))
    }

    func testKnownModelsNonEmpty() {
        for kind in CLIKind.allCases {
            XCTAssertFalse(ModelCatalog.knownModels(for: kind).isEmpty, "\(kind) catalog boş olamaz")
        }
    }

    // MARK: - CLIBackend.defaultModelID öncelik sırası

    func testUserDefaultsOverridesHardcodedForClaude() {
        UserDefaults.standard.set("claude-sonnet-4-7", forKey: ModelCatalog.userDefaultsKey(for: .claude))
        XCTAssertEqual(CLIBackend.defaultModelID(for: .claude), "claude-sonnet-4-7")
    }

    func testUserDefaultsOverridesHardcodedForGemini() {
        UserDefaults.standard.set("gemini-2.5-pro", forKey: ModelCatalog.userDefaultsKey(for: .gemini))
        XCTAssertEqual(CLIBackend.defaultModelID(for: .gemini), "gemini-2.5-pro")
    }

    func testEmptyUserDefaultsFallsBackToHardcoded() {
        // setUp clearAllStoredModels yapmıştı; UserDefaults boş.
        // Env var da set değilse hardcoded fallback gelmeli.
        if ProcessInfo.processInfo.environment["PIXEL_CLAUDE_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .claude), "claude-opus-4-7")
        }
        if ProcessInfo.processInfo.environment["PIXEL_GEMINI_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .gemini), "gemini-2.5-flash")
        }
    }

    func testWhitespaceOnlyUserDefaultsTreatedAsEmpty() {
        UserDefaults.standard.set("   ", forKey: ModelCatalog.userDefaultsKey(for: .codex))
        if ProcessInfo.processInfo.environment["PIXEL_CODEX_MODEL"] == nil {
            XCTAssertEqual(CLIBackend.defaultModelID(for: .codex), "gpt-5.5")
        }
    }
}
