import XCTest
@testable import PixelMacApp

/// **Sprint 40 (v0.2.67):** ProactiveTrigger userInfoPayload encode/decode
/// round-trip + edge case tests.
final class TriggerUserInfoEncodingTests: XCTestCase {

    func testIdleRoundTrip() {
        let original = ProactiveTrigger.idle(minutes: 15)
        let payload = original.userInfoPayload()
        XCTAssertEqual(payload["kind"], "idle")
        XCTAssertEqual(payload["minutes"], "15")
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testAppChangedRoundTrip() {
        let original = ProactiveTrigger.appChanged(name: "Safari", bundleID: "com.apple.Safari")
        let payload = original.userInfoPayload()
        XCTAssertEqual(payload["kind"], "appChange")
        XCTAssertEqual(payload["app"], "Safari")
        XCTAssertEqual(payload["bundleID"], "com.apple.Safari")
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testWindowDwellRoundTrip() {
        let original = ProactiveTrigger.windowDwell(
            app: "Xcode",
            title: "main.swift",
            minutes: 30,
            bundleID: "com.apple.dt.Xcode"
        )
        let payload = original.userInfoPayload()
        XCTAssertEqual(payload["kind"], "windowDwell")
        XCTAssertEqual(payload["app"], "Xcode")
        XCTAssertEqual(payload["title"], "main.swift")
        XCTAssertEqual(payload["minutes"], "30")
        XCTAssertEqual(payload["bundleID"], "com.apple.dt.Xcode")
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testTypedPauseRoundTrip() {
        let original = ProactiveTrigger.typedPause(app: "Slack", bundleID: "com.tinyspeck.slack")
        let payload = original.userInfoPayload()
        XCTAssertEqual(payload["kind"], "typedPause")
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testUpcomingEventWithLocationRoundTrip() {
        let original = ProactiveTrigger.upcomingEvent(
            title: "Standup",
            minutesUntil: 5,
            location: "Zoom"
        )
        let payload = original.userInfoPayload()
        XCTAssertEqual(payload["kind"], "calendar")
        XCTAssertEqual(payload["title"], "Standup")
        XCTAssertEqual(payload["minutesUntil"], "5")
        XCTAssertEqual(payload["location"], "Zoom")
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testUpcomingEventWithoutLocationRoundTrip() {
        let original = ProactiveTrigger.upcomingEvent(
            title: "1:1",
            minutesUntil: 10,
            location: nil
        )
        let payload = original.userInfoPayload()
        XCTAssertNil(payload["location"])
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeMissingKindReturnsNil() {
        let payload: [String: String] = ["minutes": "15"]
        XCTAssertNil(ProactiveTrigger(userInfoPayload: payload))
    }

    func testDecodeUnknownKindReturnsNil() {
        let payload: [String: String] = ["kind": "alien_trigger"]
        XCTAssertNil(ProactiveTrigger(userInfoPayload: payload))
    }

    func testDecodeIdleWithoutMinutesReturnsNil() {
        let payload: [String: String] = ["kind": "idle"]
        XCTAssertNil(ProactiveTrigger(userInfoPayload: payload))
    }

    func testDecodeAppChangedWithoutBundleReturnsNil() {
        let payload: [String: String] = ["kind": "appChange", "app": "Safari"]
        XCTAssertNil(ProactiveTrigger(userInfoPayload: payload))
    }

    func testDecodeCorruptMinutesReturnsNil() {
        let payload: [String: String] = ["kind": "idle", "minutes": "not_a_number"]
        XCTAssertNil(ProactiveTrigger(userInfoPayload: payload))
    }

    func testDecodeWindowDwellEmptyTitleAccepted() {
        // Empty title default'tur (permission yoksa), nil değil; decode
        // başarılı olmalı.
        let payload: [String: String] = [
            "kind": "windowDwell",
            "app": "Terminal",
            "minutes": "20",
            "bundleID": "com.apple.Terminal"
            // "title" anahtarı yok — empty string default'a düşmeli
        ]
        let decoded = ProactiveTrigger(userInfoPayload: payload)
        XCTAssertNotNil(decoded)
        if case .windowDwell(_, let title, _, _) = decoded {
            XCTAssertEqual(title, "")
        } else {
            XCTFail("Decoded değil veya yanlış case")
        }
    }
}
