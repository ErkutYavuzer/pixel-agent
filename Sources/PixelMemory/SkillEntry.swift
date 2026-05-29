import Foundation

/// **Sprint 51 (v0.2.80):** Yeniden kullanılabilir workflow "skill" kaydı.
///
/// `MemoryEntry` atomik bir fact ("Beni Erkut diye çağır"); `SkillEntry` ise
/// **çok-adımlı, versiyonlu, kullanım-takipli** bir workflow ("PR review akışı:
/// 1… 2… 3…"). Ayrı tip + ayrı store ([[SkillStore]]) — `MemoryConsolidator`'ın
/// Jaccard-merge'ünden izole, kendi ranking'i ([[SkillRanker]]) var.
///
/// **Self-improving (versiyonlama):** Her skill bir `lineageID` (kalıcı kimlik)
/// altında yaşar; `update` yeni bir `version` satırı append eder (`supersedesID`
/// önceki versiyonu işaret eder), eski versiyon arşivde kalır. "Aktif versiyon"
/// = lineage içindeki en yüksek `version`. `usageCount` her `apply`'da artar ve
/// SkillRanker'da küçük bir boost'a dönüşür (sık kullanılan skill öne çıkar).
public struct SkillEntry: Codable, Equatable, Identifiable, Sendable {
    /// Versiyon-spesifik kimlik (her versiyon satırı kendi id'sine sahip).
    public let id: UUID
    /// Skill'in kalıcı kimliği — tüm versiyonlar paylaşır.
    public let lineageID: UUID
    /// 1'den başlayan versiyon numarası.
    public var version: Int
    /// Bir önceki versiyonun `id`'si (versiyon zinciri). v1'de nil.
    public var supersedesID: UUID?
    public var title: String
    /// "Ne zaman uygula" — SkillRanker relevance query'sinin eşleştiği alan.
    public var trigger: String
    /// Yapılandırılmış adım listesi (her eleman bir adım).
    public var steps: [String]
    public var tags: [String]
    /// Kaç kez `apply_skill` edildiği — ranking boost sinyali.
    public var usageCount: Int
    /// Lineage doğum tarihi (tüm versiyonlarda korunur).
    public let createdAt: Date
    public var updatedAt: Date
    /// Gerçek silme tombstone'u (supersede DEĞİL) — lineage'in tamamını gizler.
    public var deleted: Bool
    public var origin: SkillOrigin

    public init(
        id: UUID = UUID(),
        lineageID: UUID = UUID(),
        version: Int = 1,
        supersedesID: UUID? = nil,
        title: String,
        trigger: String,
        steps: [String],
        tags: [String] = [],
        usageCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deleted: Bool = false,
        origin: SkillOrigin = .explicit
    ) {
        self.id = id
        self.lineageID = lineageID
        self.version = version
        self.supersedesID = supersedesID
        self.title = title
        self.trigger = trigger
        self.steps = steps
        self.tags = tags
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deleted = deleted
        self.origin = origin
    }

    /// **Sprint 51:** Tag (trim+lowercase+dedup) ve step (trim + boş-ele)
    /// normalizasyonu. `SkillStore.create/update` çağrı edenler için.
    public func withNormalized() -> SkillEntry {
        var copy = self
        let seen = NSMutableOrderedSet()
        for tag in tags {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty { seen.add(normalized) }
        }
        copy.tags = (seen.array as? [String]) ?? []
        copy.steps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

/// **Sprint 51 (v0.2.80):** Skill'in nasıl yaratıldığı — UI rozeti + (Faz 2)
/// otomatik extraction'ın FP gürültüsünü ayırt etmek için.
public enum SkillOrigin: String, Codable, CaseIterable, Sendable {
    /// Kullanıcı açık niyetiyle ("her seferinde şöyle yap") veya manuel.
    case explicit
    /// Agent görev sonrası otomatik çıkardı (Faz 2).
    case auto

    public var displayName: String {
        switch self {
        case .explicit: return "Manuel"
        case .auto: return "Otomatik"
        }
    }
}
