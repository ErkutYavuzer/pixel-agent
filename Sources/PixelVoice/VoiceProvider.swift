import Foundation

/// **Sprint 42 (v0.2.69):** Voice provider abstraction.
///
/// Üç implementation hedefi:
/// 1. **`AppleVoiceProvider`** (Sprint 42 MVP) — SFSpeechRecognizer + AVSpeechSynthesizer.
///    Lokal, ücretsiz, sıfır API key, ~100ms latency, privacy-friendly.
///    Tam Realtime değil — interrupt zayıf, server-side VAD yok.
/// 2. **`OpenAIRealtimeProvider`** (Sprint 43) — WebSocket `wss://api.openai.com/v1/realtime`.
///    Server-side VAD, interruptible, function calling, ~$0.06/min input.
/// 3. **`GeminiLiveProvider`** (Sprint 44) — WebSocket Google AI Studio.
///    Benzer Realtime spec'i, Apple Silicon optimized.
///
/// `VoiceSession` (PixelMacApp) bu protokolü kullanarak transcript'i
/// ChatView composer'a inject eder; agent cevabını `speak(_:)` ile TTS yapar.
///
/// `Sendable` — actor sınırları aracılığıyla taşınır.
public protocol VoiceProvider: Sendable {
    /// **Sprint 42:** Capture başlat. Permission kontrolü içeride yapılır.
    /// `transcriptEvents` stream'i `TranscriptEvent.final`/`.interim` yields.
    /// Hata olursa `.error` event'i ile (stream sonlanmaz, retry desteği).
    func start() async throws

    /// **Sprint 42:** Capture durdur. `transcriptEvents` stream'i finish.
    func stop() async

    /// **Sprint 42:** Agent cevabını TTS ile seslendirir. Non-blocking —
    /// background queue'da çalışır.
    func speak(_ text: String) async

    /// **Sprint 42:** Speak ortasında durdurmak için. Provider içeride
    /// AVSpeechSynthesizer.stopSpeaking veya WebSocket cancel etc.
    func cancelSpeech() async

    /// **Sprint 42:** Transcript stream — UI bunu dinler. AsyncSequence
    /// finish edince session bitti sayılır.
    var transcriptEvents: AsyncStream<TranscriptEvent> { get }

    /// **Sprint 42:** Provider human-readable adı — Settings UI'da
    /// gösterilir (örn "Apple Speech", "OpenAI Realtime").
    var providerName: String { get }

    /// **Sprint 42:** Permission durum kontrolü. Provider-specific.
    /// `true` ise `start()` çağrısı başarılı olur (Permission istenir
    /// gerekirse).
    func isAuthorized() async -> Bool
}

/// **Sprint 42 (v0.2.69):** Voice session event'leri.
///
/// `interim` — partial transcript, kullanıcı konuşmaya devam ediyor.
/// UI canlı olarak göster (gri renkte, italic).
///
/// `final` — segment tamamlandı, send'e hazır metin.
/// Provider segment kararını verir (sessizlik, "." gibi end-of-utterance).
///
/// `error` — recoverable veya fatal. UI banner gösterir, kullanıcı retry'a
/// karar verir.
public enum TranscriptEvent: Sendable, Equatable {
    case interim(text: String)
    case final(text: String)
    case error(message: String)

    /// Convenience — text payload veya nil (error case).
    public var text: String? {
        switch self {
        case .interim(let t), .final(let t): return t
        case .error: return nil
        }
    }

    /// Convenience — `.final` ise true.
    public var isFinal: Bool {
        if case .final = self { return true }
        return false
    }
}
