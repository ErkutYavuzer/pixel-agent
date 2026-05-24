import Foundation

/// `~/Library/Application Support/pixel-agent/screenshots/` dizininde
/// `<messageID>.png` formatında ekran görüntüsü dosyalarını saklar
/// (Sprint 4 — C2/C3 follow-up).
///
/// ChatViewModel.captureScreenshotIntoChat:
/// 1. PNG bytes'ı buraya `save(pngData:for:)` ile yazar.
/// 2. Placeholder mesajını ConversationStore'a append'ler.
///
/// ChatViewModel.restoreIfNeeded:
/// 1. JSONL'den mesajları okur (eski davranış).
/// 2. `.system` rolünde + `[ekran görüntüsü` prefix'li mesajlar için
///    `load(for:)` ile PNG bytes'ı geri okur.
/// 3. Attachment dict'i yeniden doldurur — restart'tan sonra önceki
///    konuşmadaki ekran görüntüleri görünmeye devam eder.
///
/// Saf enum — actor değil. File ops küçük PNG'ler için sync; testler
/// hermetic.
public enum ScreenshotStore {

    /// `~/Library/Application Support/pixel-agent/screenshots/`
    public static func defaultDirectory() -> URL {
        ConversationStore.defaultDirectory()
            .appendingPathComponent("screenshots", isDirectory: true)
    }

    /// PNG bytes'ı `<messageID>.png` olarak yazar. Dizin yoksa oluşturulur.
    /// Atomic write (yarım kalmaz).
    public static func save(
        pngData: Data,
        for messageID: UUID,
        directory: URL? = nil
    ) throws {
        let dir = directory ?? defaultDirectory()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent("\(messageID.uuidString).png")
        try pngData.write(to: url, options: .atomic)
    }

    /// PNG bytes'ı `<messageID>.png`'den okur. Dosya yoksa nil.
    public static func load(
        for messageID: UUID,
        directory: URL? = nil
    ) throws -> Data? {
        let dir = directory ?? defaultDirectory()
        let url = dir.appendingPathComponent("\(messageID.uuidString).png")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Bir messageID için kaydedilmiş PNG'yi siler (best-effort).
    public static func delete(
        for messageID: UUID,
        directory: URL? = nil
    ) throws {
        let dir = directory ?? defaultDirectory()
        let url = dir.appendingPathComponent("\(messageID.uuidString).png")
        try? FileManager.default.removeItem(at: url)
    }

    /// Dizini tarayıp **artık aktif store'da olmayan** `messageID`'lerin
    /// PNG dosyalarını siler. Caller `activeIDs` set'ini ConversationStore'dan
    /// türetir. Boş set verilirse no-op.
    public static func purgeOrphans(
        keeping activeIDs: Set<UUID>,
        directory: URL? = nil
    ) throws -> Int {
        let dir = directory ?? defaultDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var removed = 0
        for url in urls where url.pathExtension == "png" {
            let stem = url.deletingPathExtension().lastPathComponent
            guard let uuid = UUID(uuidString: stem) else { continue }
            if !activeIDs.contains(uuid) {
                try? FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }
}
