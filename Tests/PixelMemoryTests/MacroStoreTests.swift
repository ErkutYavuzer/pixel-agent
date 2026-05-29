import XCTest

import PixelComputerUse
@testable import PixelMemory

final class MacroStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macrostore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> MacroStore {
        try MacroStore(directory: tempDir)
    }

    private let sampleSteps: [MacroStep] = [
        .click(query: nil, opaqueID: "app|AXButton:0", count: 1, modifiers: []),
        .wait(milliseconds: 100),
        .type(text: "merhaba", into: nil),
    ]

    func testSaveAndLoadActive() async throws {
        let store = try makeStore()
        _ = try await store.save(MacroRecording(title: "Login akışı", steps: sampleSteps))
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.title, "Login akışı")
        XCTAssertEqual(active.first?.steps, sampleSteps)
        XCTAssertEqual(active.first?.stepCount, 3)
    }

    func testSaveUpsertByID() async throws {
        let store = try makeStore()
        let rec = MacroRecording(title: "v1", steps: sampleSteps)
        _ = try await store.save(rec)
        var updated = rec
        updated.title = "v2"
        _ = try await store.save(updated)
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)            // aynı id → upsert
        XCTAssertEqual(active.first?.title, "v2")  // latest-wins
    }

    func testDeleteTombstone() async throws {
        let store = try makeStore()
        let rec = try await store.save(MacroRecording(title: "X", steps: sampleSteps))
        try await store.delete(id: rec.id)
        let active = try await store.loadActive()
        XCTAssertTrue(active.isEmpty)
    }

    func testDeleteUnknownThrows() async throws {
        let store = try makeStore()
        do {
            try await store.delete(id: UUID())
            XCTFail("bilinmeyen id silme hata vermeli")
        } catch MacroStoreError.recordingNotFound {
            // beklenen
        }
    }

    func testTwoRecordingsIndependent() async throws {
        let store = try makeStore()
        _ = try await store.save(MacroRecording(title: "A", steps: [.wait(milliseconds: 1)]))
        _ = try await store.save(MacroRecording(title: "B", steps: [.wait(milliseconds: 2)]))
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 2)
    }

    func testCompactKeepsActiveOnly() async throws {
        let store = try makeStore()
        let a = try await store.save(MacroRecording(title: "A", steps: sampleSteps))
        let b = try await store.save(MacroRecording(title: "B", steps: sampleSteps))
        try await store.delete(id: b.id)
        try await store.compact()
        let raw = try await store.loadAllRaw()
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(raw.count, active.count)
        XCTAssertEqual(raw.first?.id, a.id)
    }

    func testTitleTrimmedOnSave() async throws {
        let store = try makeStore()
        _ = try await store.save(MacroRecording(title: "  boşluklu  ", steps: sampleSteps))
        let active = try await store.loadActive()
        XCTAssertEqual(active.first?.title, "boşluklu")
    }

    func testCountReflectsActive() async throws {
        let store = try makeStore()
        _ = try await store.save(MacroRecording(title: "A", steps: sampleSteps))
        let b = try await store.save(MacroRecording(title: "B", steps: sampleSteps))
        try await store.delete(id: b.id)
        let count = try await store.count()
        XCTAssertEqual(count, 1)
    }
}
