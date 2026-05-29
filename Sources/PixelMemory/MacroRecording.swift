import Foundation
import PixelComputerUse

/// **Sprint 52 (v0.2.81) — F1 Computer-Use Task Recorder.** Kaydedilmiş bir
/// computer-use makrosu: sıralı `MacroStep` listesi + metadata. [[MacroStore]]
/// (`macros.jsonl`) tarafından persiste edilir.
///
/// `SkillEntry`'den farkı: skill = LLM'e enjekte edilen doğal-dil reçete;
/// macro = deterministik AX aksiyon dizisi (replay edilir). Bu yüzden ayrı tip
/// + ayrı store (ADR-0038). Faz 1'de lineage/versiyonlama yok — basit;
/// `deleted` tombstone (SkillStore paterni) ile silme.
public struct MacroRecording: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var steps: [MacroStep]
    public let createdAt: Date
    public var updatedAt: Date
    public var deleted: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        steps: [MacroStep],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deleted = deleted
    }

    public var stepCount: Int { steps.count }

    /// Title trim'lenmiş kopya — `MacroStore.save` çağrı edenler için.
    public func withNormalizedTitle() -> MacroRecording {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}
