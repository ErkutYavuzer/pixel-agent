import Foundation

/// **Sprint 52 (v0.2.81) — F1 Computer-Use Task Recorder.** Kaydedilen tek bir
/// computer-use aksiyonu. **Koordinat-tabanlı DEĞİL:** tıklama hedefi semantik
/// AX referansı olarak (`UIQuery` + `opaqueID`) saklanır; replay'de element AX
/// ile yeniden çözülür → pencere taşınsa/boyut değişse bile çalışır (AX moat).
///
/// `UIQuery` / `ModifierFlags` / `ScreenshotTarget` zaten `Codable` + `Sendable`
/// olduğundan `MacroStep` otomatik Codable/Sendable/Equatable.
public enum MacroStep: Sendable, Codable, Equatable {
    /// Bir element'e tıkla. Replay'de **önce `opaqueID` re-resolve** denenir
    /// (en kararlı semantik handle), başarısızsa `query` fallback.
    case click(query: UIQuery?, opaqueID: String?, count: Int, modifiers: ModifierFlags)
    /// Aktif veya `into` element'ine metin yaz.
    case type(text: String, into: UIQuery?)
    /// Ekran görüntüsü al (replay'de çoğunlukla yan-etkisiz; demo'da görünür).
    case screenshot(target: ScreenshotTarget)
    /// Adımlar arası açık bekleme.
    case wait(milliseconds: Int)

    /// İnsan-okur kısa özet (Settings listesi + debug). UI katmanı kullanır.
    public var summary: String {
        switch self {
        case .click(let q, let oid, let count, _):
            let target = q?.title ?? q?.identifier ?? q?.label ?? q?.containsText
                ?? oid.map { "#\($0.prefix(12))" } ?? "element"
            return count > 1 ? "Tıkla ×\(count): \(target)" : "Tıkla: \(target)"
        case .type(let text, _):
            let preview = text.count > 30 ? "\(text.prefix(30))…" : text
            return "Yaz: \"\(preview)\""
        case .screenshot:
            return "Ekran görüntüsü"
        case .wait(let ms):
            return "Bekle: \(ms) ms"
        }
    }

    /// Replay'i destructive (Plan Mode guard'a tabi) yapan adım mı?
    /// `.click`/`.type` UI'yi değiştirir; `.screenshot`/`.wait` read-only/pasif.
    public var isDestructive: Bool {
        switch self {
        case .click, .type: return true
        case .screenshot, .wait: return false
        }
    }
}

/// **Sprint 52:** Replay sırasında element bulunamazsa ne yapılacağı.
public enum NotFoundPolicy: Sendable, Equatable {
    /// Replay'i durdur (yanlış state'te devam etme).
    case abort
    /// Bu adımı atla, sonrakine geç (riskli — state kayabilir).
    case skip
    /// `backoffMs` bekleyip tekrar dene; `maxRetries` tükenince abort.
    case retry(maxRetries: Int, backoffMs: Int)
}

/// **Sprint 52:** `MacroReplayPlan.decideOnNotFound` kararı (saf çıktı).
public enum NotFoundAction: Sendable, Equatable {
    case retry(afterMs: Int)
    case skip
    case abort
}

/// **Sprint 52:** Replay motoru hataları.
public enum MacroReplayError: Error, Sendable, Equatable {
    case emptyRecording
    case tooManySteps(count: Int, max: Int)
    case elementNotFound(stepIndex: Int)
    case planModeBlocked
    case cancelled
    case timedOut
}

/// **Sprint 52:** Replay yapılandırması + runaway safety sınırları.
public struct MacroReplayOptions: Sendable, Equatable {
    public var maxSteps: Int
    public var notFoundPolicy: NotFoundPolicy
    public var interStepDelayMs: Int
    public var maxDurationSeconds: Double
    /// Destructive (.click/.type) adımlara izin ver. UI default true (kullanıcı
    /// açıkça "oynat" dedi); MCP yolunda Plan Mode guard ayrıca enforce eder.
    public var allowDestructive: Bool

    public init(
        maxSteps: Int = 200,
        notFoundPolicy: NotFoundPolicy = .retry(maxRetries: 3, backoffMs: 300),
        interStepDelayMs: Int = 250,
        maxDurationSeconds: Double = 60,
        allowDestructive: Bool = true
    ) {
        self.maxSteps = maxSteps
        self.notFoundPolicy = notFoundPolicy
        self.interStepDelayMs = interStepDelayMs
        self.maxDurationSeconds = maxDurationSeconds
        self.allowDestructive = allowDestructive
    }

    public static let `default` = MacroReplayOptions()
}
