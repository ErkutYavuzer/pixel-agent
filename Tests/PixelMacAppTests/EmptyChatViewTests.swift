import XCTest

@testable import PixelMacApp

final class EmptyChatViewTests: XCTestCase {

    func testSuggestedPromptsAreNonEmpty() {
        XCTAssertFalse(EmptyChatView.suggestedPrompts.isEmpty)
        XCTAssertGreaterThanOrEqual(EmptyChatView.suggestedPrompts.count, 3,
            "En az 3 prompt chip beklenir (görsel grid hissi için).")
    }

    func testSuggestedPromptsHaveUniqueIDs() {
        let ids = EmptyChatView.suggestedPrompts.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "PromptChip ID'leri benzersiz olmalı.")
    }

    func testSuggestedPromptsHaveNonEmptyLabelAndPrompt() {
        for chip in EmptyChatView.suggestedPrompts {
            XCTAssertFalse(chip.label.isEmpty, "Chip label boş olmamalı: \(chip.id)")
            XCTAssertFalse(chip.prompt.isEmpty, "Chip prompt boş olmamalı: \(chip.id)")
            XCTAssertFalse(chip.icon.isEmpty, "Chip icon boş olmamalı: \(chip.id)")
        }
    }

    func testSuggestedPromptsCoverKeyWorkflows() {
        // Demo senaryosunun gerektirdiği 4 ana kullanım vakası prompt setinde
        // temsil edilmeli — her birinin ID'si stable, regression için referans.
        let expectedIDs: Set<String> = [
            "summarize-folder",
            "code-review",
            "plan-research",
            "subagent-compare",
        ]
        let actualIDs = Set(EmptyChatView.suggestedPrompts.map(\.id))
        XCTAssertTrue(expectedIDs.isSubset(of: actualIDs),
            "Beklenen workflow chip'leri eksik: \(expectedIDs.subtracting(actualIDs))")
    }

    func testPromptChipEquatableComparesByID() {
        let a = PromptChip(id: "x", label: "A", icon: "star", prompt: "p")
        let b = PromptChip(id: "x", label: "A", icon: "star", prompt: "p")
        let c = PromptChip(id: "y", label: "A", icon: "star", prompt: "p")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
