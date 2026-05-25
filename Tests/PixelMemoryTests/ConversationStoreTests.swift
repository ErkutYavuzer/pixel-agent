import Foundation
import XCTest

@testable import PixelCore
@testable import PixelMemory

final class ConversationStoreTests: XCTestCase {
    var testDir: URL!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-agent-test-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        if let testDir {
            try? FileManager.default.removeItem(at: testDir)
        }
        testDir = nil
    }

    func testAppendAndLoadRoundTrip() async throws {
        let store = try ConversationStore(directory: testDir)
        let msg1 = Message(role: .user, text: "Merhaba")
        let msg2 = Message(role: .assistant, text: "Selam")
        let msg3 = Message(role: .user, text: "Nasılsın?")

        try await store.append(msg1)
        try await store.append(msg2)
        try await store.append(msg3)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.id), [msg1.id, msg2.id, msg3.id])
        XCTAssertEqual(loaded.map(\.text), ["Merhaba", "Selam", "Nasılsın?"])
    }

    func testLoadAllReturnsEmptyForFreshStore() async throws {
        let store = try ConversationStore(directory: testDir)
        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadAllLimitReturnsLastN() async throws {
        let store = try ConversationStore(directory: testDir)
        for index in 0..<10 {
            try await store.append(Message(role: .user, text: "msg \(index)"))
        }
        let loaded = try await store.loadAll(limit: 3)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.map(\.text), ["msg 7", "msg 8", "msg 9"])
    }

    // MARK: - Sprint 6 (B2) — rename
    //
    // `listAllArchives` parser kind'lı filename bekler (`conversation-<kind>-<stamp>.jsonl`);
    // bu yüzden bu testler `fileName: "conversation-claude.jsonl"` ile init eder.

    func testRenameArchiveReflectsInListAllArchives() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "rename me"))
        try await store.newConversation()

        var entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].customTitle)

        try await store.renameArchive(at: entries[0].id, title: "Custom başlık")

        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries[0].customTitle, "Custom başlık")
        XCTAssertEqual(entries[0].backendKind, "claude")
    }

    func testRenameArchiveStaticOverloadWorks() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-codex.jsonl")
        try await store.append(Message(role: .user, text: "static test"))
        try await store.newConversation()

        var entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 1)
        try ConversationStore.renameArchive(at: entries[0].id, title: "Via static", directory: testDir)
        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries[0].customTitle, "Via static")
    }

    func testRenameArchiveWithNilClearsTitle() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-gemini.jsonl")
        try await store.append(Message(role: .user, text: "clear me"))
        try await store.newConversation()

        var entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 1)
        try await store.renameArchive(at: entries[0].id, title: "First")
        try await store.renameArchive(at: entries[0].id, title: nil)
        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertNil(entries[0].customTitle)
    }

    // MARK: - Sprint 7 (B2) — tags

    func testSetTagsReflectsInListAllArchives() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "tagged"))
        try await store.newConversation()

        var entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].tags.isEmpty)

        try await store.setTags(["work", "important"], for: entries[0].id)
        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries[0].tags, ["work", "important"])
    }

    func testSetTagsStaticOverloadWorks() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-codex.jsonl")
        try await store.append(Message(role: .user, text: "via static"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        try ConversationStore.setTags(["x"], for: entries[0].id, directory: testDir)
        let refreshed = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(refreshed[0].tags, ["x"])
    }

    func testSetTagsNilOrEmptyClears() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-gemini.jsonl")
        try await store.append(Message(role: .user, text: "clear"))
        try await store.newConversation()

        var entries = try ConversationStore.listAllArchives(directory: testDir)
        try await store.setTags(["a", "b"], for: entries[0].id)
        try await store.setTags(nil, for: entries[0].id)
        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertTrue(entries[0].tags.isEmpty)

        try await store.setTags(["a"], for: entries[0].id)
        try await store.setTags([], for: entries[0].id)
        entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertTrue(entries[0].tags.isEmpty)
    }

    func testListAllTagsReturnsUnion() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "first"))
        try await store.newConversation()
        try await Task.sleep(for: .milliseconds(50))
        try await store.append(Message(role: .user, text: "second"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 2)
        try await store.setTags(["work", "urgent"], for: entries[0].id)
        try await store.setTags(["personal", "work"], for: entries[1].id)

        XCTAssertEqual(
            ConversationStore.listAllTags(directory: testDir),
            ["personal", "urgent", "work"]
        )
    }

    func testListAllArchivesPreservesUntitledEntries() async throws {
        let store = try ConversationStore(directory: testDir, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "first"))
        try await store.newConversation()
        // ms timestamp collision'ı önle.
        try await Task.sleep(for: .milliseconds(50))
        try await store.append(Message(role: .user, text: "second"))
        try await store.newConversation()

        let entries = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(entries.count, 2)
        guard entries.count == 2 else { return }
        try await store.renameArchive(at: entries[0].id, title: "Only first")

        let refreshed = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(refreshed.count, 2)
        let titled = refreshed.filter { $0.customTitle != nil }
        XCTAssertEqual(titled.count, 1)
        XCTAssertEqual(titled.first?.customTitle, "Only first")
    }

    func testNewConversationArchivesAndEmpties() async throws {
        let store = try ConversationStore(directory: testDir)
        try await store.append(Message(role: .user, text: "before"))
        try await store.append(Message(role: .assistant, text: "yeah"))

        let countBefore = try await store.messageCount()
        XCTAssertEqual(countBefore, 2)

        try await store.newConversation()

        let countAfter = try await store.messageCount()
        XCTAssertEqual(countAfter, 0)

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)

        let archiveURL = testDir.appendingPathComponent("archive")
        let archived = try FileManager.default.contentsOfDirectory(atPath: archiveURL.path)
        XCTAssertGreaterThan(archived.count, 0)
    }

    func testNewConversationOnEmptyDoesNotArchive() async throws {
        let store = try ConversationStore(directory: testDir)
        try await store.newConversation()

        let archiveURL = testDir.appendingPathComponent("archive")
        let archived = try FileManager.default.contentsOfDirectory(atPath: archiveURL.path)
        XCTAssertEqual(archived.count, 0)
    }

    func testCorruptedLineSkippedDuringLoad() async throws {
        let store = try ConversationStore(directory: testDir)
        try await store.append(Message(role: .user, text: "ok"))

        let fileURL = await store.fileURL
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        if let bad = "this is not json\n".data(using: .utf8) {
            try handle.write(contentsOf: bad)
        }
        try handle.close()

        try await store.append(Message(role: .assistant, text: "after"))

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.text), ["ok", "after"])
    }

    func testMessageCountAccurate() async throws {
        let store = try ConversationStore(directory: testDir)
        let c0 = try await store.messageCount()
        XCTAssertEqual(c0, 0)

        try await store.append(Message(role: .user, text: "1"))
        let c1 = try await store.messageCount()
        XCTAssertEqual(c1, 1)

        try await store.append(Message(role: .user, text: "2"))
        let c2 = try await store.messageCount()
        XCTAssertEqual(c2, 2)
    }

    // MARK: - Sprint 4 (B2 follow-up): replaceWithArchive

    func testReplaceWithArchiveSwapsActiveJSONL() async throws {
        let store = try ConversationStore(
            directory: testDir,
            fileName: "conversation-claude.jsonl"
        )

        // 1. Bir konuşma yap ve arşivle (newConversation tetikler).
        try await store.append(Message(role: .user, text: "ilk soru"))
        try await store.append(Message(role: .assistant, text: "ilk cevap"))
        try await store.newConversation()

        // 2. Yeni aktif konuşma — farklı içerik.
        try await store.append(Message(role: .user, text: "ikinci soru"))
        let beforeReplace = try await store.loadAll()
        XCTAssertEqual(beforeReplace.map(\.text), ["ikinci soru"])

        // 3. Arşivi listele, ilkini yükle.
        let archives = try ConversationStore.listAllArchives(directory: testDir)
        guard let first = archives.first else {
            return XCTFail("Beklenen: en az bir arşiv var")
        }
        try await store.replaceWithArchive(first)

        // 4. Aktif store artık ilk konuşmanın mesajlarını içermeli.
        let afterReplace = try await store.loadAll()
        XCTAssertEqual(afterReplace.map(\.text), ["ilk soru", "ilk cevap"])

        // 5. "ikinci soru" da yeni archive girişine taşınmış olmalı.
        let archivesAfter = try ConversationStore.listAllArchives(directory: testDir)
        XCTAssertEqual(archivesAfter.count, 2)
    }

    func testReplaceWithArchiveOnEmptyActiveJSONL() async throws {
        // Aktif store boşken replace çalışmalı — newConversation boş dosyada
        // no-op (rename yapmaz), sonra archive içeriği aktif'e yazılır.
        let store = try ConversationStore(
            directory: testDir,
            fileName: "conversation-claude.jsonl"
        )

        // Boş bir arşiv yaratmak için: önce bir konuşma, arşivle, sonra
        // yeni aktif boş bırak.
        try await store.append(Message(role: .user, text: "x"))
        try await store.newConversation()
        // Şu an active boş, archive dolu.

        let archives = try ConversationStore.listAllArchives(directory: testDir)
        guard let first = archives.first else { return XCTFail("Arşiv yok") }

        try await store.replaceWithArchive(first)
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.map(\.text), ["x"])
    }
}
