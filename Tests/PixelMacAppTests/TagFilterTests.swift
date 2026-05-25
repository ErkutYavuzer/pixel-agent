import Foundation
import XCTest

@testable import PixelMacApp
@testable import PixelMemory

final class TagFilterTests: XCTestCase {
    private func entry(_ name: String, tags: [String] = []) -> ArchivedConversationEntry {
        ArchivedConversationEntry(
            id: URL(fileURLWithPath: "/tmp/\(name).jsonl"),
            backendKind: "claude",
            archivedAt: Date(),
            messageCount: 1,
            firstUserSnippet: name,
            customTitle: nil,
            tags: tags
        )
    }

    func testEmptyActiveTagsReturnsAll() {
        let entries = [entry("a", tags: ["x"]), entry("b", tags: [])]
        XCTAssertEqual(TagFilter.apply(entries: entries, activeTags: []).count, 2)
    }

    func testSingleTagFiltersToMatchingOnly() {
        let entries = [
            entry("a", tags: ["work"]),
            entry("b", tags: ["personal"]),
            entry("c", tags: []),
        ]
        let result = TagFilter.apply(entries: entries, activeTags: ["work"])
        XCTAssertEqual(result.map(\.firstUserSnippet), ["a"])
    }

    func testMultipleActiveTagsActsAsORUnion() {
        let entries = [
            entry("a", tags: ["work"]),
            entry("b", tags: ["personal"]),
            entry("c", tags: ["other"]),
            entry("d", tags: ["work", "personal"]),
        ]
        let result = TagFilter.apply(entries: entries, activeTags: ["work", "personal"])
        XCTAssertEqual(result.map(\.firstUserSnippet), ["a", "b", "d"])
    }

    func testEntryWithNoTagsExcludedWhenFilterActive() {
        let entries = [entry("untagged", tags: []), entry("tagged", tags: ["work"])]
        let result = TagFilter.apply(entries: entries, activeTags: ["work"])
        XCTAssertEqual(result.map(\.firstUserSnippet), ["tagged"])
    }

    func testFilterPreservesOrder() {
        let entries = [
            entry("first", tags: ["x"]),
            entry("second", tags: ["y"]),
            entry("third", tags: ["x"]),
        ]
        let result = TagFilter.apply(entries: entries, activeTags: ["x"])
        XCTAssertEqual(result.map(\.firstUserSnippet), ["first", "third"])
    }

    func testNoMatchReturnsEmpty() {
        let entries = [entry("a", tags: ["x"])]
        XCTAssertTrue(TagFilter.apply(entries: entries, activeTags: ["unknown"]).isEmpty)
    }
}
