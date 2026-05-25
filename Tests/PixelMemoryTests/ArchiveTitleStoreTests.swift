import Foundation
import XCTest

@testable import PixelMemory

final class ArchiveTitleStoreTests: XCTestCase {
    var testDir: URL!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-agent-titles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let testDir { try? FileManager.default.removeItem(at: testDir) }
        testDir = nil
    }

    func testLoadReturnsEmptyWhenNoFile() {
        let titles = ArchiveTitleStore.load(directory: testDir)
        XCTAssertTrue(titles.isEmpty)
    }

    func testLoadReturnsEmptyForCorruptJSON() throws {
        let url = ArchiveTitleStore.fileURL(in: testDir)
        try Data("{not valid json".utf8).write(to: url)
        let titles = ArchiveTitleStore.load(directory: testDir)
        XCTAssertTrue(titles.isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        let original = [
            "conversation-claude-2026-05-25T10-00-00.000Z.jsonl": "Sprint planlaması",
            "conversation-codex-2026-05-25T11-00-00.000Z.jsonl": "Refactor brainstorm",
        ]
        try ArchiveTitleStore.save(original, directory: testDir)
        let loaded = ArchiveTitleStore.load(directory: testDir)
        XCTAssertEqual(loaded, original)
    }

    func testSetTitleAddsKey() throws {
        try ArchiveTitleStore.setTitle("Yeni başlık", for: "a.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTitleStore.load(directory: testDir), ["a.jsonl": "Yeni başlık"])
    }

    func testSetTitleTrimsWhitespace() throws {
        try ArchiveTitleStore.setTitle("   trimmed   ", for: "a.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTitleStore.load(directory: testDir)["a.jsonl"], "trimmed")
    }

    func testSetTitleNilRemovesKey() throws {
        try ArchiveTitleStore.save(["a.jsonl": "x", "b.jsonl": "y"], directory: testDir)
        try ArchiveTitleStore.setTitle(nil, for: "a.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTitleStore.load(directory: testDir), ["b.jsonl": "y"])
    }

    func testSetTitleEmptyRemovesKey() throws {
        try ArchiveTitleStore.save(["a.jsonl": "x"], directory: testDir)
        try ArchiveTitleStore.setTitle("", for: "a.jsonl", directory: testDir)
        XCTAssertTrue(ArchiveTitleStore.load(directory: testDir).isEmpty)
    }

    func testSetTitleWhitespaceOnlyRemovesKey() throws {
        try ArchiveTitleStore.save(["a.jsonl": "x"], directory: testDir)
        try ArchiveTitleStore.setTitle("   \n\t  ", for: "a.jsonl", directory: testDir)
        XCTAssertTrue(ArchiveTitleStore.load(directory: testDir).isEmpty)
    }

    func testRemoveNonexistentKeyIsNoop() throws {
        try ArchiveTitleStore.save(["a.jsonl": "x"], directory: testDir)
        try ArchiveTitleStore.setTitle(nil, for: "ghost.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTitleStore.load(directory: testDir), ["a.jsonl": "x"])
    }
}
