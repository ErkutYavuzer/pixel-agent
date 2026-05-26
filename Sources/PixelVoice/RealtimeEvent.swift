import Foundation

/// **Sprint 43 (v0.2.70):** OpenAI Realtime WebSocket event protocol.
///
/// **Event direction:**
/// - **Client → Server:** `session.update`, `input_audio_buffer.append`,
///   `input_audio_buffer.commit`, `response.create`, `response.cancel`.
/// - **Server → Client:** `session.created`, `session.updated`, `response.audio.delta`,
///   `response.audio_transcript.delta`, `response.done`, `error`,
///   `input_audio_buffer.speech_started`, `input_audio_buffer.speech_stopped`.
///
/// MVP scope (Sprint 43): audio I/O + server-side VAD + transcript.
/// Sprint 44: function calling + interrupt + Gemini Live parity.
///
/// **Encoding:** JSON over WebSocket text frame. Her event'in `type` field'ı
/// var; event-specific payload diğer field'lar. Burada **partial typing** —
/// sadece kullandığımız field'ları decode/encode, geri kalan ignore.
public enum RealtimeClientEvent: Encodable, Sendable {
    /// **Sprint 43:** Session configuration — modalities, voice, instructions,
    /// turn_detection (server_vad), audio formats.
    case sessionUpdate(config: SessionConfig)

    /// **Sprint 43:** Mic'ten yakalanan base64 audio chunk gönder.
    case inputAudioBufferAppend(audioBase64: String)

    /// **Sprint 43:** Server-side VAD `false` ise client manuel commit eder.
    /// Server-side VAD `true` (default Sprint 43) ise otomatik.
    case inputAudioBufferCommit

    /// **Sprint 43:** Response generation tetikle (server-side VAD `true`'da
    /// otomatik; manuel mode'da client çağırır).
    case responseCreate

    /// **Sprint 44:** Devam eden response'u interrupt et (kullanıcı sözünü
    /// kesti). Şu an Sprint 43 MVP'de kullanılmıyor.
    case responseCancel

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionUpdate(let config):
            try container.encode("session.update", forKey: .type)
            try container.encode(config, forKey: .session)
        case .inputAudioBufferAppend(let audioBase64):
            try container.encode("input_audio_buffer.append", forKey: .type)
            try container.encode(audioBase64, forKey: .audio)
        case .inputAudioBufferCommit:
            try container.encode("input_audio_buffer.commit", forKey: .type)
        case .responseCreate:
            try container.encode("response.create", forKey: .type)
        case .responseCancel:
            try container.encode("response.cancel", forKey: .type)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, session, audio
    }
}

/// **Sprint 43 (v0.2.70):** Session configuration — `session.update` payload.
///
/// **Sprint 43 MVP:**
/// - modalities: ["text", "audio"] — hem transcript hem ses
/// - voice: "alloy" (default; "echo"/"shimmer" Sprint 44+)
/// - instructions: "Sen pixel-agent..." (kullanıcı tarafından configurable v0.2.71+)
/// - input/output_audio_format: "pcm16" (Sprint 43 sabit)
/// - turn_detection: server_vad (Apple Speech'in zayıf interrupt'ını çözer)
public struct SessionConfig: Encodable, Sendable {
    public let modalities: [String]
    public let voice: String
    public let instructions: String
    public let inputAudioFormat: String
    public let outputAudioFormat: String
    public let turnDetection: TurnDetection?

    public init(
        modalities: [String] = ["text", "audio"],
        voice: String = "alloy",
        instructions: String = "Sen pixel-agent — kullanıcıya Türkçe, kısa ve net cevaplar ver.",
        inputAudioFormat: String = "pcm16",
        outputAudioFormat: String = "pcm16",
        turnDetection: TurnDetection? = TurnDetection.serverVAD()
    ) {
        self.modalities = modalities
        self.voice = voice
        self.instructions = instructions
        self.inputAudioFormat = inputAudioFormat
        self.outputAudioFormat = outputAudioFormat
        self.turnDetection = turnDetection
    }

    enum CodingKeys: String, CodingKey {
        case modalities, voice, instructions
        case inputAudioFormat = "input_audio_format"
        case outputAudioFormat = "output_audio_format"
        case turnDetection = "turn_detection"
    }
}

public struct TurnDetection: Encodable, Sendable {
    public let type: String
    public let threshold: Double
    public let prefixPaddingMs: Int
    public let silenceDurationMs: Int

    public init(
        type: String,
        threshold: Double,
        prefixPaddingMs: Int,
        silenceDurationMs: Int
    ) {
        self.type = type
        self.threshold = threshold
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
    }

    /// **Sprint 43:** Server-side VAD default — Apple Realtime API recommended
    /// values. 500ms silence sonra response otomatik trigger.
    public static func serverVAD(
        threshold: Double = 0.5,
        prefixPaddingMs: Int = 300,
        silenceDurationMs: Int = 500
    ) -> TurnDetection {
        TurnDetection(
            type: "server_vad",
            threshold: threshold,
            prefixPaddingMs: prefixPaddingMs,
            silenceDurationMs: silenceDurationMs
        )
    }

    enum CodingKeys: String, CodingKey {
        case type, threshold
        case prefixPaddingMs = "prefix_padding_ms"
        case silenceDurationMs = "silence_duration_ms"
    }
}

// MARK: - Server events (decode)

/// **Sprint 43 (v0.2.70):** Server'dan gelen event'lerin partial decode'u.
/// Sadece kullandığımız case'leri model'le; bilinmeyen `type` → `.unknown`
/// (forward-compat, OpenAI yeni event türleri eklerse parse fail etmez).
public enum RealtimeServerEvent: Sendable, Equatable {
    /// Session created — connection başarılı.
    case sessionCreated(sessionID: String)

    /// Session updated — config ack.
    case sessionUpdated

    /// `response.audio.delta` — server PCM16 audio chunk yolladı (base64).
    case audioDelta(base64: String)

    /// `response.audio_transcript.delta` — server text transcript chunk.
    case transcriptDelta(text: String)

    /// `response.done` — response tamamlandı.
    case responseDone

    /// `input_audio_buffer.speech_started` — server VAD speech başlangıcı detect etti.
    case speechStarted

    /// `input_audio_buffer.speech_stopped` — VAD speech sonu.
    case speechStopped

    /// `error` — server hata bildirdi.
    case error(message: String)

    /// Bilinmeyen type — forward-compat.
    case unknown(type: String)

    /// **Sprint 43:** JSON Data → event. Partial parse; unknown type
    /// ignore. Returns nil → JSON corrupt veya `type` field eksik.
    public static func decode(_ data: Data) -> RealtimeServerEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        switch type {
        case "session.created":
            let sid = (json["session"] as? [String: Any])?["id"] as? String ?? ""
            return .sessionCreated(sessionID: sid)
        case "session.updated":
            return .sessionUpdated
        case "response.audio.delta":
            let b64 = json["delta"] as? String ?? ""
            return .audioDelta(base64: b64)
        case "response.audio_transcript.delta":
            let text = json["delta"] as? String ?? ""
            return .transcriptDelta(text: text)
        case "response.done":
            return .responseDone
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            return .error(message: msg)
        default:
            return .unknown(type: type)
        }
    }
}
