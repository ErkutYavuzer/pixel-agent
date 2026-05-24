import XCTest
import PixelCore

@testable import PixelMemory

final class ArchivedConversationTests: XCTestCase {

    // MARK: - Filename parser

    func testParseClaudeFilename() throws {
        let parsed = ArchivedConversationParser.parseFilename(
            "conversation-claude-2026-05-24T10-30-15Z.jsonl"
        )
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.kind, "claude")

        // 2026-05-24T10:30:15Z
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let expected = formatter.date(from: "2026-05-24T10:30:15Z")
        XCTAssertEqual(parsed?.date, expected)
    }

    func testParseCodexFilename() {
        let parsed = ArchivedConversationParser.parseFilename(
            "conversation-codex-2026-01-15T08-00-00Z.jsonl"
        )
        XCTAssertEqual(parsed?.kind, "codex")
        XCTAssertNotNil(parsed?.date)
    }

    func testParseGeminiFilename() {
        let parsed = ArchivedConversationParser.parseFilename(
            "conversation-gemini-2026-12-31T23-59-59Z.jsonl"
        )
        XCTAssertEqual(parsed?.kind, "gemini")
    }

    func testParseInvalidFilenamesReturnsNil() {
        XCTAssertNil(ArchivedConversationParser.parseFilename(""))
        XCTAssertNil(ArchivedConversationParser.parseFilename("random.txt"))
        XCTAssertNil(ArchivedConversationParser.parseFilename("conversation.jsonl"))
        XCTAssertNil(ArchivedConversationParser.parseFilename("conversation-claude.jsonl"))
        XCTAssertNil(ArchivedConversationParser.parseFilename("conversation-claude-not-a-date.jsonl"))
    }

    func testParseHandlesUnknownBackendKind() {
        // Forward-compat: yeni bir CLIKind eklenirse parse'i geçecek; UI
        // tarafı capitalize fallback ile gösterir.
        let parsed = ArchivedConversationParser.parseFilename(
            "conversation-qwen-2026-05-24T10-30-15Z.jsonl"
        )
        XCTAssertEqual(parsed?.kind, "qwen")
    }

    // MARK: - First user snippet

    func testFirstUserSnippetReturnsFirstUserText() {
        let messages = [
            Message(role: .system, text: "sys init"),
            Message(role: .user, text: "Hello, how are you?"),
            Message(role: .assistant, text: "I'm well, thanks."),
            Message(role: .user, text: "Tell me more."),
        ]
        XCTAssertEqual(
            ArchivedConversationParser.firstUserSnippet(messages: messages),
            "Hello, how are you?"
        )
    }

    func testFirstUserSnippetTruncatesLongText() {
        let longText = String(repeating: "x", count: 200)
        let messages = [Message(role: .user, text: longText)]
        let snippet = ArchivedConversationParser.firstUserSnippet(messages: messages)
        XCTAssertEqual(snippet?.count, 61) // 60 + "…"
        XCTAssertTrue(snippet?.hasSuffix("…") == true)
    }

    func testFirstUserSnippetSkipsEmptyUser() {
        let messages = [
            Message(role: .user, text: "   "),
            Message(role: .user, text: "actual content"),
        ]
        XCTAssertEqual(
            ArchivedConversationParser.firstUserSnippet(messages: messages),
            "actual content"
        )
    }

    func testFirstUserSnippetReturnsNilWhenNoUserMessages() {
        let messages = [
            Message(role: .system, text: "sys"),
            Message(role: .assistant, text: "robot"),
        ]
        XCTAssertNil(ArchivedConversationParser.firstUserSnippet(messages: messages))
    }

    // MARK: - End-to-end listing via temp directory

    func testListAllArchivesFromTempDirectory() async throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-archive-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        // Create a ConversationStore and archive a conversation manually.
        let store = try ConversationStore(directory: tmpRoot, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "merhaba"))
        try await store.append(Message(role: .assistant, text: "selam"))
        try await store.newConversation()

        // Now there should be 1 archived file.
        let archives = try ConversationStore.listAllArchives(directory: tmpRoot)
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(archives.first?.backendKind, "claude")
        XCTAssertEqual(archives.first?.messageCount, 2)
        XCTAssertEqual(archives.first?.firstUserSnippet, "merhaba")
    }

    func testListAllArchivesEmptyDirectoryReturnsEmpty() throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-archive-empty-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        // Without creating any archive — directory might not even exist.
        let result = try ConversationStore.listAllArchives(directory: tmpRoot)
        XCTAssertTrue(result.isEmpty)
    }

    func testListAllArchivesSortsByDateDescending() async throws {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("pixel-archive-sort-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        let store = try ConversationStore(directory: tmpRoot, fileName: "conversation-claude.jsonl")
        try await store.append(Message(role: .user, text: "ilk"))
        try await store.newConversation()

        // ConversationStore'un kendisi içinde delay yok; ms-precision'da
        // arşiv adları farklı olmayabilir. Sleep ile garanti.
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        try await store.append(Message(role: .user, text: "ikinci"))
        try await store.newConversation()

        let archives = try ConversationStore.listAllArchives(directory: tmpRoot)
        XCTAssertEqual(archives.count, 2)
        XCTAssertGreaterThan(archives[0].archivedAt, archives[1].archivedAt,
                             "En yeni arşiv ilk sırada olmalı")
    }
}
