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

    /// **Sprint 44 (v0.2.71):** Devam eden response'u interrupt et (kullanıcı
    /// sözünü kesti). `speech_started` event'iyle auto-trigger ya da `cancel
    /// Speech()` API'siyle manuel.
    case responseCancel

    /// **Sprint 44 (v0.2.71):** Function call'un sonucunu server'a yolla.
    /// MCP dispatch sonrası agent çağrısına cevap. `callID` server'ın yolladığı
    /// function_call.call_id; `output` JSON-serialized tool result.
    case conversationItemCreateFunctionCallOutput(callID: String, output: String)

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
        case .conversationItemCreateFunctionCallOutput(let callID, let output):
            try container.encode("conversation.item.create", forKey: .type)
            // Nested item structure — OpenAI spec
            try container.encode(
                FunctionCallOutputItem(callID: callID, output: output),
                forKey: .item
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, session, audio, item
    }
}

/// **Sprint 44 (v0.2.71):** `conversation.item.create` event'inin `item`
/// field'ı için function_call_output payload.
public struct FunctionCallOutputItem: Encodable, Sendable {
    public let type: String = "function_call_output"
    public let callID: String
    public let output: String

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
        case output
    }
}

/// **Sprint 43 (v0.2.70):** Session configuration — `session.update` payload.
///
/// **Sprint 43 MVP:**
/// - modalities: ["text", "audio"] — hem transcript hem ses
/// - voice: "alloy" (default; "echo"/"shimmer" Sprint 44+)
/// - instructions: "Sen pixel-agent..." (kullanıcı tarafından configurable v0.2.72+)
/// - input/output_audio_format: "pcm16" (Sprint 43 sabit)
/// - turn_detection: server_vad (Apple Speech'in zayıf interrupt'ını çözer)
///
/// **Sprint 44 (v0.2.71):** `tools` field eklendi — OpenAI fonksiyon
/// çağırabilsin. MCP `BuiltInTools` registry'sinden `OpenAIToolBridge` ile
/// convert edilir.
public struct SessionConfig: Encodable, Sendable {
    public let modalities: [String]
    public let voice: String
    public let instructions: String
    public let inputAudioFormat: String
    public let outputAudioFormat: String
    public let turnDetection: TurnDetection?
    public let tools: [OpenAITool]?

    public init(
        modalities: [String] = ["text", "audio"],
        voice: String = "alloy",
        instructions: String = "Sen pixel-agent — kullanıcıya Türkçe, kısa ve net cevaplar ver. Gereken bilgi için elindeki MCP araçlarını çağır (örn `get_current_time` saat sorusunda).",
        inputAudioFormat: String = "pcm16",
        outputAudioFormat: String = "pcm16",
        turnDetection: TurnDetection? = TurnDetection.serverVAD(),
        tools: [OpenAITool]? = nil
    ) {
        self.modalities = modalities
        self.voice = voice
        self.instructions = instructions
        self.inputAudioFormat = inputAudioFormat
        self.outputAudioFormat = outputAudioFormat
        self.turnDetection = turnDetection
        self.tools = tools
    }

    enum CodingKeys: String, CodingKey {
        case modalities, voice, instructions, tools
        case inputAudioFormat = "input_audio_format"
        case outputAudioFormat = "output_audio_format"
        case turnDetection = "turn_detection"
    }
}

/// **Sprint 44 (v0.2.71):** OpenAI tool definition. `OpenAIToolBridge` MCP
/// `ToolDefinition` → bu type'a convert eder. `parameters` JSON schema
/// object string (MCP'nin `inputSchema` JSON-encoded).
public struct OpenAITool: Encodable, Sendable {
    public let type: String = "function"
    public let name: String
    public let description: String
    /// **Parameters** — opaque JSON object encoded as a Codable wrapper.
    public let parameters: AnyEncodable

    public init(name: String, description: String, parameters: AnyEncodable) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// **Sprint 44 (v0.2.71):** Type-erased Encodable — `OpenAITool.parameters`
/// için MCP `JSONValue` veya `[String: Any]` dict'i alıp Encodable
/// container'a sarar.
public struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void
    public init<T: Encodable & Sendable>(_ wrapped: T) {
        self._encode = { encoder in try wrapped.encode(to: encoder) }
    }
    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
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
///
/// **Sprint 44 (v0.2.71):** Function call event'leri eklendi.
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

    /// **Sprint 44 (v0.2.71):** Server function call başlattı.
    /// `response.output_item.added` event'i `item.type == "function_call"`
    /// ise. `callID` sonraki argument event'leriyle eşleşir; `name` tool adı.
    case functionCallStarted(callID: String, name: String)

    /// **Sprint 44 (v0.2.71):** Function call argument'ları stream'le geldi.
    /// `response.function_call_arguments.delta`. Partial JSON string.
    case functionCallArgumentsDelta(callID: String, delta: String)

    /// **Sprint 44 (v0.2.71):** Function call argument'ları tamamlandı.
    /// `response.function_call_arguments.done`. Full JSON string.
    /// Client şimdi tool'u çalıştırır + sonucu `conversation.item.create`
    /// (`function_call_output`) ile yollar.
    case functionCallArgumentsDone(callID: String, arguments: String)

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
        case "response.output_item.added":
            // Sprint 44 (v0.2.71): yalnız function_call item'ları ilgilendirir.
            guard let item = json["item"] as? [String: Any],
                  (item["type"] as? String) == "function_call",
                  let callID = item["call_id"] as? String,
                  let name = item["name"] as? String else {
                return .unknown(type: type)
            }
            return .functionCallStarted(callID: callID, name: name)
        case "response.function_call_arguments.delta":
            let callID = json["call_id"] as? String ?? ""
            let delta = json["delta"] as? String ?? ""
            return .functionCallArgumentsDelta(callID: callID, delta: delta)
        case "response.function_call_arguments.done":
            let callID = json["call_id"] as? String ?? ""
            let args = json["arguments"] as? String ?? ""
            return .functionCallArgumentsDone(callID: callID, arguments: args)
        default:
            return .unknown(type: type)
        }
    }
}
