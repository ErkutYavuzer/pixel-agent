import XCTest

@testable import PixelTools

final class SystemNotificationsTests: XCTestCase {
    @MainActor
    func testBuildContentHasTitleAndBody() {
        let content = SystemNotifications.buildContent(title: "Başlık", body: "İçerik")
        XCTAssertEqual(content.title, "Başlık")
        XCTAssertEqual(content.body, "İçerik")
        XCTAssertNotNil(content.sound)
    }

    @MainActor
    func testBuildContentPreservesTurkishChars() {
        let content = SystemNotifications.buildContent(
            title: "Şükür çığ üşür",
            body: "İnşallah özgün"
        )
        XCTAssertEqual(content.title, "Şükür çığ üşür")
        XCTAssertEqual(content.body, "İnşallah özgün")
    }
}
