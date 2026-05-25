import Foundation
import XCTest

@testable import PixelMacApp
@testable import PixelMemory

final class ArchiveTitleResolverTests: XCTestCase {
    private func entry(
        custom: String? = nil,
        snippet: String? = nil
    ) -> ArchivedConversationEntry {
        ArchivedConversationEntry(
            id: URL(fileURLWithPath: "/tmp/conversation-claude-2026-05-25T10-00-00.000Z.jsonl"),
            backendKind: "claude",
            archivedAt: Date(timeIntervalSince1970: 1_716_550_000),
            messageCount: 3,
            firstUserSnippet: snippet,
            customTitle: custom
        )
    }

    func testCustomTitleWins() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: "Custom", snippet: "Snippet")),
            "Custom"
        )
    }

    func testFallsBackToSnippetWhenCustomNil() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: nil, snippet: "From snippet")),
            "From snippet"
        )
    }

    func testFallsBackToSnippetWhenCustomEmpty() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: "", snippet: "Snippet")),
            "Snippet"
        )
    }

    func testFallsBackToSnippetWhenCustomWhitespaceOnly() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: "   \n", snippet: "Snippet")),
            "Snippet"
        )
    }

    func testPlaceholderWhenBothNil() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: nil, snippet: nil)),
            ArchiveTitleResolver.placeholder
        )
    }

    func testPlaceholderWhenBothEmpty() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: "", snippet: "  ")),
            ArchiveTitleResolver.placeholder
        )
    }

    func testTrimsCustomTitleWhitespace() {
        XCTAssertEqual(
            ArchiveTitleResolver.displayTitle(for: entry(custom: "  padded  ", snippet: nil)),
            "padded"
        )
    }

    func testPlaceholderConstantIsStable() {
        XCTAssertEqual(ArchiveTitleResolver.placeholder, "(başlıksız)")
    }
}
