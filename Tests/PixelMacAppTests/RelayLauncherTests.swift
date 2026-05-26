import XCTest
@testable import PixelMacApp

/// **Sprint 47 (v0.2.75):** RelayLauncher state machine smoke tests.
/// Production subprocess yaratmaz (test ortamında relay/ dizini yok ya da
/// stable değil) — sadece UserDefaults toggle + initial state.
@MainActor
final class RelayLauncherTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "test.launcher.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testAutoStartDefaultTrue() {
        // **Sprint 49.1 hot-fix (v0.2.78):** Default tekrar ON — Cloudflare
        // workers.dev cert provisioning yok, fresh install için yerel wrangler
        // gerekli.
        XCTAssertTrue(RelayLauncher.isAutoStartEnabled(defaults: defaults))
    }

    func testAutoStartRespectsFalse() {
        defaults.set(false, forKey: RelayLauncher.autoStartEnabledDefaultsKey)
        XCTAssertFalse(RelayLauncher.isAutoStartEnabled(defaults: defaults))
    }

    func testAutoStartRespectsTrue() {
        defaults.set(true, forKey: RelayLauncher.autoStartEnabledDefaultsKey)
        XCTAssertTrue(RelayLauncher.isAutoStartEnabled(defaults: defaults))
    }

    func testInitialStateNotRunning() {
        let launcher = RelayLauncher()
        XCTAssertFalse(launcher.isRunning)
        XCTAssertNil(launcher.lastError)
        XCTAssertFalse(launcher.didStartOnce)
    }

    func testStartWithoutRelayDirectoryFailsGracefully() {
        // relay/ olmayan bir directory → error set, crash yok.
        // Sprint 49.1: default true geri döndü, ekstra UserDefaults set gerek değil.
        let launcher = RelayLauncher(relayDirectory: URL(fileURLWithPath: "/tmp/nonexistent-dir-\(UUID())"))
        launcher.start()
        XCTAssertFalse(launcher.isRunning)
    }

    func testStopWhenNotRunningNoOp() {
        let launcher = RelayLauncher()
        launcher.stop()  // crash etmemeli
        XCTAssertFalse(launcher.isRunning)
    }

    func testDefaultRelayDirectoryDevPath() {
        // Dev build'de /Users/erkut/Projects/pixel-agent/relay'in olduğu varsayılır.
        // Test ortamında bu dosya yolu repo'da varsa nil değil; yoksa nil.
        let dir = RelayLauncher.defaultRelayDirectory()
        // Best-effort: dosya varsa URL döner, yoksa nil.
        if let dir {
            XCTAssertTrue(dir.absoluteString.contains("relay"))
        }
    }
}
