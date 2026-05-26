import XCTest
@testable import PixelMacApp

/// **Sprint 38 (v0.2.65):** ProactiveTrigger enum + TriggerKind testleri.
final class ProactiveTriggerTests: XCTestCase {

    func testIdleTriggerKindIsIdle() {
        let trigger = ProactiveTrigger.idle(minutes: 15)
        XCTAssertEqual(trigger.kind, .idle)
    }

    func testAppChangeTriggerKindIsAppChange() {
        let trigger = ProactiveTrigger.appChanged(name: "Safari", bundleID: "com.apple.Safari")
        XCTAssertEqual(trigger.kind, .appChange)
    }

    func testIdleHasNoBundleSuppressionKey() {
        let trigger = ProactiveTrigger.idle(minutes: 30)
        XCTAssertNil(trigger.bundleSuppressionKey)
    }

    func testAppChangeBundleSuppressionKey() {
        let trigger = ProactiveTrigger.appChanged(name: "Slack", bundleID: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(trigger.bundleSuppressionKey, "com.tinyspeck.slackmacgap")
    }

    func testHumanDescriptionIdle() {
        let trigger = ProactiveTrigger.idle(minutes: 20)
        XCTAssertTrue(trigger.humanDescription.contains("20"))
    }

    func testHumanDescriptionAppChange() {
        let trigger = ProactiveTrigger.appChanged(name: "Xcode", bundleID: "com.apple.dt.Xcode")
        XCTAssertTrue(trigger.humanDescription.contains("Xcode"))
    }

    func testTriggerKindAllCases() {
        // Sprint 38 MVP: idle + appChange. Sprint 39'da +3 case.
        XCTAssertEqual(TriggerKind.allCases.count, 2)
        XCTAssertTrue(TriggerKind.allCases.contains(.idle))
        XCTAssertTrue(TriggerKind.allCases.contains(.appChange))
    }

    func testTriggerKindRawValueStable() {
        // Rate limiter, SuppressionStore UserDefaults serialization
        // raw value'ya bağımlı — değişmemeli.
        XCTAssertEqual(TriggerKind.idle.rawValue, "idle")
        XCTAssertEqual(TriggerKind.appChange.rawValue, "appChange")
    }

    func testTriggerKindDisplayNamesNonEmpty() {
        for kind in TriggerKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.description.isEmpty)
        }
    }
}
