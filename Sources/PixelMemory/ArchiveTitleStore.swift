import Foundation

/// Sprint 6 (B2 follow-up): kullanıcı tarafından verilen arşiv başlıkları
/// için sidecar persistence. Filename değişmiyor (parser kırılmasın) —
/// `archive/titles.json` flat dict tutar: `[filename: title]`.
///
/// Saf helper; FileManager ile çalışır ama state yok. ConversationStore
/// actor metodu içinden çağrılır → yazma serileşir.
public enum ArchiveTitleStore {
    public static let filename = "titles.json"

    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Sidecar yoksa veya bozuksa boş dict döner — UI fallback davranır.
    public static func load(directory: URL) -> [String: String] {
        let url = fileURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public static func save(_ titles: [String: String], directory: URL) throws {
        let url = fileURL(in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(titles)
        try data.write(to: url, options: .atomic)
    }

    /// Title nil veya whitespace-only ise key kaldırılır (custom title sıfırlama).
    public static func setTitle(
        _ title: String?,
        for archiveFilename: String,
        directory: URL
    ) throws {
        var titles = load(directory: directory)
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            titles[archiveFilename] = trimmed
        } else {
            titles.removeValue(forKey: archiveFilename)
        }
        try save(titles, directory: directory)
    }
}
