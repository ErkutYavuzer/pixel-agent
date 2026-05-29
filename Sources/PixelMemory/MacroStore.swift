import Foundation

/// **Sprint 52 (v0.2.81) — F1.** Makro kayıt store'u. JSONL append-only
/// (`MemoryStore`/`SkillStore` paterni, ADR-0006): her [[MacroRecording]] tek
/// satır JSON olarak `macros.jsonl`'e append edilir. Latest-wins by id;
/// `delete` tombstone (`deleted: true`). Faz 1'de versiyonlama yok (skill'lerden
/// farklı — makro deterministik tekrar; lineage gerekmez).
///
/// **Concurrency:** Actor. UI/MCP `Task { await store.method() }` ile çağırır.
public actor MacroStore {
    public let directory: URL
    public let fileURL: URL

    public init(directory: URL? = nil, fileName: String = "macros.jsonl") throws {
        let baseDir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.directory = baseDir
        self.fileURL = baseDir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    /// **Sprint 52:** Makro kaydet/güncelle (upsert by id — latest-wins).
    /// Title trim'lenir. Aynı id ile tekrar save → güncelleme.
    @discardableResult
    public func save(_ recording: MacroRecording) throws -> MacroRecording {
        var normalized = recording.withNormalizedTitle()
        normalized.updatedAt = Date()
        try append(normalized)
        return normalized
    }

    /// **Sprint 52:** Soft delete (tombstone). `loadActive` filter eder.
    public func delete(id: UUID) throws {
        let all = try loadAllRaw()
        guard var existing = all.last(where: { $0.id == id }) else {
            throw MacroStoreError.recordingNotFound(id: id)
        }
        existing.deleted = true
        existing.updatedAt = Date()
        try append(existing)
    }

    /// **Sprint 52:** Aktif (deleted olmayan) makrolar, son güncellemeye göre.
    public func loadActive() throws -> [MacroRecording] {
        var latest: [UUID: MacroRecording] = [:]
        for r in try loadAllRaw() { latest[r.id] = r }  // latest-wins by id
        return latest.values
            .filter { !$0.deleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func count() throws -> Int {
        try loadActive().count
    }

    public func loadAllRaw() throws -> [MacroRecording] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var entries: [MacroRecording] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let entry = try? decoder.decode(MacroRecording.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// **Sprint 52:** Fiziksel kompakta — sadece aktif kayıtları tutar.
    public func compact() throws {
        let active = try loadActive()
        let encoder = JSONEncoder()
        var newData = Data()
        for entry in active {
            var encoded = try encoder.encode(entry)
            encoded.append(0x0A)
            newData.append(encoded)
        }
        try newData.write(to: fileURL, options: .atomic)
    }

    private func append(_ recording: MacroRecording) throws {
        var data = try JSONEncoder().encode(recording)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public nonisolated static func defaultDirectory() -> URL {
        ConversationStore.defaultDirectory()
    }
}

/// **Sprint 52 (v0.2.81):** MacroStore operasyon hataları.
public enum MacroStoreError: Error, Sendable {
    case recordingNotFound(id: UUID)
}
