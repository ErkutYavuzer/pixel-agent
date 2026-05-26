import XCTest
@testable import PixelMacApp

/// **Sprint 48 (v0.2.76):** RelayLauncher writable-copy testleri.
/// Bundle Resources/relay (read-only) → Application Support/relay (writable)
/// kopya mantığı + `isInstallingDependencies` state.
///
/// Production subprocess yaratmaz (npx/npm gerek yok) — yalnızca dosya sistemi
/// yardımcıları + state başlangıç değeri kontrolü.
@MainActor
final class RelayLauncherCopyTests: XCTestCase {
    private var tempRoot: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pixel-relay-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot, fm.fileExists(atPath: tempRoot.path) {
            try? fm.removeItem(at: tempRoot)
        }
        try await super.tearDown()
    }

    // MARK: - writableRelayDirectory URL format

    func testWritableRelayDirectoryUnderApplicationSupport() {
        let url = RelayLauncher.writableRelayDirectory
        // Beklenen: …/Library/Application Support/pixel-agent/relay
        XCTAssertTrue(url.path.hasSuffix("pixel-agent/relay"))
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testWritableRelayDirectoryIsAbsolute() {
        let url = RelayLauncher.writableRelayDirectory
        XCTAssertTrue(url.path.hasPrefix("/"))
    }

    // MARK: - isInstallingDependencies initial state

    func testIsInstallingDependenciesInitiallyFalse() {
        let launcher = RelayLauncher(relayDirectory: URL(fileURLWithPath: "/tmp/nonexistent-\(UUID())"))
        XCTAssertFalse(launcher.isInstallingDependencies)
    }

    // MARK: - ensureWritableCopy: first-time create

    func testEnsureWritableCopyFirstTimeCreatesDestination() throws {
        let source = makeFakeRelay(in: tempRoot, name: "src-first", lockContent: "lock-v1")
        let destination = tempRoot.appendingPathComponent("dst-first", isDirectory: true)
        XCTAssertFalse(fm.fileExists(atPath: destination.path))

        try RelayLauncher.ensureWritableCopy(from: source, to: destination)

        XCTAssertTrue(fm.fileExists(atPath: destination.path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("wrangler.toml").path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("package.json").path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("package-lock.json").path))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("src").path))
    }

    func testEnsureWritableCopyFirstTimeCreatesParentDirectory() throws {
        // Parent (Application Support/pixel-agent) yoksa create etmeli.
        let source = makeFakeRelay(in: tempRoot, name: "src-parent", lockContent: "lock-v1")
        let nestedDestination = tempRoot
            .appendingPathComponent("deep", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("relay", isDirectory: true)

        try RelayLauncher.ensureWritableCopy(from: source, to: nestedDestination)

        XCTAssertTrue(fm.fileExists(atPath: nestedDestination.path))
    }

    // MARK: - ensureWritableCopy: idempotent (same lock → skip)

    func testEnsureWritableCopySkipsWhenPackageLockMatches() throws {
        let source = makeFakeRelay(in: tempRoot, name: "src-same", lockContent: "lock-stable")
        let destination = tempRoot.appendingPathComponent("dst-same", isDirectory: true)
        try RelayLauncher.ensureWritableCopy(from: source, to: destination)

        // Destination'a kullanıcı tarafından eklenmiş ekstra dosya — kopya
        // tekrar çalışırsa silinmemeli (no-op olduğunu kanıtla).
        let userFile = destination.appendingPathComponent("user-marker.txt")
        try "do-not-touch".data(using: .utf8)!.write(to: userFile)

        // Kaynak değişmedi → tekrar çağrı no-op olmalı
        try RelayLauncher.ensureWritableCopy(from: source, to: destination)
        XCTAssertTrue(fm.fileExists(atPath: userFile.path),
                      "package-lock aynıyken kopya skip olmalı; user-marker yerinde kalmalı")
    }

    // MARK: - ensureWritableCopy: lock diff → overwrite

    func testEnsureWritableCopyOverwritesWhenPackageLockDiffers() throws {
        let sourceV1 = makeFakeRelay(in: tempRoot, name: "src-v1", lockContent: "lock-v1", srcMarker: "alpha")
        let destination = tempRoot.appendingPathComponent("dst-versioned", isDirectory: true)
        try RelayLauncher.ensureWritableCopy(from: sourceV1, to: destination)

        // Destination src/index.ts içeriği "alpha" olmalı
        let destSrcIndex = destination.appendingPathComponent("src/index.ts")
        let initialContent = try String(contentsOf: destSrcIndex, encoding: .utf8)
        XCTAssertEqual(initialContent, "// alpha")

        // Yeni versiyon — farklı lock + farklı src
        let sourceV2 = makeFakeRelay(in: tempRoot, name: "src-v2", lockContent: "lock-v2", srcMarker: "bravo")
        try RelayLauncher.ensureWritableCopy(from: sourceV2, to: destination)

        let updatedContent = try String(contentsOf: destSrcIndex, encoding: .utf8)
        XCTAssertEqual(updatedContent, "// bravo", "lock farklıyken src/ üzerine kopyalanmalı")
    }

    func testEnsureWritableCopyPreservesNodeModulesOnUpdate() throws {
        let sourceV1 = makeFakeRelay(in: tempRoot, name: "src-nm-v1", lockContent: "lock-v1")
        let destination = tempRoot.appendingPathComponent("dst-nm", isDirectory: true)
        try RelayLauncher.ensureWritableCopy(from: sourceV1, to: destination)

        // npm install simülasyonu — destination'a node_modules ekle
        let nodeModules = destination.appendingPathComponent("node_modules")
        try fm.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        let installedDep = nodeModules.appendingPathComponent("wrangler/package.json")
        try fm.createDirectory(at: installedDep.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try "{}".data(using: .utf8)!.write(to: installedDep)

        // Yeni versiyon kopyala — node_modules dokunulmamalı
        let sourceV2 = makeFakeRelay(in: tempRoot, name: "src-nm-v2", lockContent: "lock-v2")
        try RelayLauncher.ensureWritableCopy(from: sourceV2, to: destination)

        XCTAssertTrue(fm.fileExists(atPath: installedDep.path),
                      "node_modules ensureWritableCopy tarafından silinmemeli")
    }

    // MARK: - ensureWritableCopy: optional README

    func testEnsureWritableCopySkipsMissingReadme() throws {
        // README olmadan source — copy hata vermemeli.
        let source = makeFakeRelay(in: tempRoot, name: "src-no-readme",
                                   lockContent: "lock", includeReadme: false)
        let destination = tempRoot.appendingPathComponent("dst-no-readme", isDirectory: true)

        XCTAssertNoThrow(try RelayLauncher.ensureWritableCopy(from: source, to: destination))
        XCTAssertTrue(fm.fileExists(atPath: destination.appendingPathComponent("package.json").path))
        XCTAssertFalse(fm.fileExists(atPath: destination.appendingPathComponent("README.md").path))
    }

    // MARK: - Helpers

    /// Test için sahte bir `relay/` kaynak dizini oluştur.
    /// İçerik: wrangler.toml + package.json + package-lock.json + src/index.ts [+ README.md].
    private func makeFakeRelay(in parent: URL,
                               name: String,
                               lockContent: String,
                               srcMarker: String = "alpha",
                               includeReadme: Bool = true) -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "name = \"pixel-relay\"\n".data(using: .utf8)?
            .write(to: dir.appendingPathComponent("wrangler.toml"))
        try? "{\"name\":\"pixel-relay\"}".data(using: .utf8)?
            .write(to: dir.appendingPathComponent("package.json"))
        try? lockContent.data(using: .utf8)?
            .write(to: dir.appendingPathComponent("package-lock.json"))

        let srcDir = dir.appendingPathComponent("src", isDirectory: true)
        try? fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try? "// \(srcMarker)".data(using: .utf8)?
            .write(to: srcDir.appendingPathComponent("index.ts"))

        if includeReadme {
            try? "# pixel-relay".data(using: .utf8)?
                .write(to: dir.appendingPathComponent("README.md"))
        }
        return dir
    }
}
