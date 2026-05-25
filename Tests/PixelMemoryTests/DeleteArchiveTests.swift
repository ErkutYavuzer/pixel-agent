import Foundation
import XCTest

@testable import PixelCore
@testable import PixelMemory

final class DeleteArchiveTests: XCTestCase {
    var testDir: URL!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-agent-delete-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let testDir { try? FileManager.default.removeItem(at: testDir) }
        testDir = nil
    }

    func testDeleteArchiveRemovesFile() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "to delete"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 1)

        try ConversationStore.deleteArchive(at: entries[0].id, directory: testDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: entries[0].id.path))
        let after = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(after.count, 0)
    }

    func testDeleteArchiveClearsSidecarEntries() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "tagged + titled"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        try await store.renameArchive(at: entries[0].id, title: "Önemli")
        try await store.setTags(["work", "urgent"], for: entries[0].id)

        // Sidecar entry'leri kayıtlı olmalı.
        let archiveDir = testDir.appendingPathComponent("archive", isDirectory: true)
        XCTAssertNotNil(
            ArchiveTitleStore.load(directory: archiveDir)[entries[0].id.lastPathComponent]
        )
        XCTAssertNotNil(
            ArchiveTagsStore.load(directory: archiveDir)[entries[0].id.lastPathComponent]
        )

        try ConversationStore.deleteArchive(at: entries[0].id, directory: testDir)

        // Sidecar entry'leri temizlenmiş olmalı.
        XCTAssertNil(
            ArchiveTitleStore.load(directory: archiveDir)[entries[0].id.lastPathComponent]
        )
        XCTAssertNil(
            ArchiveTagsStore.load(directory: archiveDir)[entries[0].id.lastPathComponent]
        )
    }

    func testDeleteArchiveIsIdempotentOnMissingFile() {
        let ghostURL = testDir
            .appendingPathComponent("archive", isDirectory: true)
            .appendingPathComponent("conversation-claude-2026-05-25T00-00-00.000Z.jsonl")
        XCTAssertNoThrow(
            try ConversationStore.deleteArchive(at: ghostURL, directory: testDir)
        )
    }

    func testDeleteArchivePreservesOtherEntries() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "first"))
        try await store.newConversation()
        try await Task.sleep(for: .milliseconds(50))
        try await store.append(Message(role: .user, text: "second"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 2)
        // İlkini sil; ikincisi kalmalı.
        try ConversationStore.deleteArchive(at: entries[0].id, directory: testDir)
        let after = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].id, entries[1].id)
    }
}
