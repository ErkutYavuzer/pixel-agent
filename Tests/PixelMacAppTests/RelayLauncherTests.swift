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

    func testAutoStartDefaultFalse() {
        // **Sprint 49 (v0.2.77):** Default OFF — production Cloudflare URL
        // hardcoded artık, lokal wrangler subprocess opsiyonel. Kullanıcı
        // offline/dev için manuel açabilir.
        XCTAssertFalse(RelayLauncher.isAutoStartEnabled(defaults: defaults))
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
        // **Sprint 49:** Default auto-start OFF → start() no-op olur.
        // Auto-start'i explicit ON yapıp yine de relay/ yokken graceful fail
        // edebildiğini kontrol et.
        UserDefaults.standard.set(true, forKey: RelayLauncher.autoStartEnabledDefaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: RelayLauncher.autoStartEnabledDefaultsKey)
        }
        let launcher = RelayLauncher(relayDirectory: URL(fileURLWithPath: "/tmp/nonexistent-dir-\(UUID())"))
        launcher.start()
        // start() çağrısı başarısız oldu; crash yok
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
