import Foundation

/// **Sprint 51 (v0.2.80):** Self-improving skill store.
///
/// JSONL append-only paterni `MemoryStore`/`ConversationStore` ile aynı
/// (ADR-0006): her [[SkillEntry]] versiyonu tek satır JSON olarak
/// `skills.jsonl`'e append edilir. Memory'den ayrı dosya — `MemoryConsolidator`
/// Jaccard-merge çakışması yok, ranking bağımsız.
///
/// **Lineage-aware latest-wins:** "Aktif head" = bir `lineageID` içindeki en
/// yüksek `version` (eşitlikte son `updatedAt`). `update` yeni versiyon satırı
/// (`version+1`, `supersedesID`) yazar; `recordUsage` aynı id'yi `usageCount+1`
/// ile yeniden yazar (latest-wins by id → versiyon artmaz); `delete` deleted
/// tombstone versiyonu append eder (lineage gizlenir).
///
/// **Concurrency:** Actor. UI/MCP `Task { await store.method() }` ile çağırır.
public actor SkillStore {
    public let directory: URL
    public let fileURL: URL

    public init(directory: URL? = nil, fileName: String = "skills.jsonl") throws {
        let baseDir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.directory = baseDir
        self.fileURL = baseDir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    // MARK: - Write

    /// **Sprint 51:** Yeni skill (lineage v1). normalize edilmiş halini append eder.
    @discardableResult
    public func create(
        title: String,
        trigger: String,
        steps: [String],
        tags: [String] = [],
        origin: SkillOrigin = .explicit
    ) throws -> SkillEntry {
        let entry = SkillEntry(
            title: title, trigger: trigger, steps: steps, tags: tags, origin: origin
        ).withNormalized()
        try append(entry)
        return entry
    }

    /// **Sprint 51:** Aktif head'in üstüne yeni versiyon (self-improve).
    /// `appendSteps` verilirse mevcut adımlara eklenir; `steps` verilirse
    /// adımlar tamamen değiştirilir (ikisi birden verilirse `steps` kazanır,
    /// sonra `appendSteps` eklenir). usageCount + createdAt korunur.
    @discardableResult
    public func update(
        lineageID: UUID,
        title: String? = nil,
        trigger: String? = nil,
        steps: [String]? = nil,
        appendSteps: [String]? = nil,
        tags: [String]? = nil
    ) throws -> SkillEntry {
        guard let head = try activeHead(lineageID: lineageID) else {
            throw SkillStoreError.skillNotFound(lineageID: lineageID)
        }
        var newSteps = steps ?? head.steps
        if let appendSteps { newSteps += appendSteps }
        let next = SkillEntry(
            id: UUID(),
            lineageID: head.lineageID,
            version: head.version + 1,
            supersedesID: head.id,
            title: title ?? head.title,
            trigger: trigger ?? head.trigger,
            steps: newSteps,
            tags: tags ?? head.tags,
            usageCount: head.usageCount,
            createdAt: head.createdAt,
            updatedAt: Date(),
            deleted: false,
            origin: head.origin
        ).withNormalized()
        try append(next)
        return next
    }

    /// **Sprint 51:** `apply_skill` sayacı — aktif head'i aynı versiyonla
    /// `usageCount+1` yazar (latest-wins by id; yeni versiyon DEĞİL).
    @discardableResult
    public func recordUsage(lineageID: UUID) throws -> SkillEntry {
        guard let head = try activeHead(lineageID: lineageID) else {
            throw SkillStoreError.skillNotFound(lineageID: lineageID)
        }
        let bumped = SkillEntry(
            id: head.id,
            lineageID: head.lineageID,
            version: head.version,
            supersedesID: head.supersedesID,
            title: head.title,
            trigger: head.trigger,
            steps: head.steps,
            tags: head.tags,
            usageCount: head.usageCount + 1,
            createdAt: head.createdAt,
            updatedAt: Date(),
            deleted: false,
            origin: head.origin
        )
        try append(bumped)
        return bumped
    }

    /// **Sprint 51:** Gerçek silme — deleted tombstone versiyonu (lineage gizlenir).
    public func delete(lineageID: UUID) throws {
        let allHeads = try heads()
        guard let head = allHeads[lineageID] else {
            throw SkillStoreError.skillNotFound(lineageID: lineageID)
        }
        let tombstone = SkillEntry(
            id: UUID(),
            lineageID: head.lineageID,
            version: head.version + 1,
            supersedesID: head.id,
            title: head.title,
            trigger: head.trigger,
            steps: head.steps,
            tags: head.tags,
            usageCount: head.usageCount,
            createdAt: head.createdAt,
            updatedAt: Date(),
            deleted: true,
            origin: head.origin
        )
        try append(tombstone)
    }

    // MARK: - Read

    /// **Sprint 51:** Aktif (deleted olmayan) skill head'leri, son güncellemeye göre.
    public func loadActive() throws -> [SkillEntry] {
        try heads().values
            .filter { !$0.deleted }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// **Sprint 51:** Belirli lineage'in aktif head'i (deleted ise nil).
    public func activeHead(lineageID: UUID) throws -> SkillEntry? {
        guard let head = try heads()[lineageID], !head.deleted else { return nil }
        return head
    }

    public func count() throws -> Int {
        try loadActive().count
    }

    /// **Sprint 51:** Tüm raw satırlar (tüm versiyonlar + deleted dahil).
    public func loadAllRaw() throws -> [SkillEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var entries: [SkillEntry] = []
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            if let entry = try? decoder.decode(SkillEntry.self, from: Data(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// **Sprint 51:** Lineage başına head — latest-by-id (recordUsage collapse)
    /// → en yüksek version (eşitlikte son updatedAt). Deleted head'ler dahil.
    private func heads() throws -> [UUID: SkillEntry] {
        let raw = try loadAllRaw()
        var latestById: [UUID: SkillEntry] = [:]
        for entry in raw { latestById[entry.id] = entry }  // last-wins by id
        var byLineage: [UUID: SkillEntry] = [:]
        for entry in latestById.values {
            if let current = byLineage[entry.lineageID] {
                if entry.version > current.version
                    || (entry.version == current.version && entry.updatedAt > current.updatedAt) {
                    byLineage[entry.lineageID] = entry
                }
            } else {
                byLineage[entry.lineageID] = entry
            }
        }
        return byLineage
    }

    /// **Sprint 51:** Fiziksel kompakta — sadece aktif head'leri tutar
    /// (eski versiyonlar + collapsed usage satırları + deleted lineage'ler purge).
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

    // MARK: - Raw append

    private func append(_ entry: SkillEntry) throws {
        var data = try JSONEncoder().encode(entry)
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

/// **Sprint 51 (v0.2.80):** SkillStore operasyon hataları.
public enum SkillStoreError: Error, Sendable {
    case skillNotFound(lineageID: UUID)
}
