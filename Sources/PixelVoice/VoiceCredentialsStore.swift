import Foundation

/// **Sprint 42 (v0.2.69) — skeleton:** Voice provider API key store.
/// Sprint 43-44'te `OpenAIRealtimeProvider` ve `GeminiLiveProvider` bu store
/// üzerinden API key okuyacak. Sprint 42 MVP'de `AppleVoiceProvider` key
/// gerektirmediği için store sadece UI'a placeholder olarak kullanılır
/// (Settings → Sesli Mod tab).
///
/// **Storage:** Keychain (production). Test'lerde `UserDefaults`-backed
/// fallback (TestCredentialsStore). Şu an MVP'de `UserDefaults` kullanır;
/// Sprint 43'te Keychain'e taşınır (Sources/PixelRemote'taki `KeychainKey
/// Store` paterniyle uyumlu).
public struct VoiceCredentialsStore: @unchecked Sendable {
    public static let openaiKeyDefaultsKey = "pixel.voice.openai.apiKey"
    public static let geminiKeyDefaultsKey = "pixel.voice.gemini.apiKey"

    // **Sprint 42 (v0.2.69):** UserDefaults Sendable değil ama API thread-safe;
    // `@unchecked Sendable` ile struct'a izin ver. Apple framework garantisi.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// **Sprint 42:** OpenAI Realtime API key kaydet. Sprint 43'te kullanılacak.
    public func setOpenAIKey(_ key: String?) {
        if let key, !key.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(key, forKey: Self.openaiKeyDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.openaiKeyDefaultsKey)
        }
    }

    /// **Sprint 42:** OpenAI Realtime API key okuyucu.
    public func openaiKey() -> String? {
        let key = defaults.string(forKey: Self.openaiKeyDefaultsKey)
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    /// **Sprint 42:** Gemini Live API key kaydet. Sprint 44'te kullanılacak.
    public func setGeminiKey(_ key: String?) {
        if let key, !key.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(key, forKey: Self.geminiKeyDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.geminiKeyDefaultsKey)
        }
    }

    /// **Sprint 42:** Gemini Live API key okuyucu.
    public func geminiKey() -> String? {
        let key = defaults.string(forKey: Self.geminiKeyDefaultsKey)
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    /// **Sprint 42:** Provider key var mı? Settings UI status badge için.
    public func hasKey(for provider: VoiceProviderKind) -> Bool {
        switch provider {
        case .apple: return true  // Apple keysiz
        case .openaiRealtime: return openaiKey() != nil
        case .geminiLive: return geminiKey() != nil
        }
    }
}

/// **Sprint 42 (v0.2.69):** Settings UI provider picker — kullanıcı seçimi.
public enum VoiceProviderKind: String, CaseIterable, Sendable, Codable {
    case apple
    case openaiRealtime
    case geminiLive

    public var displayName: String {
        switch self {
        case .apple: return "Apple Speech (lokal)"
        case .openaiRealtime: return "OpenAI Realtime"
        case .geminiLive: return "Gemini Live"
        }
    }

    public var description: String {
        switch self {
        case .apple:
            return "SFSpeechRecognizer + AVSpeechSynthesizer. Lokal, ücretsiz, sıfır API key, ~100ms latency. Function calling ve interrupt zayıf."
        case .openaiRealtime:
            return "OpenAI Realtime WebSocket API. Server-side VAD, function calling, interrupt. PCM16 24kHz. ~$0.06/min input, ~$0.24/min output."
        case .geminiLive:
            return "Google Gemini Live WebSocket API (BidiGenerateContent). Server-side VAD, function calling, interrupt. PCM16 16kHz input / 24kHz output. ~$0.006/min input, ~$0.024/min output (OpenAI'den ~10x ucuz)."
        }
    }

    /// **Sprint 42-45:** Provider kullanıma hazır mı? `apple` her zaman true;
    /// `openaiRealtime` Sprint 43 (audio I/O) + Sprint 44 (function calling +
    /// interrupt); `geminiLive` Sprint 45.
    public var isAvailable: Bool {
        switch self {
        case .apple: return true
        case .openaiRealtime: return true   // Sprint 43-44 (v0.2.70-0.2.71)
        case .geminiLive: return true       // Sprint 45 (v0.2.72)
        }
    }

    /// **Sprint 43 (v0.2.70):** UserDefaults toggle anahtarı — aktif provider.
    /// nil → default `.apple` (geriye uyumluluk).
    public static let activeProviderDefaultsKey = "pixel.voice.activeProvider"
}
