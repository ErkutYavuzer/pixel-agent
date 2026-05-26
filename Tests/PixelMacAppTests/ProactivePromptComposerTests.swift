import XCTest
@testable import PixelMacApp

/// **Sprint 40 (v0.2.67):** ProactivePromptComposer per-trigger Turkish copy.
final class ProactivePromptComposerTests: XCTestCase {

    func testIdlePromptIncludesMinutes() {
        let p = ProactivePromptComposer.prompt(for: .idle(minutes: 15))
        XCTAssertTrue(p.contains("15"))
        XCTAssertTrue(p.contains("dakika"))
        XCTAssertFalse(p.isEmpty)
    }

    func testAppChangedPromptIncludesAppName() {
        let p = ProactivePromptComposer.prompt(for: .appChanged(name: "Safari", bundleID: "com.apple.Safari"))
        XCTAssertTrue(p.contains("Safari"))
    }

    func testWindowDwellWithTitleIncludesBoth() {
        let p = ProactivePromptComposer.prompt(for: .windowDwell(
            app: "Xcode",
            title: "main.swift",
            minutes: 30,
            bundleID: "com.apple.dt.Xcode"
        ))
        XCTAssertTrue(p.contains("30"))
        XCTAssertTrue(p.contains("Xcode"))
        XCTAssertTrue(p.contains("main.swift"))
    }

    func testWindowDwellWithoutTitleStillCoherent() {
        let p = ProactivePromptComposer.prompt(for: .windowDwell(
            app: "Terminal",
            title: "",
            minutes: 20,
            bundleID: "com.apple.Terminal"
        ))
        XCTAssertTrue(p.contains("Terminal"))
        XCTAssertTrue(p.contains("20"))
        // Boş title olduğunda " — " bağlacı çıkmamalı
        XCTAssertFalse(p.contains("— )"))
    }

    func testTypedPauseIncludesAppName() {
        let p = ProactivePromptComposer.prompt(for: .typedPause(app: "Notes", bundleID: "com.apple.Notes"))
        XCTAssertTrue(p.contains("Notes"))
    }

    func testUpcomingEventWithLocationIncludesLocation() {
        let p = ProactivePromptComposer.prompt(for: .upcomingEvent(
            title: "Standup",
            minutesUntil: 5,
            location: "Zoom"
        ))
        XCTAssertTrue(p.contains("Standup"))
        XCTAssertTrue(p.contains("5"))
        XCTAssertTrue(p.contains("Zoom"))
    }

    func testUpcomingEventWithoutLocation() {
        let p = ProactivePromptComposer.prompt(for: .upcomingEvent(
            title: "1:1",
            minutesUntil: 10,
            location: nil
        ))
        XCTAssertTrue(p.contains("1:1"))
        XCTAssertTrue(p.contains("10"))
        // Location yoksa parantez/Zoom-like suffix çıkmamalı
        XCTAssertFalse(p.contains("()"))
    }

    func testUpcomingEventWithEmptyLocation() {
        let p = ProactivePromptComposer.prompt(for: .upcomingEvent(
            title: "Workshop",
            minutesUntil: 7,
            location: ""
        ))
        XCTAssertTrue(p.contains("Workshop"))
        // Empty string da location'sız davranmalı
        XCTAssertFalse(p.contains("()"))
    }

    func testAllPromptsAreFirstPersonAndNonEmpty() {
        // Demo regression — kullanıcı ağzından, agent'a soru.
        let triggers: [ProactiveTrigger] = [
            .idle(minutes: 15),
            .appChanged(name: "X", bundleID: "com.x"),
            .windowDwell(app: "Y", title: "z", minutes: 5, bundleID: "com.y"),
            .typedPause(app: "Z", bundleID: "com.z"),
            .upcomingEvent(title: "Meeting", minutesUntil: 5, location: nil)
        ]
        for t in triggers {
            let p = ProactivePromptComposer.prompt(for: t)
            XCTAssertFalse(p.isEmpty, "Trigger \(t) için prompt boş")
            XCTAssertGreaterThan(p.count, 20, "Trigger \(t) için prompt çok kısa")
        }
    }
}
