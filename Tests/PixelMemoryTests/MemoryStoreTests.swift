import XCTest
@testable import PixelMemory

/// **Sprint 36 (v0.2.63):** MemoryStore actor CRUD + JSONL persist
/// + soft delete + compact testleri.
final class MemoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("memorystore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Basic CRUD

    func testInitCreatesEmptyFile() async throws {
        let store = try MemoryStore(directory: tempDir)
        let count = try await store.entryCount()
        XCTAssertEqual(count, 0)
    }

    func testAddPersistsEntry() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .profile, content: "Beni Erkut diye çağır")
        try await store.add(entry)
        let all = try await store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.content, "Beni Erkut diye çağır")
        XCTAssertEqual(all.first?.category, .profile)
    }

    func testAddMultipleEntries() async throws {
        let store = try MemoryStore(directory: tempDir)
        try await store.add(MemoryEntry(category: .profile, content: "A"))
        try await store.add(MemoryEntry(category: .preference, content: "B"))
        try await store.add(MemoryEntry(category: .task, content: "C", tags: ["recipe"]))
        let count = try await store.entryCount()
        XCTAssertEqual(count, 3)
    }

    func testTagsNormalizedOnAdd() async throws {
        let store = try MemoryStore(directory: tempDir)
        // Capitalize + duplicate + whitespace
        let entry = MemoryEntry(category: .task, content: "X", tags: ["  Recipe ", "RECIPE", "review"])
        try await store.add(entry)
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.tags, ["recipe", "review"])
    }

    // MARK: - Update

    func testUpdateChangesContentAndUpdatedAt() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .note, content: "Eski")
        try await store.add(entry)
        let originalUpdated = entry.updatedAt
        try await Task.sleep(nanoseconds: 10_000_000)  // 10ms — updatedAt fark için
        try await store.update(id: entry.id, content: "Yeni")
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.content, "Yeni")
        XCTAssertGreaterThan(loaded.first?.updatedAt ?? Date.distantPast, originalUpdated)
    }

    func testUpdateNonExistentEntryThrows() async throws {
        let store = try MemoryStore(directory: tempDir)
        let bogusID = UUID()
        do {
            try await store.update(id: bogusID, content: "X")
            XCTFail("Beklenen entryNotFound error gelmedi")
        } catch MemoryStoreError.entryNotFound(let id) {
            XCTAssertEqual(id, bogusID)
        } catch {
            XCTFail("Beklenmedik error: \(error)")
        }
    }

    func testUpdateChangesCategoryAndTags() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .note, content: "X", tags: ["a"])
        try await store.add(entry)
        try await store.update(id: entry.id, tags: ["b", "c"], category: .task)
        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.category, .task)
        XCTAssertEqual(loaded.first?.tags, ["b", "c"])
    }

    // MARK: - Soft delete

    func testDeleteSoftRemovesFromLoadAll() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .note, content: "Silinecek")
        try await store.add(entry)
        try await store.delete(id: entry.id)
        let active = try await store.loadAll()
        XCTAssertTrue(active.isEmpty)
    }

    func testDeleteKeepsTombstoneInRawLog() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .note, content: "X")
        try await store.add(entry)
        try await store.delete(id: entry.id)
        let raw = try await store.loadAllRaw()
        XCTAssertEqual(raw.count, 2)  // add + delete tombstone
        XCTAssertTrue(raw.last?.deleted ?? false)
    }

    // MARK: - Filters

    func testLoadByCategory() async throws {
        let store = try MemoryStore(directory: tempDir)
        try await store.add(MemoryEntry(category: .profile, content: "P"))
        try await store.add(MemoryEntry(category: .task, content: "T1"))
        try await store.add(MemoryEntry(category: .task, content: "T2"))
        let tasks = try await store.loadByCategory(.task)
        XCTAssertEqual(tasks.count, 2)
    }

    func testLoadByTagCaseInsensitive() async throws {
        let store = try MemoryStore(directory: tempDir)
        try await store.add(MemoryEntry(category: .task, content: "X", tags: ["Recipe"]))
        try await store.add(MemoryEntry(category: .task, content: "Y"))
        let recipes = try await store.loadByTag("recipe")
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes.first?.content, "X")
    }

    // MARK: - Compact

    func testCompactRemovesDeletedAndDuplicateAppends() async throws {
        let store = try MemoryStore(directory: tempDir)
        let entry = MemoryEntry(category: .note, content: "X")
        try await store.add(entry)
        try await store.update(id: entry.id, content: "Y")  // 2. append
        try await store.update(id: entry.id, content: "Z")  // 3. append
        let toDelete = MemoryEntry(category: .note, content: "Delete me")
        try await store.add(toDelete)
        try await store.delete(id: toDelete.id)

        let beforeRaw = try await store.loadAllRaw()
        XCTAssertGreaterThan(beforeRaw.count, 2)

        try await store.compact()

        let afterRaw = try await store.loadAllRaw()
        XCTAssertEqual(afterRaw.count, 1)  // sadece son hali, deleted yok
        XCTAssertEqual(afterRaw.first?.content, "Z")
    }

    // MARK: - relevantContext integration

    func testRelevantContextDelegatesToPlaybookLearner() async throws {
        let store = try MemoryStore(directory: tempDir)
        try await store.add(MemoryEntry(category: .task, content: "PR review için template kullan", tags: ["recipe"]))
        try await store.add(MemoryEntry(category: .note, content: "Tamamen alakasız bir not"))
        let results = try await store.relevantContext(for: "PR review yapacağım", minSimilarity: 0.1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.tags, ["recipe"])
    }
}
