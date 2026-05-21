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
}
