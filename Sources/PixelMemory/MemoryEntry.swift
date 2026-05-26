import Foundation

/// **Sprint 36 (v0.2.63):** MemoryStore'un ana value type'ı.
///
/// v3'te ilk kez **cross-session persistent memory** mekanizması — bir
/// kullanıcı mesajı sırasında ChatViewModel `MemoryStore.relevantContext(for:)`
/// çağırır, sonuçlar CLIBackend prompt'una system context olarak enjekte
/// edilir. Agent geçmiş benzer task'leri "hatırlar".
///
/// 5 kategori (`MemoryCategory`) ile hiyerarşik öncelik: `profile` (kullanıcı
/// kimliği, rol), `preference` (iletişim stili), `project` (aktif iş bağlamı),
/// `task` (tekrarlayan iş örüntüleri), `note` (uzun-form serbest metin).
/// Her kategorinin `promptWeight`'i (0-4) PlaybookLearner ranking'inde
/// boost faktörü olarak kullanılır.
///
/// **JSONL serialization**: `MemoryStore` her entry'yi tek satır JSON olarak
/// `memory.jsonl` dosyasının sonuna append eder. Update/delete logical
/// (tombstone gibi append-only; consolidate periyodik kompaktlar).
public struct MemoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var category: MemoryCategory
    public var content: String
    public var tags: [String]
    public let createdAt: Date
    public var updatedAt: Date
    /// **Soft delete flag.** `true` ise entry compacted (`compactDeleted()`)
    /// öncesi log'da fiziksel olarak kalır ama `loadAll()` filter eder.
    public var deleted: Bool

    public init(
        id: UUID = UUID(),
        category: MemoryCategory,
        content: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deleted: Bool = false
    ) {
        self.id = id
        self.category = category
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deleted = deleted
    }

    /// **Sprint 36 (v0.2.63):** Trim + lowercase tag normalization helper —
    /// `MemoryStore.add` çağrı edenler bunu tetiklemeli (dedup için).
    public func withNormalizedTags() -> MemoryEntry {
        var copy = self
        let seen = NSMutableOrderedSet()
        for tag in tags {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty {
                seen.add(normalized)
            }
        }
        copy.tags = (seen.array as? [String]) ?? []
        return copy
    }
}

/// **Sprint 36 (v0.2.63):** 5 öncelik seviyesi ile memory kategorisi.
///
/// v2 (~64k LOC monorepo) bu modeli `MemoryStore.swift:1-115`'de yapıyordu;
/// v3 SPM modüler yapıda PixelMemory altında yeniden hayata geçti.
public enum MemoryCategory: String, Codable, CaseIterable, Sendable {
    case profile     // 4 — kullanıcı kimliği, rol, ülke, dil
    case preference  // 3 — iletişim stili, ton tercihleri
    case project     // 2 — aktif iş bağlamı, hedefler
    case task        // 1 — tekrarlayan iş örüntüleri (recipe candidates)
    case note        // 0 — uzun-form serbest metin

    /// **Prompt weight** — PlaybookLearner ranking'inde boost katsayısı.
    /// 0 (en düşük) - 4 (en yüksek). `profile` (4) her zaman üst sıralarda
    /// olmalı (kullanıcı kim?); `note` (0) sadece eşleşme varsa.
    public var promptWeight: Int {
        switch self {
        case .profile: return 4
        case .preference: return 3
        case .project: return 2
        case .task: return 1
        case .note: return 0
        }
    }

    /// **UI başlığı** — Settings tab memory list rendering için.
    public var displayName: String {
        switch self {
        case .profile: return "Profil"
        case .preference: return "Tercih"
        case .project: return "Proje"
        case .task: return "Görev"
        case .note: return "Not"
        }
    }
}
