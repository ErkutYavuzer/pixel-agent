import Foundation

/// Sprint 7 (B2): Arşivlenmiş konuşmalar için tag sidecar persistence.
/// `ArchiveTitleStore` paterniyle aynı: filename'e dokunma, sidecar'da tut.
///
/// Format: `archive/tags.json` flat dict `[filename: [tag, tag, ...]]`.
/// Boş array veya yokluk → entry tag'siz. Tag listesi her zaman normalize
/// (lowercase trim, dedup, ordered) gelir; write-side `TagNormalizer` ile
/// sanitize edilir (caller sorumluluğu).
public enum ArchiveTagsStore {
    public static let filename = "tags.json"

    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Sidecar yoksa veya bozuksa boş dict döner.
    public static func load(directory: URL) -> [String: [String]] {
        let url = fileURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    public static func save(_ tags: [String: [String]], directory: URL) throws {
        let url = fileURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tags)
        try data.write(to: url, options: .atomic)
    }

    /// Tag listesi boş veya nil → key kaldırılır (entry'i sıfırlama).
    public static func setTags(
        _ tags: [String]?,
        for archiveFilename: String,
        directory: URL
    ) throws {
        var all = load(directory: directory)
        if let tags, !tags.isEmpty {
            all[archiveFilename] = tags
        } else {
            all.removeValue(forKey: archiveFilename)
        }
        try save(all, directory: directory)
    }

    /// Tüm entry'lerin tag union'unu sorted döner (sidebar filter chip'leri için).
    public static func allTags(directory: URL) -> [String] {
        let all = load(directory: directory)
        var union = Set<String>()
        for tags in all.values {
            union.formUnion(tags)
        }
        return union.sorted()
    }
}
