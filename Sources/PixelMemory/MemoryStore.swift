import Foundation

/// **Sprint 36 (v0.2.63):** Cross-session persistent memory store.
///
/// JSONL append-only paterni `ConversationStore` ile aynı (ADR-0006):
/// her entry tek satır JSON olarak `memory.jsonl` dosyasının sonuna eklenir.
/// Update/delete logical — `add` mevcut id'ye `updatedAt` ile yeniden append,
/// `delete` `deleted: true` flag'i ile tombstone. `loadAll()` her entry id'si
/// için **en son** kayıtı tutar, deleted olanları filter eder.
///
/// Storage path: `~/Library/Application Support/pixel-agent/memory.jsonl`.
/// `ConversationStore.defaultDirectory()` ile aynı baz dizin.
///
/// **Concurrency:** Actor. `add` / `update` / `delete` MainActor değil — UI
/// kabuğu (Settings → Memory tab) `Task { await store.method() }` ile çağırır.
public actor MemoryStore {
    public let directory: URL
    public let fileURL: URL

    public init(directory: URL? = nil, fileName: String = "memory.jsonl") throws {
        let baseDir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        self.directory = baseDir
        self.fileURL = baseDir.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    /// **Sprint 36:** Yeni veya mevcut entry'yi append eder. Caller `id`
    /// duplikatsa loadAll'un latest-wins davranışı update gibi çalışır.
    /// Tags otomatik normalize edilir (trim + lowercase + dedup).
    public func add(_ entry: MemoryEntry) throws {
        let normalized = entry.withNormalizedTags()
        var data = try JSONEncoder().encode(normalized)
        data.append(0x0A)  // newline
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// **Sprint 36:** Mevcut entry'nin alanlarını günceller, `updatedAt`
    /// yenilenir. ID değişmez. Append-only: yeni bir satır yazılır;
    /// `loadAll` latest-wins ile aynı id'nin son halini döndürür.
    public func update(id: UUID, content: String? = nil, tags: [String]? = nil, category: MemoryCategory? = nil) throws {
        let all = try loadAllRaw()
        guard var existing = all.last(where: { $0.id == id && !$0.deleted }) else {
            throw MemoryStoreError.entryNotFound(id: id)
        }
        if let content { existing.content = content }
        if let tags { existing.tags = tags }
        if let category { existing.category = category }
        existing.updatedAt = Date()
        try add(existing)
    }

    /// **Sprint 36:** Soft delete — `deleted: true` flag ile tombstone
    /// append eder. `loadAll()` deleted entry'leri filter eder. Fiziksel
    /// purge için `compact()` (gelecek versiyonda otomatik).
    public func delete(id: UUID) throws {
        let all = try loadAllRaw()
        guard var existing = all.last(where: { $0.id == id }) else {
            throw MemoryStoreError.entryNotFound(id: id)
        }
        existing.deleted = true
        existing.updatedAt = Date()
        try add(existing)
    }

    /// **Sprint 36:** Aktif (deleted olmayan) entry'leri döndürür, en son
    /// güncellemeye göre latest-wins.
    public func loadAll() throws -> [MemoryEntry] {
        let raw = try loadAllRaw()
        var latest: [UUID: MemoryEntry] = [:]
        for entry in raw {
            // Latest-wins: append-only log'da aynı id'nin son satırı kazanır.
            latest[entry.id] = entry
        }
        return latest.values
            .filter { !$0.deleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// **Sprint 36:** Tüm raw entry'leri okur (deleted dahil) — `update`/
    /// `delete` operasyonları ve future `compact()` için.
    public func loadAllRaw() throws -> [MemoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A)
        var entries: [MemoryEntry] = []
        for line in lines {
            guard !line.isEmpty else { continue }
            if let entry = try? decoder.decode(MemoryEntry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// **Sprint 36:** Kategori filtresi ile aktif entry'ler.
    public func loadByCategory(_ category: MemoryCategory) throws -> [MemoryEntry] {
        try loadAll().filter { $0.category == category }
    }

    /// **Sprint 36:** Tag filter (case-insensitive substring değil exact
    /// match — tag normalization sayesinde lowercase).
    public func loadByTag(_ tag: String) throws -> [MemoryEntry] {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try loadAll().filter { $0.tags.contains(normalized) }
    }

    /// **Sprint 36 — PlaybookLearner integration point.** `query` ile
    /// `TextSimilarityScorer` üzerinden top-N benzer entry'leri döndürür.
    /// Tag'inde "recipe" olan entry'ler boost edilir (PlaybookLearner çoğu
    /// zaman buradan beslenir).
    ///
    /// Default `limit = 3`, `minSimilarity = 0.55` — v2'nin PlaybookLearner
    /// threshold'u ile uyumlu. Embedding-free Jaccard token similarity
    /// (CoreML overhead'i v0.3+ aday).
    public func relevantContext(for query: String, limit: Int = 3, minSimilarity: Double = 0.55) throws -> [MemoryEntry] {
        let all = try loadAll()
        return PlaybookLearner.relevant(
            query: query,
            in: all,
            limit: limit,
            minSimilarity: minSimilarity
        )
    }

    public func entryCount() throws -> Int {
        try loadAll().count
    }

    /// **Sprint 36 (defensive future-proof):** Fiziksel kompakta — tüm
    /// log dosyasını yeniden yazar, sadece en son halleri tutar.
    /// MVP'de manuel çağrılır (`consolidate_memory` MCP tool veya Settings
    /// "Optimize Et" butonu); v0.3+ otomatik schedule.
    public func compact() throws {
        let active = try loadAll()
        let encoder = JSONEncoder()
        var newData = Data()
        for entry in active {
            var encoded = try encoder.encode(entry)
            encoded.append(0x0A)
            newData.append(encoded)
        }
        try newData.write(to: fileURL, options: .atomic)
    }

    public nonisolated static func defaultDirectory() -> URL {
        // ConversationStore ile aynı baz dizin — single source of truth.
        ConversationStore.defaultDirectory()
    }
}

/// **Sprint 36 (v0.2.63):** MemoryStore operasyon hataları.
public enum MemoryStoreError: Error, Sendable {
    case entryNotFound(id: UUID)
}
