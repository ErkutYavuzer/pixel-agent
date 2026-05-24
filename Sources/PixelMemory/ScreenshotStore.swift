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

    /// Bir messageID için kaydedilmiş PNG'yi (ve varsa JSON sidecar'ı) siler
    /// (best-effort). Sidecar Sprint 6'da SoMMark dizisi için eklendi.
    public static func delete(
        for messageID: UUID,
        directory: URL? = nil
    ) throws {
        let dir = directory ?? defaultDirectory()
        let pngURL = dir.appendingPathComponent("\(messageID.uuidString).png")
        try? FileManager.default.removeItem(at: pngURL)
        try? deleteSidecar(for: messageID, directory: dir)
    }

    // MARK: - Sprint 6: Sidecar JSON (SoM marks vb.)

    /// Sidecar JSON dosya path'i — `<UUID>.json` aynı dizinde.
    private static func sidecarURL(for messageID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(messageID.uuidString).json")
    }

    /// PNG'nin yanına arbitrary JSON yazar. Sprint 6'da SoMMark dizisi için
    /// kullanılır — restart sonrası `ui_screenshot` numbered overlay'leri
    /// yeniden render olur.
    public static func saveSidecar(
        jsonData: Data,
        for messageID: UUID,
        directory: URL? = nil
    ) throws {
        let dir = directory ?? defaultDirectory()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = sidecarURL(for: messageID, in: dir)
        try jsonData.write(to: url, options: .atomic)
    }

    /// Sidecar'ı okur. Dosya yoksa nil — caller marks olmadan attachment kurar.
    public static func loadSidecar(
        for messageID: UUID,
        directory: URL? = nil
    ) throws -> Data? {
        let dir = directory ?? defaultDirectory()
        let url = sidecarURL(for: messageID, in: dir)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Sidecar'ı siler (best-effort).
    public static func deleteSidecar(
        for messageID: UUID,
        directory: URL? = nil
    ) throws {
        let dir = directory ?? defaultDirectory()
        let url = sidecarURL(for: messageID, in: dir)
        try? FileManager.default.removeItem(at: url)
    }

    /// Dizini tarayıp **artık aktif store'da olmayan** `messageID`'lerin
    /// PNG ve JSON sidecar dosyalarını siler. Caller `activeIDs` set'ini
    /// ConversationStore'dan türetir. Sprint 6: `.json` sidecar'lar da dahil.
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
        for url in urls {
            let ext = url.pathExtension
            guard ext == "png" || ext == "json" else { continue }
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
