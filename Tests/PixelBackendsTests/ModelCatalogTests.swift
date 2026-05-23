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

    func testKnownModelsClaudeStartsWithOpusAlias() {
        let models = ModelCatalog.knownModels(for: .claude)
        // v0.2.24: alias "opus" en üstte — her zaman güncel Opus
        XCTAssertEqual(models.first, "opus")
        XCTAssertTrue(models.contains("sonnet"))
        XCTAssertTrue(models.contains("haiku"))
        XCTAssertTrue(models.contains("claude-opus-4-7"))
        XCTAssertTrue(models.contains("claude-opus-4-6"))
    }

    func testKnownModelsClaudeAliasesBeforeVersionedIDs() {
        let models = ModelCatalog.knownModels(for: .claude)
        guard let opusIdx = models.firstIndex(of: "opus"),
              let versionedIdx = models.firstIndex(of: "claude-opus-4-7") else {
            return XCTFail("alias veya versioned ID eksik")
        }
        XCTAssertLessThan(opusIdx, versionedIdx)
    }

    func testKnownModelsCodexIncludesGPT5() {
        let models = ModelCatalog.knownModels(for: .codex)
        XCTAssertTrue(models.contains("gpt-5"))
        XCTAssertTrue(models.contains("gpt-5.5"))
    }

    func testKnownModelsGeminiIncludesFlashFamily() {
        let models = ModelCatalog.knownModels(for: .gemini)
        // v0.2.23 kullanıcı tercihi: 3.5-flash + 3.1-pro öncelikli
        XCTAssertTrue(models.contains("gemini-3.5-flash"))
        XCTAssertTrue(models.contains("gemini-3.1-pro"))
        // Eski sürümler hâlâ catalog'da (fallback)
        XCTAssertTrue(models.contains("gemini-2.5-flash"))
        XCTAssertTrue(models.contains("gemini-2.0-flash"))
    }

    func testGeminiCatalogPrioritizes3xVersions() {
        let models = ModelCatalog.knownModels(for: .gemini)
        guard let flashIdx = models.firstIndex(of: "gemini-3.5-flash"),
              let proIdx = models.firstIndex(of: "gemini-3.1-pro"),
              let oldFlashIdx = models.firstIndex(of: "gemini-2.5-flash") else {
            return XCTFail("3.x veya 2.x model eksik")
        }
        XCTAssertLessThan(flashIdx, oldFlashIdx, "3.5-flash 2.5-flash'tan önce olmalı")
        XCTAssertLessThan(proIdx, oldFlashIdx)
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
            // v0.2.24: alias "opus" → her zaman güncel Opus
            XCTAssertEqual(CLIBackend.defaultModelID(for: .claude), "opus")
        }
        if ProcessInfo.processInfo.environment["PIXEL_GEMINI_MODEL"] == nil {
            // v0.2.25: varsayılan model gemini-2.5-flash
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
