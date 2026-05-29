import XCTest

@testable import PixelMemory

final class SkillStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeStore() throws -> SkillStore {
        try SkillStore(directory: tempDir)
    }

    func testCreateProducesActiveV1() async throws {
        let store = try makeStore()
        let created = try await store.create(title: "PR review", trigger: "pr açarken", steps: ["fetch", "review"])
        XCTAssertEqual(created.version, 1)
        XCTAssertEqual(created.usageCount, 0)
        XCTAssertNil(created.supersedesID)

        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.title, "PR review")
        XCTAssertEqual(active.first?.steps, ["fetch", "review"])
    }

    func testUpdateSupersedesAndKeepsArchive() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "Skill", trigger: "t", steps: ["a"])
        let v2 = try await store.update(lineageID: v1.lineageID, title: "Skill v2", steps: ["a", "b"])

        XCTAssertEqual(v2.version, 2)
        XCTAssertEqual(v2.supersedesID, v1.id)
        XCTAssertEqual(v2.lineageID, v1.lineageID)
        XCTAssertEqual(v2.createdAt, v1.createdAt)  // lineage doğum tarihi korunur

        // Aktif tek lineage, v2 head.
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.title, "Skill v2")
        XCTAssertEqual(active.first?.version, 2)

        // Eski versiyon arşivde (raw'da en az 2 satır).
        let raw = try await store.loadAllRaw()
        XCTAssertGreaterThanOrEqual(raw.count, 2)
    }

    func testUpdateAppendSteps() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "S", trigger: "t", steps: ["1", "2"])
        let v2 = try await store.update(lineageID: v1.lineageID, appendSteps: ["3"])
        XCTAssertEqual(v2.steps, ["1", "2", "3"])
    }

    func testRecordUsageBumpsCountSameVersion() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "S", trigger: "t", steps: ["a"])
        let used = try await store.recordUsage(lineageID: v1.lineageID)
        XCTAssertEqual(used.usageCount, 1)
        XCTAssertEqual(used.version, 1)  // versiyon artmaz

        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.usageCount, 1)
        XCTAssertEqual(active.first?.version, 1)
    }

    func testDeleteHidesLineage() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "S", trigger: "t", steps: ["a"])
        try await store.delete(lineageID: v1.lineageID)

        let active = try await store.loadActive()
        XCTAssertTrue(active.isEmpty)
        let head = try await store.activeHead(lineageID: v1.lineageID)
        XCTAssertNil(head)
    }

    func testUpdateAfterDeleteThrows() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "S", trigger: "t", steps: ["a"])
        try await store.delete(lineageID: v1.lineageID)
        do {
            _ = try await store.update(lineageID: v1.lineageID, title: "x")
            XCTFail("deleted lineage update etmemeli")
        } catch SkillStoreError.skillNotFound {
            // beklenen
        }
    }

    func testActiveHeadTracksLatestVersion() async throws {
        let store = try makeStore()
        let v1 = try await store.create(title: "S", trigger: "t", steps: ["a"])
        _ = try await store.update(lineageID: v1.lineageID, steps: ["a", "b"])
        _ = try await store.update(lineageID: v1.lineageID, steps: ["a", "b", "c"])
        let head = try await store.activeHead(lineageID: v1.lineageID)
        XCTAssertEqual(head?.version, 3)
        XCTAssertEqual(head?.steps, ["a", "b", "c"])
    }

    func testTwoLineagesIndependent() async throws {
        let store = try makeStore()
        let a = try await store.create(title: "A", trigger: "ta", steps: ["1"])
        let b = try await store.create(title: "B", trigger: "tb", steps: ["1"])
        XCTAssertNotEqual(a.lineageID, b.lineageID)
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 2)
    }

    func testCompactKeepsOnlyActiveHeads() async throws {
        let store = try makeStore()
        let a = try await store.create(title: "A", trigger: "ta", steps: ["1"])
        _ = try await store.update(lineageID: a.lineageID, steps: ["1", "2"])
        _ = try await store.recordUsage(lineageID: a.lineageID)
        let b = try await store.create(title: "B", trigger: "tb", steps: ["1"])
        try await store.delete(lineageID: b.lineageID)  // B silinir

        try await store.compact()
        let raw = try await store.loadAllRaw()
        let active = try await store.loadActive()
        XCTAssertEqual(active.count, 1)               // sadece A aktif
        XCTAssertEqual(raw.count, active.count)        // compact: raw == aktif head sayısı
        XCTAssertEqual(raw.first?.title, "A")
    }

    func testCountReflectsActive() async throws {
        let store = try makeStore()
        _ = try await store.create(title: "A", trigger: "t", steps: ["1"])
        let b = try await store.create(title: "B", trigger: "t", steps: ["1"])
        try await store.delete(lineageID: b.lineageID)
        let count = try await store.count()
        XCTAssertEqual(count, 1)
    }
}
