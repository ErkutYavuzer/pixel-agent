import XCTest

@testable import PixelMacApp

final class SettingsTabTests: XCTestCase {

    func testAllCasesPresent() {
        // B1 demo senaryosu için sabit tab seti. Eklenirse hem enum hem
        // SettingsView switch'i güncellenmiş olmalı.
        // Sprint 14 (v0.2.39): subagent 5. tab eklendi.
        XCTAssertEqual(SettingsTab.allCases.count, 5)
        XCTAssertTrue(SettingsTab.allCases.contains(.general))
        XCTAssertTrue(SettingsTab.allCases.contains(.models))
        XCTAssertTrue(SettingsTab.allCases.contains(.connection))
        XCTAssertTrue(SettingsTab.allCases.contains(.subagent))
        XCTAssertTrue(SettingsTab.allCases.contains(.permissions))
    }

    func testEachTabHasNonEmptyTitleAndIcon() {
        for tab in SettingsTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "title boş: \(tab)")
            XCTAssertFalse(tab.systemImage.isEmpty, "systemImage boş: \(tab)")
        }
    }

    func testTitlesAreUnique() {
        let titles = SettingsTab.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "Duplicate title")
    }

    func testIconsAreUnique() {
        let icons = SettingsTab.allCases.map(\.systemImage)
        XCTAssertEqual(Set(icons).count, icons.count, "Duplicate icon")
    }

    func testRawValuesAreLowercased() {
        // Identifiable id = rawValue; case-stable, URL-safe karakterler.
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.rawValue, tab.rawValue.lowercased(),
                           "rawValue lowercase değil: \(tab)")
        }
    }

    func testIdEqualsRawValue() {
        for tab in SettingsTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }
}
