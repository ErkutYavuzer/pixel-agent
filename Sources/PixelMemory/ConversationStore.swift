import Foundation
import PixelCore

public actor ConversationStore {
    public let directory: URL
    public let fileURL: URL
    public let archiveDirectory: URL

    public init(directory: URL? = nil, fileName: String = "conversation.jsonl") throws {
        let baseDir = directory ?? Self.defaultDirectory()
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let archive = baseDir.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        self.directory = baseDir
        self.fileURL = baseDir.appendingPathComponent(fileName)
        self.archiveDirectory = archive

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    public func append(_ message: Message) throws {
        var data = try JSONEncoder().encode(message)
        data.append(0x0A)  // newline
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func loadAll(limit: Int? = nil) throws -> [Message] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }

        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A)
        var messages: [Message] = []
        for line in lines {
            guard !line.isEmpty else { continue }
            if let message = try? decoder.decode(Message.self, from: Data(line)) {
                messages.append(message)
            }
        }
        if let limit, messages.count > limit {
            return Array(messages.suffix(limit))
        }
        return messages
    }

    public func newConversation() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? Int) ?? 0
        if size > 0 {
            // **Sprint 4:** Millisecond precision — saniye precision'da hızlı
            // ardışık `newConversation()` çağrıları (test hız + UI bouncing)
            // dosya çakışmasına yol açıyordu. Format:
            //   `YYYY-MM-DDTHH:MM:SS.sssZ` → `:` → `-` → 24 char stamp.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withColonSeparatorInTime,
                .withFractionalSeconds,
            ]
            let stamp = formatter.string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension
            let archiveURL = archiveDirectory.appendingPathComponent("\(baseName)-\(stamp).\(ext)")
            try FileManager.default.moveItem(at: fileURL, to: archiveURL)
        } else {
            try FileManager.default.removeItem(at: fileURL)
        }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    public func messageCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }
        let data = try Data(contentsOf: fileURL)
        return data.split(separator: 0x0A).filter { !$0.isEmpty }.count
    }

    /// **Sprint 4 (B2 follow-up):** Aktif JSONL'i arşivler, sonra verilen
    /// archived dosyanın içeriğini aktif JSONL'e kopyalar. Kullanıcı
    /// "Bu sohbete devam et" tıkladığında çağrılır. ChatView re-init olunca
    /// `restoreIfNeeded()` artık archived mesajları görür.
    ///
    /// `entry.id` URL'i archive dizininden olmalı (defensive sınır değil;
    /// caller sorumluluğu — Sidebar'dan zaten geliyor).
    public func replaceWithArchive(_ entry: ArchivedConversationEntry) throws {
        // 1. Mevcut JSONL'i (boş değilse) archive'a taşı.
        try newConversation()
        // 2. Archive dosyasının içeriğini aktif JSONL'e kopyala.
        let data = try Data(contentsOf: entry.id)
        guard !data.isEmpty else { return }
        try data.write(to: fileURL)
    }

    /// Sprint 6 (B2): Bir archived dosyaya kullanıcı başlığı set/clear et.
    /// `nil` veya whitespace-only → sidecar'dan kaldırılır (snippet fallback'e döner).
    public func renameArchive(at url: URL, title: String?) throws {
        try ArchiveTitleStore.setTitle(
            title,
            for: url.lastPathComponent,
            directory: archiveDirectory
        )
    }

    /// Sprint 6 (B2): View'lar instance olmadan da rename edebilsin —
    /// `listAllArchives` gibi static. Sidecar atomic write olduğu için
    /// thread-safe; aynı anda iki yerden yazımda last-write-wins.
    public nonisolated static func renameArchive(
        at url: URL,
        title: String?,
        directory: URL? = nil
    ) throws {
        let baseDir = directory ?? defaultDirectory()
        let archiveDir = baseDir.appendingPathComponent("archive", isDirectory: true)
        try ArchiveTitleStore.setTitle(
            title,
            for: url.lastPathComponent,
            directory: archiveDir
        )
    }

    /// Sprint 7 (B2): Bir archived dosyaya tag listesi set/clear et.
    /// Caller `TagNormalizer` ile sanitize etmeli (lowercase/trim/dedup).
    /// Boş veya nil → sidecar'dan kaldırılır.
    public func setTags(_ tags: [String]?, for url: URL) throws {
        try ArchiveTagsStore.setTags(
            tags,
            for: url.lastPathComponent,
            directory: archiveDirectory
        )
    }

    /// Sprint 7 (B2): View'lar instance olmadan da tag edebilsin.
    public nonisolated static func setTags(
        _ tags: [String]?,
        for url: URL,
        directory: URL? = nil
    ) throws {
        let baseDir = directory ?? defaultDirectory()
        let archiveDir = baseDir.appendingPathComponent("archive", isDirectory: true)
        try ArchiveTagsStore.setTags(
            tags,
            for: url.lastPathComponent,
            directory: archiveDir
        )
    }

    /// Sprint 7 (B2): Tüm arşivlerin tag union'u (sidebar filter chip'leri için).
    public nonisolated static func listAllTags(directory: URL? = nil) -> [String] {
        let baseDir = directory ?? defaultDirectory()
        let archiveDir = baseDir.appendingPathComponent("archive", isDirectory: true)
        return ArchiveTagsStore.allTags(directory: archiveDir)
    }

    /// Sprint 12 (v0.2.37): Bir arşivi kalıcı olarak sil — JSONL dosyası +
    /// sidecar entry'ler (title + tags). Idempotent (dosya yoksa hata atmaz).
    /// View'lar instance olmadan da silebilsin diye static.
    public nonisolated static func deleteArchive(at url: URL, directory: URL? = nil) throws {
        let baseDir = directory ?? defaultDirectory()
        let archiveDir = baseDir.appendingPathComponent("archive", isDirectory: true)
        let filename = url.lastPathComponent

        // 1. Sidecar entry'lerini temizle (her ikisi için "nil set" = remove key).
        //    setTitle/setTags atomic write yapar; dosya yoksa graceful.
        try? ArchiveTitleStore.setTitle(nil, for: filename, directory: archiveDir)
        try? ArchiveTagsStore.setTags(nil, for: filename, directory: archiveDir)

        // 2. JSONL dosyasını sil. Idempotent — dosya zaten yoksa hata atmaz.
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// B2: Belirli bir archived dosyadan mesajları oku. URL store'un kendi
    /// archive dizininde olmalı (defensive boundary değil — caller dikkat etsin).
    public func loadMessages(fromArchive url: URL) throws -> [Message] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        let lines = data.split(separator: 0x0A)
        var messages: [Message] = []
        for line in lines {
            guard !line.isEmpty else { continue }
            if let m = try? decoder.decode(Message.self, from: Data(line)) {
                messages.append(m)
            }
        }
        return messages
    }

    /// B2: Tüm backend'lerin arşivlerini tek listede döner. Sidebar'da
    /// kullanılır. Filename'den parse edilemeyenler atlanır (geriye-uyumlu).
    public nonisolated static func listAllArchives(
        directory: URL? = nil
    ) throws -> [ArchivedConversationEntry] {
        let baseDir = directory ?? defaultDirectory()
        let archiveDir = baseDir.appendingPathComponent("archive", isDirectory: true)
        guard FileManager.default.fileExists(atPath: archiveDir.path) else { return [] }

        let urls = try FileManager.default.contentsOfDirectory(
            at: archiveDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        // Sprint 6 (B2): Sidecar titles dict'i bir kere yükle, loop'ta lookup et.
        let titles = ArchiveTitleStore.load(directory: archiveDir)
        // Sprint 7 (B2): Tags sidecar'ı da bir kere yükle.
        let tagsByFile = ArchiveTagsStore.load(directory: archiveDir)

        let decoder = JSONDecoder()
        var entries: [ArchivedConversationEntry] = []
        for url in urls {
            let filename = url.lastPathComponent
            guard filename.hasSuffix(".jsonl") else { continue }
            guard let parsed = ArchivedConversationParser.parseFilename(filename) else {
                continue
            }
            // Mesaj sayısı + ilk user snippet'i için içeriği oku.
            let data = (try? Data(contentsOf: url)) ?? Data()
            let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
            var messages: [Message] = []
            for line in lines {
                if let m = try? decoder.decode(Message.self, from: Data(line)) {
                    messages.append(m)
                }
            }
            let entry = ArchivedConversationEntry(
                id: url,
                backendKind: parsed.kind,
                archivedAt: parsed.date,
                messageCount: messages.count,
                firstUserSnippet: ArchivedConversationParser.firstUserSnippet(messages: messages),
                customTitle: titles[filename],
                tags: tagsByFile[filename] ?? []
            )
            entries.append(entry)
        }
        // En yeni arşiv üstte.
        return entries.sorted { $0.archivedAt > $1.archivedAt }
    }

    public nonisolated static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("pixel-agent", isDirectory: true)
    }
}
