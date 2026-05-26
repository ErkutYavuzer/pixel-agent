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
        // Sprint 38 MVP: idle + appChange.
        // Sprint 39 Tier 2: +3 case (windowDwell, typedPause, calendar).
        XCTAssertEqual(TriggerKind.allCases.count, 5)
        XCTAssertTrue(TriggerKind.allCases.contains(.idle))
        XCTAssertTrue(TriggerKind.allCases.contains(.appChange))
        XCTAssertTrue(TriggerKind.allCases.contains(.windowDwell))
        XCTAssertTrue(TriggerKind.allCases.contains(.typedPause))
        XCTAssertTrue(TriggerKind.allCases.contains(.calendar))
    }

    func testTriggerKindRawValueStable() {
        // Rate limiter, SuppressionStore UserDefaults serialization
        // raw value'ya bağımlı — değişmemeli.
        XCTAssertEqual(TriggerKind.idle.rawValue, "idle")
        XCTAssertEqual(TriggerKind.appChange.rawValue, "appChange")
        XCTAssertEqual(TriggerKind.windowDwell.rawValue, "windowDwell")
        XCTAssertEqual(TriggerKind.typedPause.rawValue, "typedPause")
        XCTAssertEqual(TriggerKind.calendar.rawValue, "calendar")
    }

    func testPermissionRequirements() {
        XCTAssertEqual(TriggerKind.idle.permissionRequirement, .none)
        XCTAssertEqual(TriggerKind.appChange.permissionRequirement, .none)
        XCTAssertEqual(TriggerKind.typedPause.permissionRequirement, .none)
        XCTAssertEqual(TriggerKind.windowDwell.permissionRequirement, .accessibility)
        XCTAssertEqual(TriggerKind.calendar.permissionRequirement, .calendar)
    }

    func testTier2TriggerHumanDescriptions() {
        let dwell = ProactiveTrigger.windowDwell(app: "Xcode", title: "main.swift", minutes: 30, bundleID: "com.apple.dt.Xcode")
        XCTAssertTrue(dwell.humanDescription.contains("30"))
        XCTAssertTrue(dwell.humanDescription.contains("Xcode"))

        let typed = ProactiveTrigger.typedPause(app: "Slack", bundleID: "com.slack")
        XCTAssertTrue(typed.humanDescription.contains("Slack"))

        let event = ProactiveTrigger.upcomingEvent(title: "Standup", minutesUntil: 5, location: "Zoom")
        XCTAssertTrue(event.humanDescription.contains("Standup"))
        XCTAssertTrue(event.humanDescription.contains("5"))
    }

    func testTier2BundleSuppressionKeys() {
        XCTAssertEqual(
            ProactiveTrigger.windowDwell(app: "X", title: "T", minutes: 1, bundleID: "com.x").bundleSuppressionKey,
            "com.x"
        )
        XCTAssertEqual(
            ProactiveTrigger.typedPause(app: "X", bundleID: "com.x").bundleSuppressionKey,
            "com.x"
        )
        XCTAssertNil(
            ProactiveTrigger.upcomingEvent(title: "Standup", minutesUntil: 5, location: nil).bundleSuppressionKey
        )
    }

    func testTriggerKindDisplayNamesNonEmpty() {
        for kind in TriggerKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.description.isEmpty)
        }
    }
}
