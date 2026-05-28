# ADR-0035: PixelVoice — Realtime Voice Provider Abstraction

**Status:** Accepted (Sprint 42-46 landed; v0.2.69 → v0.2.74)
**Date:** 2026-05-26
**Tags:** voice, realtime, websocket, openai, gemini, apple-speech, mcp, agent

## Context

v3 chat + computer-use + subagent + proaktif ile olgunlaşmıştı ama tamamen **metin** tabanlıydı. pixel-agent2'nin `LiveOrchestrator` realtime voice'u MVP'de kasıtlı atlanmıştı (bkz. madde 697 "MVP'de YOK"). Sesli mod "konuşan kişisel agent" iddiası için doğal bir sonraki adım.

2026 manzarasında realtime voice 3 yolla yapılıyor: lokal (Apple Speech, ücretsiz, on-device), OpenAI Realtime (WebSocket, premium kalite + function calling), Gemini Live (WebSocket, ~10x ucuz). Her birinin audio format ve protokolü farklı. Tasarım sorusu: bunları **tek soyutlama** altında nasıl swap edilebilir kılarız ki UI ve MCP tool köprüsü provider'dan habersiz kalsın?

## Decision

### Yeni library: `PixelVoice` (11. modül)

`VoiceProvider` protokol soyutlaması — UI ve tool köprüsü provider'a bağımsız:

```swift
public protocol VoiceProvider: Sendable {
    func start() async throws            // mic capture + stream başlat
    func stop() async
    var transcripts: AsyncStream<TranscriptEvent> { get }   // interim/final/error
}
```

- **`TranscriptEvent`** (interim / final / error) — provider-agnostic.
- **`MockVoiceProvider`** — programlanabilir event harness (hermetic test).
- **`VoiceSession`** (Sources/PixelMacApp, `@MainActor` ObservableObject) — provider stream → ChatViewModel köprüsü: interim → `injectDraft`, final → `send(text:)`.

### 3 provider, aynı protokol (sprint sırasıyla)

| Provider | Sprint | Transport | Audio | Maliyet |
|---|---|---|---|---|
| `AppleVoiceProvider` | 42 (v0.2.69) | on-device | SFSpeechRecognizer + AVSpeechSynthesizer (tr-TR) | ücretsiz |
| `OpenAIRealtimeProvider` | 43-44 (v0.2.70-71) | URLSessionWebSocketTask | PCM16 24kHz mono | $0.06/$0.24 per min |
| `GeminiLiveProvider` | 45 (v0.2.72) | URLSessionWebSocketTask (BidiGenerateContent) | 16kHz in / 24kHz out | $0.006/$0.024 per min (~10x ucuz) |

Provider swap `RootView.makeVoiceProvider()` dynamic factory ile (UserDefaults aktif provider raw value okur; restart-required).

### Audio + event katmanı (OpenAI Realtime, Sprint 43)

- **`PCMAudioCodec`** (saf) — Int16 PCM ↔ base64 + Float32 ↔ Int16 (Apple AVAudioEngine → OpenAI 24kHz mono spec).
- **`RealtimeEvent`** (saf) — client→server encode + server→client decode (unknown case forward-compat).
- **`RealtimeAudioPlayer`** (actor) — AVAudioEngine PCM16 24kHz mono playback queue.
- `OpenAIRealtimeProvider` server-side VAD ile otomatik response trigger; `AVAudioConverter` Apple↔PCM16.

### Function calling + interrupt (Sprint 44)

- **`OpenAIToolBridge`** (saf) — MCP `ToolDefinition` → OpenAI tool format + **9-tool voice-safe whitelist** (UI manipülasyon tool'ları hariç).
- `PixelVoice → PixelMCPServer` dependency. Voice modunda "Saat kaç?" → `get_current_time` MCP tool → sesli cevap.
- Interrupt: speechStarted → `cancelSpeech()` → `response.cancel` + `RealtimeAudioPlayer.interrupt`.

### Gemini Live paralel (Sprint 45)

- **`GeminiEvent`** + **`GeminiToolBridge`** — BidiGenerateContent JSON tree; `voiceSafeToolNames` whitelist OpenAI'dan reuse. Audio format farkı (16/24kHz) + protokol farkı abstraction altında gizli.

### Tool opt-in (Sprint 46)

- **`VoiceToolPreferences`** (saf) — per-tool UserDefaults override (`pixel.voice.tool.<name>`); `riskyTools` static set (ui_click, subagent_dispatch, install_command…) **default kapalı**, safe tool'lar default açık. Kullanıcı Settings → Sesli Mod → "Voice Tools" ile bilinçli açar.
- `OpenAIToolBridge`/`GeminiToolBridge` `voiceSafeTools(from:preferences:)` runtime filter (eski hardcoded `voiceSafeToolNames` alias korundu).

### Credentials

`VoiceCredentialsStore` (struct) — OpenAI/Gemini API key. Şu an UserDefaults (Keychain migration defer). Settings "Sesli Mod" tab'da API key field + provider picker + System Settings mic/speech deep-link.

## Alternatives considered

- **Tek provider (sadece OpenAI veya sadece Apple)** — abstraction maliyeti ama kullanıcıya maliyet/kalite/gizlilik seçimi sunar (Apple lokal/ücretsiz, Gemini ucuz, OpenAI premium). 3 provider'ın tek protokolde toplanması portfolio değeri de taşır.
- **HTTP streaming (WebSocket yerine)** — realtime bidirectional audio için WebSocket gerekli; OpenAI/Gemini Realtime API'leri zaten WS.
- **Tüm MCP tool'ları voice'a açmak** — `ui_click` gibi destructive tool'un sesli yanlış-tanıma ile tetiklenmesi riskli; voice-safe whitelist + Sprint 46 opt-in tercih edildi.
- **Keychain'de API key (UserDefaults yerine)** — doğru olan bu; MVP'de UserDefaults, migration v0.2.72+ defer.
- **iOS voice** — Background App Refresh + sustained WebSocket + AVAudioSession ekstra config; Mac-only MVP yeterli, defer.

## Consequences

**Olumlu:**
- "Konuşan kişisel agent" — yeni demo-able yetenek tier'ı.
- Tek `VoiceProvider` abstraction → yeni provider eklemek sadece protokol conformance (gelecekte ör. local Whisper).
- Function calling ile voice modunda MCP tool çağrısı — agent sesli "ekran görüntüsü al" diyebilir.
- Gemini Live ~10x ucuz → günlük kullanım ekonomik.

**Olumsuz:**
- macOS-specific (AVAudioEngine, SFSpeechRecognizer); iOS voice defer.
- API key UserDefaults'ta (Keychain değil) — güvenlik borcu.
- WebSocket sustained connection + audio buffer enerji/bandwidth maliyeti.
- Provider switch restart-required (hot-reload defer).
- 3 provider = 3 ayrı event/codec yolu bakım yükü (abstraction azaltır ama sıfırlamaz).

## Plan (iterative)

- **Sprint 42 ✓** (v0.2.69): PixelVoice + VoiceProvider + TranscriptEvent + AppleVoiceProvider + VoiceSession + mic FAB + Settings "Sesli Mod" tab.
- **Sprint 43 ✓** (v0.2.70): OpenAI Realtime Faz A — PCMAudioCodec + RealtimeEvent + RealtimeAudioPlayer + OpenAIRealtimeProvider (server-side VAD).
- **Sprint 44 ✓** (v0.2.71): OpenAI Realtime Faz B — function calling (OpenAIToolBridge + 9-tool whitelist) + interrupt; PixelVoice→PixelMCPServer dep.
- **Sprint 45 ✓** (v0.2.72): Gemini Live — GeminiEvent + GeminiToolBridge + GeminiLiveProvider.
- **Sprint 46 ✓** (v0.2.74): Voice tools opt-in — VoiceToolPreferences per-tool runtime filter.
- **Defer (v0.2.72+):** API key Keychain migration; cost dashboard UI (token + USD estimate); hot-reload provider switch; iOS voice; mascot "listening" interrupt UI feedback.

## References

- [`Sources/PixelVoice/`](../../Sources/PixelVoice/) — VoiceProvider, TranscriptEvent, MockVoiceProvider, AppleVoiceProvider, OpenAIRealtimeProvider, GeminiLiveProvider, PCMAudioCodec, RealtimeEvent, RealtimeAudioPlayer, GeminiEvent, OpenAIToolBridge, GeminiToolBridge, VoiceToolPreferences, VoiceCredentialsStore
- [`Sources/PixelMacApp/VoiceSession.swift`](../../Sources/PixelMacApp/VoiceSession.swift)
- [ADR-0004 — ChatBackend Protocol Abstraction](0004-chatbackend-protocol-abstraction.md) (aynı "protokol soyutlama, implementasyon swap" ilkesi)
- [ADR-0016 — MCP Server Expose](0016-mcp-server-expose.md) (function calling tool kaynağı)
- [OpenAI — Realtime API](https://platform.openai.com/docs/guides/realtime)
- [Google — Gemini Live API](https://ai.google.dev/gemini-api/docs/live)
- [Apple — SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
