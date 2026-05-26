import XCTest
@testable import PixelMacApp

/// **Sprint 40 (v0.2.67):** NotificationActionDispatcher helper testleri.
final class NotificationActionDispatcherTests: XCTestCase {

    // MARK: - normalizePayload

    func testNormalizePayloadEmpty() {
        XCTAssertNil(NotificationActionDispatcher.normalizePayload([:]))
    }

    func testNormalizePayloadFilteredToStringPairs() {
        let raw: [AnyHashable: Any] = [
            "kind": "idle",
            "minutes": "15",
            "extra_int": 42,        // Int — skip
            123: "value_for_int_key" // Int key — skip
        ]
        let result = NotificationActionDispatcher.normalizePayload(raw)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["kind"], "idle")
        XCTAssertEqual(result?["minutes"], "15")
        XCTAssertNil(result?["extra_int"])
    }

    func testNormalizePayloadAllStrings() {
        let raw: [AnyHashable: Any] = ["a": "1", "b": "2"]
        let result = NotificationActionDispatcher.normalizePayload(raw)
        XCTAssertEqual(result?.count, 2)
    }

    func testNormalizePayloadOnlyNonStringsReturnsNil() {
        let raw: [AnyHashable: Any] = [1: 1, 2: "x"]
        let result = NotificationActionDispatcher.normalizePayload(raw)
        // Int-key (1: 1) skip + Int-key (2: "x") skip → boş → nil
        XCTAssertNil(result)
    }

    // MARK: - isInjectEnabled

    func testInjectEnabledDefaultsTrueWhenUnset() {
        let defaults = UserDefaults(suiteName: "test.inject.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "_x") }
        XCTAssertTrue(NotificationActionDispatcher.isInjectEnabled(defaults: defaults))
    }

    func testInjectEnabledRespectsStoredFalse() {
        let suiteName = "test.inject.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(false, forKey: NotificationActionDispatcher.enabledDefaultsKey)
        XCTAssertFalse(NotificationActionDispatcher.isInjectEnabled(defaults: defaults))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testInjectEnabledRespectsStoredTrue() {
        let suiteName = "test.inject.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: NotificationActionDispatcher.enabledDefaultsKey)
        XCTAssertTrue(NotificationActionDispatcher.isInjectEnabled(defaults: defaults))
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - broadcast

    func testBroadcastEmitsNotification() {
        let expectation = XCTestExpectation(description: "Notification received")
        let observer = NotificationCenter.default.addObserver(
            forName: .proactivePromptInject,
            object: nil,
            queue: .main
        ) { note in
            if let draft = note.userInfo?["draft"] as? String, draft == "Hello world" {
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        NotificationActionDispatcher.broadcast(draft: "Hello world")

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - End-to-end Trigger → broadcast flow (manual handler invoke)

    func testRoundTripTriggerToBroadcast() {
        // 1. Trigger oluştur
        let trigger = ProactiveTrigger.idle(minutes: 20)
        // 2. userInfo payload üret
        let payload = trigger.userInfoPayload()
        // 3. Normalize'dan geçir (real path simulation)
        let normalized = NotificationActionDispatcher.normalizePayload(payload as [AnyHashable: Any])
        XCTAssertNotNil(normalized)
        // 4. Decode geri trigger'a
        let decoded = ProactiveTrigger(userInfoPayload: normalized ?? [:])
        XCTAssertEqual(decoded, trigger)
        // 5. Compose draft
        let draft = ProactivePromptComposer.prompt(for: decoded!)
        XCTAssertTrue(draft.contains("20"))

        // 6. Broadcast — observer check
        let expectation = XCTestExpectation(description: "Broadcast received")
        let observer = NotificationCenter.default.addObserver(
            forName: .proactivePromptInject,
            object: nil,
            queue: .main
        ) { note in
            if let received = note.userInfo?["draft"] as? String, received == draft {
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        NotificationActionDispatcher.broadcast(draft: draft)
        wait(for: [expectation], timeout: 1.0)
    }
}
