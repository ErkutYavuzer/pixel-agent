import XCTest

@testable import PixelMacApp

final class AppCommandTests: XCTestCase {

    func testAllCasesPresent() {
        // B5 demo senaryosu için sabit üç komut. Sayı değişirse PixelMacApp.swift
        // `.commands { ... }` bloku da güncellenmiş olmalı.
        XCTAssertEqual(AppCommand.allCases.count, 3)
        XCTAssertTrue(AppCommand.allCases.contains(.newConversation))
        XCTAssertTrue(AppCommand.allCases.contains(.togglePlanMode))
        XCTAssertTrue(AppCommand.allCases.contains(.toggleChatMode))
    }

    func testRawValuesAreUnique() {
        let raws = AppCommand.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "Duplicate raw value var")
    }

    func testRawValuesNamespaced() {
        // NotificationCenter global isim alanı — çakışmayı önlemek için tüm
        // command isimleri `pixel.command.` prefix'iyle başlamalı.
        for command in AppCommand.allCases {
            XCTAssertTrue(command.rawValue.hasPrefix("pixel.command."),
                          "\(command) için prefix eksik: \(command.rawValue)")
        }
    }

    func testNotificationNameMatchesRawValue() {
        for command in AppCommand.allCases {
            XCTAssertEqual(command.notificationName.rawValue, command.rawValue)
        }
    }

    func testPostDispatchesObservableNotification() {
        // post() çağrısının gerçekten NotificationCenter'a düştüğünü doğrula —
        // observer set up et, post() çağır, expectation fire et.
        let exp = expectation(description: "newConversation notification")
        let observer = NotificationCenter.default.addObserver(
            forName: AppCommand.newConversation.notificationName,
            object: nil,
            queue: .main
        ) { _ in
            exp.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        AppCommand.newConversation.post()
        wait(for: [exp], timeout: 0.5)
    }
}
