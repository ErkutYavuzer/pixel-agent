import Foundation
import XCTest

@testable import PixelMemory

final class ScreenshotStoreTests: XCTestCase {

    var testDir: URL!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-screenshot-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let testDir {
            try? FileManager.default.removeItem(at: testDir)
        }
        testDir = nil
    }

    // MARK: - Save + load round trip

    func testSaveAndLoadRoundTrip() throws {
        let id = UUID()
        // Minimal valid PNG header (8 byte signature) - data fidelity test için yeterli.
        let payload = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  // PNG signature
            0x00, 0x01, 0x02, 0x03  // dummy payload
        ])
        try ScreenshotStore.save(pngData: payload, for: id, directory: testDir)
        let loaded = try ScreenshotStore.load(for: id, directory: testDir)
        XCTAssertEqual(loaded, payload)
    }

    func testLoadReturnsNilForMissingFile() throws {
        let id = UUID()
        let loaded = try ScreenshotStore.load(for: id, directory: testDir)
        XCTAssertNil(loaded)
    }

    func testSaveCreatesDirectoryIfMissing() throws {
        let nested = testDir.appendingPathComponent("nested/deep", isDirectory: true)
        let id = UUID()
        let payload = Data([1, 2, 3])
        try ScreenshotStore.save(pngData: payload, for: id, directory: nested)
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    // MARK: - Delete

    func testDeleteRemovesFile() throws {
        let id = UUID()
        try ScreenshotStore.save(pngData: Data([1, 2, 3]), for: id, directory: testDir)
        XCTAssertNotNil(try ScreenshotStore.load(for: id, directory: testDir))

        try ScreenshotStore.delete(for: id, directory: testDir)
        XCTAssertNil(try ScreenshotStore.load(for: id, directory: testDir))
    }

    func testDeleteIsIdempotent() throws {
        // Olmayan dosya için delete throw etmemeli.
        let id = UUID()
        XCTAssertNoThrow(try ScreenshotStore.delete(for: id, directory: testDir))
    }

    // MARK: - Purge orphans

    func testPurgeOrphansRemovesOnlyNonActiveFiles() throws {
        let keep1 = UUID()
        let keep2 = UUID()
        let orphan = UUID()

        let dummy = Data([0x89, 0x50])  // PNG-ish stub
        try ScreenshotStore.save(pngData: dummy, for: keep1, directory: testDir)
        try ScreenshotStore.save(pngData: dummy, for: keep2, directory: testDir)
        try ScreenshotStore.save(pngData: dummy, for: orphan, directory: testDir)

        let removed = try ScreenshotStore.purgeOrphans(
            keeping: [keep1, keep2],
            directory: testDir
        )
        XCTAssertEqual(removed, 1)
        XCTAssertNotNil(try ScreenshotStore.load(for: keep1, directory: testDir))
        XCTAssertNotNil(try ScreenshotStore.load(for: keep2, directory: testDir))
        XCTAssertNil(try ScreenshotStore.load(for: orphan, directory: testDir))
    }

    func testPurgeOrphansNoOpOnEmptyDirectory() throws {
        let removed = try ScreenshotStore.purgeOrphans(
            keeping: [UUID()],
            directory: testDir
        )
        XCTAssertEqual(removed, 0)
    }

    func testPurgeIgnoresNonPNGFiles() throws {
        try FileManager.default.createDirectory(
            at: testDir, withIntermediateDirectories: true
        )
        let txtURL = testDir.appendingPathComponent("notes.txt")
        try "hello".write(to: txtURL, atomically: true, encoding: .utf8)

        let removed = try ScreenshotStore.purgeOrphans(
            keeping: [],
            directory: testDir
        )
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: txtURL.path))
    }
}
