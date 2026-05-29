import XCTest

import PixelComputerUse
import PixelMemory
@testable import PixelMacApp

@MainActor
final class MacroRecorderTests: XCTestCase {
    var tempDir: URL!
    var store: MacroStore!
    var recorder: MacroRecorder!

    private let stepA = MacroStep.click(query: nil, opaqueID: "app|AXButton:0", count: 1, modifiers: [])
    private let stepB = MacroStep.type(text: "merhaba", into: nil)

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macrorec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try MacroStore(directory: tempDir)
        recorder = MacroRecorder(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStartSetsRecording() {
        recorder.start(title: "T")
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(recorder.draftSteps.isEmpty)
    }

    func testRecordIgnoredWhenNotRecording() {
        recorder.record(stepA)  // start çağrılmadı
        XCTAssertTrue(recorder.draftSteps.isEmpty)
    }

    func testRecordAppendsWhenRecording() {
        recorder.start(title: "T")
        recorder.record(stepA)
        recorder.record(stepB)
        XCTAssertEqual(recorder.draftSteps, [stepA, stepB])
    }

    func testStopSavesAndClears() async throws {
        recorder.start(title: "Login")
        recorder.record(stepA)
        recorder.record(stepB)
        let saved = await recorder.stop()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.title, "Login")
        XCTAssertEqual(saved?.steps, [stepA, stepB])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(recorder.draftSteps.isEmpty)
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.steps, [stepA, stepB])
    }

    func testStopEmptyReturnsNilAndSavesNothing() async throws {
        recorder.start(title: "Boş")
        let saved = await recorder.stop()
        XCTAssertNil(saved)
        XCTAssertFalse(recorder.isRecording)
        let active = try await store.loadActive()
        XCTAssertTrue(active.isEmpty)
    }

    func testStopWhenNotRecordingReturnsNil() async {
        let saved = await recorder.stop()
        XCTAssertNil(saved)
    }

    func testCancelDiscards() async throws {
        recorder.start(title: "X")
        recorder.record(stepA)
        recorder.cancel()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(recorder.draftSteps.isEmpty)
        let active = try await store.loadActive()
        XCTAssertTrue(active.isEmpty)
    }

    func testBlankTitleUsesDefault() async {
        recorder.start(title: "   ")
        recorder.record(stepA)
        let saved = await recorder.stop()
        XCTAssertTrue(saved?.title.hasPrefix("Makro") ?? false)
    }
}
