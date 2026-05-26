import Foundation

/// **Sprint 45 (v0.2.72):** Google Gemini Live API (`BidiGenerateContent`)
/// WebSocket protocol.
///
/// **Endpoint:** `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=<API_KEY>`
///
/// **Audio format:**
/// - Input: PCM16 16 kHz mono (OpenAI'den FARKLI — 24kHz değil)
/// - Output: PCM16 24 kHz mono (`RealtimeAudioPlayer` ile uyumlu)
///
/// **Cost** (2026 Q1): Gemini 2.0 Flash Realtime ~$0.006/min input + ~$0.024/min
/// output — OpenAI'den ~10x ucuz. Kullanıcı maliyet odaklıysa Gemini tercih.
///
/// **Sprint 45 MVP scope:**
/// - setup event (model + system_instruction + tools + response_modalities)
/// - realtime_input (audio chunk send)
/// - serverContent (audio response decode)
/// - toolCall / toolResponse (function calling)
/// - serverContent.interrupted flag (interrupt detect)

// MARK: - Client → Server

public enum GeminiClientEvent: Encodable, Sendable {
    /// **Sprint 45:** Connection açılışında — model, system instruction, tools,
    /// modalities. Tek seferlik (her connection'da bir kez).
    case setup(config: GeminiSetupConfig)

    /// **Sprint 45:** Mic chunk gönder. Gemini `realtime_input` kullanır;
    /// `media_chunks` array içinde `mime_type` ve base64 `data`.
    case realtimeInput(audioBase64: String)

    /// **Sprint 45:** Function call sonucunu server'a yolla. ID + name +
    /// response object.
    case toolResponse(functionResponses: [GeminiFunctionResponse])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TopKey.self)
        switch self {
        case .setup(let config):
            try container.encode(config, forKey: .setup)
        case .realtimeInput(let audioBase64):
            let chunk = GeminiMediaChunk(mimeType: "audio/pcm;rate=16000", data: audioBase64)
            try container.encode(
                GeminiRealtimeInput(mediaChunks: [chunk]),
                forKey: .realtimeInput
            )
        case .toolResponse(let responses):
            try container.encode(
                GeminiToolResponseWrapper(functionResponses: responses),
                forKey: .toolResponse
            )
        }
    }

    enum TopKey: String, CodingKey {
        case setup
        case realtimeInput = "realtime_input"
        case toolResponse = "tool_response"
    }
}

/// **Sprint 45 (v0.2.72):** `setup` event payload.
public struct GeminiSetupConfig: Encodable, Sendable {
    public let model: String
    public let generationConfig: GeminiGenerationConfig
    public let systemInstruction: GeminiSystemInstruction?
    public let tools: [GeminiTools]?

    public init(
        model: String = "models/gemini-2.0-flash-exp",
        generationConfig: GeminiGenerationConfig = .init(),
        systemInstruction: GeminiSystemInstruction? = .init(text: "Sen pixel-agent — kullanıcıya Türkçe, kısa ve net cevaplar ver. Gerekirse MCP araçlarını çağır."),
        tools: [GeminiTools]? = nil
    ) {
        self.model = model
        self.generationConfig = generationConfig
        self.systemInstruction = systemInstruction
        self.tools = tools
    }

    enum CodingKeys: String, CodingKey {
        case model, tools
        case generationConfig = "generation_config"
        case systemInstruction = "system_instruction"
    }
}

public struct GeminiGenerationConfig: Encodable, Sendable {
    public let responseModalities: [String]

    public init(responseModalities: [String] = ["AUDIO"]) {
        self.responseModalities = responseModalities
    }

    enum CodingKeys: String, CodingKey {
        case responseModalities = "response_modalities"
    }
}

public struct GeminiSystemInstruction: Encodable, Sendable {
    public let parts: [GeminiTextPart]

    public init(text: String) {
        self.parts = [GeminiTextPart(text: text)]
    }
}

public struct GeminiTextPart: Encodable, Sendable {
    public let text: String
    public init(text: String) { self.text = text }
}

/// **Sprint 45:** Function declaration grouping — `tools[]` her item bir
/// `functionDeclarations` array taşır.
public struct GeminiTools: Encodable, Sendable {
    public let functionDeclarations: [GeminiFunctionDeclaration]

    public init(functionDeclarations: [GeminiFunctionDeclaration]) {
        self.functionDeclarations = functionDeclarations
    }

    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }
}

public struct GeminiFunctionDeclaration: Encodable, Sendable {
    public let name: String
    public let description: String
    public let parameters: AnyEncodable?

    public init(name: String, description: String, parameters: AnyEncodable?) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct GeminiMediaChunk: Encodable, Sendable {
    public let mimeType: String
    public let data: String

    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

public struct GeminiRealtimeInput: Encodable, Sendable {
    public let mediaChunks: [GeminiMediaChunk]

    enum CodingKeys: String, CodingKey {
        case mediaChunks = "media_chunks"
    }
}

public struct GeminiFunctionResponse: Encodable, Sendable {
    public let id: String
    public let name: String
    /// Response content — opaque JSON object (function output).
    public let response: AnyEncodable

    public init(id: String, name: String, response: AnyEncodable) {
        self.id = id
        self.name = name
        self.response = response
    }
}

public struct GeminiToolResponseWrapper: Encodable, Sendable {
    public let functionResponses: [GeminiFunctionResponse]

    enum CodingKeys: String, CodingKey {
        case functionResponses = "function_responses"
    }
}

// MARK: - Server → Client (decode)

/// **Sprint 45 (v0.2.72):** Gemini Live server event'leri.
public enum GeminiServerEvent: Sendable, Equatable {
    /// `setupComplete` — config ack.
    case setupComplete

    /// `serverContent.modelTurn.parts[].inlineData` audio chunk (base64).
    case audioChunk(base64: String)

    /// `serverContent.modelTurn.parts[].text` — agent text response.
    case textChunk(text: String)

    /// `serverContent.interrupted: true` — Gemini agent'ı kesti (user spoke).
    case interrupted

    /// `serverContent.turnComplete: true` — agent turn bitti.
    case turnComplete

    /// `toolCall.functionCalls[]` — server tool çağırmak istiyor.
    case toolCall(calls: [GeminiToolCallRequest])

    /// `error` — sunucu hata.
    case error(message: String)

    /// Bilinmeyen — forward-compat.
    case unknown(snippet: String)

    /// **Sprint 45:** JSON Data → event. Defensive parsing; one-event-per-JSON
    /// (Gemini bazen tek mesajda birkaç içerik gönderir; bu durumda audio
    /// öncelikli — array versionu Sprint 45 sonrası iyileştirme adayı).
    public static func decode(_ data: Data) -> GeminiServerEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // setupComplete
        if json["setupComplete"] is [String: Any] {
            return .setupComplete
        }

        // serverContent
        if let content = json["serverContent"] as? [String: Any] {
            if (content["interrupted"] as? Bool) == true {
                return .interrupted
            }
            if (content["turnComplete"] as? Bool) == true {
                return .turnComplete
            }
            if let modelTurn = content["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                // Audio öncelik — varsa onu döndür
                for part in parts {
                    if let inline = part["inlineData"] as? [String: Any],
                       let b64 = inline["data"] as? String,
                       let mime = inline["mimeType"] as? String,
                       mime.hasPrefix("audio/") {
                        return .audioChunk(base64: b64)
                    }
                }
                // Audio yok → text varsa
                for part in parts {
                    if let text = part["text"] as? String {
                        return .textChunk(text: text)
                    }
                }
            }
        }

        // toolCall
        if let toolCall = json["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            var requests: [GeminiToolCallRequest] = []
            for call in calls {
                let id = (call["id"] as? String) ?? ""
                let name = (call["name"] as? String) ?? ""
                let args = (call["args"] as? [String: Any]) ?? [:]
                requests.append(GeminiToolCallRequest(id: id, name: name, args: args))
            }
            return .toolCall(calls: requests)
        }

        // error
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return .error(message: message)
        }

        // Bilinmeyen — JSON key'lerin ilkini snippet olarak döndür
        let key = json.keys.sorted().first ?? "unknown"
        return .unknown(snippet: key)
    }
}

/// **Sprint 45 (v0.2.72):** `toolCall.functionCalls[]` item.
///
/// **Sendability:** `args` server'dan `[String: Any]` decode olur ama
/// Sendable değil; bu yüzden JSON Data'sı olarak saklar (Sendable byte
/// buffer). Caller `argsJSON` ile JSONDecoder kullanarak rehydrate eder.
public struct GeminiToolCallRequest: Sendable, Equatable {
    public let id: String
    public let name: String
    /// **Args JSON** — Data formatında saklanır (Sendable-safe). Caller
    /// `JSONDecoder().decode(...)` veya `JSONSerialization.jsonObject(with:)`
    /// ile rehydrate eder.
    public let argsJSON: Data

    public init(id: String, name: String, args: [String: Any]) {
        self.id = id
        self.name = name
        // `[String: Any]` → JSON Data. Defensive: encode başarısızsa boş object.
        if JSONSerialization.isValidJSONObject(args),
           let data = try? JSONSerialization.data(withJSONObject: args) {
            self.argsJSON = data
        } else {
            self.argsJSON = Data("{}".utf8)
        }
    }

    public init(id: String, name: String, argsJSON: Data) {
        self.id = id
        self.name = name
        self.argsJSON = argsJSON
    }

    public static func == (lhs: GeminiToolCallRequest, rhs: GeminiToolCallRequest) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.argsJSON == rhs.argsJSON
    }
}
