import Foundation
import XCTest

@testable import PixelMemory

final class ArchiveTagsStoreTests: XCTestCase {
    var testDir: URL!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-agent-tags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let testDir { try? FileManager.default.removeItem(at: testDir) }
        testDir = nil
    }

    func testLoadReturnsEmptyWhenNoFile() {
        XCTAssertTrue(ArchiveTagsStore.load(directory: testDir).isEmpty)
    }

    func testLoadReturnsEmptyForCorruptJSON() throws {
        try Data("not json".utf8).write(to: ArchiveTagsStore.fileURL(in: testDir))
        XCTAssertTrue(ArchiveTagsStore.load(directory: testDir).isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        let original: [String: [String]] = [
            "conversation-claude-2026-05-25T10-00-00.000Z.jsonl": ["important", "work"],
            "conversation-codex-2026-05-25T11-00-00.000Z.jsonl": ["personal"],
        ]
        try ArchiveTagsStore.save(original, directory: testDir)
        XCTAssertEqual(ArchiveTagsStore.load(directory: testDir), original)
    }

    func testSetTagsAddsKey() throws {
        try ArchiveTagsStore.setTags(["a", "b"], for: "x.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTagsStore.load(directory: testDir), ["x.jsonl": ["a", "b"]])
    }

    func testSetTagsNilRemovesKey() throws {
        try ArchiveTagsStore.save(["x.jsonl": ["a"], "y.jsonl": ["b"]], directory: testDir)
        try ArchiveTagsStore.setTags(nil, for: "x.jsonl", directory: testDir)
        XCTAssertEqual(ArchiveTagsStore.load(directory: testDir), ["y.jsonl": ["b"]])
    }

    func testSetTagsEmptyArrayRemovesKey() throws {
        try ArchiveTagsStore.save(["x.jsonl": ["a"]], directory: testDir)
        try ArchiveTagsStore.setTags([], for: "x.jsonl", directory: testDir)
        XCTAssertTrue(ArchiveTagsStore.load(directory: testDir).isEmpty)
    }

    func testAllTagsUnionSorted() throws {
        try ArchiveTagsStore.save([
            "a.jsonl": ["z", "a"],
            "b.jsonl": ["m", "a", "x"],
            "c.jsonl": [],
        ], directory: testDir)
        XCTAssertEqual(ArchiveTagsStore.allTags(directory: testDir), ["a", "m", "x", "z"])
    }

    func testAllTagsEmptyWhenNoSidecar() {
        XCTAssertTrue(ArchiveTagsStore.allTags(directory: testDir).isEmpty)
    }
}
