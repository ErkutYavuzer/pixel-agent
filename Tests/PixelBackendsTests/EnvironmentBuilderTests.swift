import XCTest

@testable import PixelBackends

/// `EnvironmentBuilder.augmentedPATH` saf fonksiyon — bilinen CLI dizinlerinin
/// prepend davranışını test eder. Filesystem'a dokunan `latestNVMNodeBinDirectories`
/// gerçek bir HOME ile çalışır; CI'da nvm yoksa boş döner — bu beklenen davranış.
final class EnvironmentBuilderTests: XCTestCase {

    // MARK: - augmentedPATH saf davranış

    func testAugmentedPATHPrependsHomebrewWhenPATHEmpty() {
        let result = EnvironmentBuilder.augmentedPATH(currentPATH: nil, home: "/Users/test")
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
        XCTAssertTrue(result.contains("/usr/local/bin"))
    }

    func testAugmentedPATHKeepsExistingEntries() {
        let result = EnvironmentBuilder.augmentedPATH(
            currentPATH: "/usr/bin:/bin",
            home: "/Users/test"
        )
        XCTAssertTrue(result.contains("/usr/bin"))
        XCTAssertTrue(result.contains("/bin"))
        XCTAssertTrue(result.contains("/opt/homebrew/bin"))
    }

    func testAugmentedPATHPrependsKnownBeforeExisting() {
        let result = EnvironmentBuilder.augmentedPATH(
            currentPATH: "/usr/bin:/bin",
            home: "/Users/test"
        )
        // /opt/homebrew/bin "/usr/bin"'den önce gelmeli
        let parts = result.split(separator: ":").map(String.init)
        let homebrewIdx = parts.firstIndex(of: "/opt/homebrew/bin")
        let usrBinIdx = parts.firstIndex(of: "/usr/bin")
        XCTAssertNotNil(homebrewIdx)
        XCTAssertNotNil(usrBinIdx)
        XCTAssertLessThan(homebrewIdx!, usrBinIdx!)
    }

    func testAugmentedPATHDeduplicatesEntries() {
        // Mevcut PATH'te zaten homebrew varsa, prepend tekrarlamamalı.
        let result = EnvironmentBuilder.augmentedPATH(
            currentPATH: "/opt/homebrew/bin:/usr/bin",
            home: "/Users/test"
        )
        let count = result.split(separator: ":").filter { $0 == "/opt/homebrew/bin" }.count
        XCTAssertEqual(count, 1)
    }

    func testAugmentedPATHIncludesHomeBasedDirectories() {
        let result = EnvironmentBuilder.augmentedPATH(currentPATH: nil, home: "/Users/test")
        XCTAssertTrue(result.contains("/Users/test/.local/bin"))
        XCTAssertTrue(result.contains("/Users/test/bin"))
        XCTAssertTrue(result.contains("/Users/test/.volta/bin"))
        XCTAssertTrue(result.contains("/Users/test/.asdf/shims"))
    }

    func testAugmentedPATHIgnoresEmptySegments() {
        // Boş segment (PATH=":/usr/bin:") tekilleştirmede atlanmalı.
        let result = EnvironmentBuilder.augmentedPATH(
            currentPATH: ":/usr/bin:",
            home: "/Users/test"
        )
        let parts = result.split(separator: ":").map(String.init)
        XCTAssertFalse(parts.contains(""))
    }

    func testAugmentedPATHWithCustomHome() {
        let result = EnvironmentBuilder.augmentedPATH(
            currentPATH: nil,
            home: "/home/erkut"
        )
        XCTAssertTrue(result.contains("/home/erkut/.local/bin"))
        XCTAssertFalse(result.contains("/Users/test"))
    }

    // MARK: - augmentedEnvironment integration

    func testAugmentedEnvironmentHasPATH() {
        let env = EnvironmentBuilder.augmentedEnvironment()
        XCTAssertNotNil(env["PATH"])
        XCTAssertTrue(env["PATH"]?.contains("/opt/homebrew/bin") ?? false)
    }

    func testAugmentedEnvironmentCopiesParentVariables() {
        // HOME parent env'den miras alınmalı.
        let env = EnvironmentBuilder.augmentedEnvironment()
        XCTAssertNotNil(env["HOME"])
    }

    // MARK: - Gemini trust workspace (v0.2.18)

    func testAugmentedEnvironmentSetsGeminiTrustWorkspace() {
        let env = EnvironmentBuilder.augmentedEnvironment()
        XCTAssertEqual(env["GEMINI_CLI_TRUST_WORKSPACE"], "true")
    }

    // MARK: - knownBinDirectories order

    func testKnownBinDirectoriesPrioritizesHomebrewOverUsrLocal() {
        let dirs = EnvironmentBuilder.knownBinDirectories(home: "/Users/test")
        let homebrewIdx = dirs.firstIndex(of: "/opt/homebrew/bin")
        let usrLocalIdx = dirs.firstIndex(of: "/usr/local/bin")
        XCTAssertNotNil(homebrewIdx)
        XCTAssertNotNil(usrLocalIdx)
        XCTAssertLessThan(homebrewIdx!, usrLocalIdx!)
    }
}
