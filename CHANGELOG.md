# Changelog

`pixel-agent` projesindeki tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) tabanlıdır,
sürümleme [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) kurallarına uyar.

## [Unreleased]

### Changed — dokümantasyon konsolidasyonu (22 May 2026)
- README v0.2.4 + 177 test + 18 ADR durumuyla yeniden yazıldı. Eski `(hazırlanıyor)` placeholder'ları temizlendi (ADR 0001-0009 zaten içerikle dolu, sadece linkler stale idi). Sürüm geçmişi tablosu + tool tablosu eklendi.
- `docs/architecture.md` v0.2.4 ile senkronlandı: modül grafiğine `PixelMCPServer` + `pixel-mcp-server`; AnthropicBackend referansları çıkarıldı; CLIBackend + Plan Mode `ChatOptions` akışı; ed25519 imzalı Mac↔iOS handshake sequence; yeni MCP server akışı (Faz 1 saf-data + Faz 2 Unix socket bridge); katman tablosu + tasarım prensipleri (10 madde) güncel.

### Notes
- v0.2 kalan yol haritası: Subagent dispatching, LAN-only mode (Bonjour), App Store signing.

## [0.2.4] — 2026-05-22

**Plan Mode** (Claude `--permission-mode plan`) + **MCP Faz 2 Unix socket bridge** ile bundle-bağımlı tool'lar (DockBadge, Notify, Sound). v0.2.3'ten sonra biriken 2 büyük başlık. **177 test yeşil** (+11). Breaking change yok.

### Added — MCP server expose Faz 2: Unix socket bridge (22 May 2026)
- **`BridgeProtocol`** (PixelMCPServer): `BridgeRequest` + `BridgeResponse` Codable tipleri; `BridgePaths.defaultSocketPath()` → `~/Library/Caches/dev.erkutyavuzer.pixel-agent/control.sock`.
- **`BridgeClient`** (PixelMCPServer): POSIX `socket(AF_UNIX, SOCK_STREAM)` single-shot RPC. connect → write newline-delimited JSON → read until `\n` → close. `BridgeError` (`socketCreateFailed`/`pathTooLong`/`connectFailed`/`writeFailed`/`readFailed`/`decodeFailed`).
- **`ControlSocketServer`** (PixelMacApp, actor): `socket → bind → listen → accept loop` background `DispatchQueue` üzerinde. Dispatch sırasında MainActor hop (DockBadge.set NSApp.dockTile gerektirir). `start()`/`stop()` idempotent.
- **3 yeni bridge tool** (`BuiltInTools` registry, toplam 5 → 8):
  - `dock_badge_set` — `label: String|null`, Dock badge'i ayarla/temizle
  - `notify` — `title` (zorunlu), `body` (opsiyonel), sistem bildirimi
  - `play_sound` — `name`, macOS sistem sesi
- `PixelMacApp.RootView.task` içinde `Self.controlServer.start()` — açılışta başlatılır; hata stderr'e log.
- `SystemNotifications.isBundledApp` tighten: artık `bundleURL.pathExtension == "app"` da kontrol ediliyor (xctest'te exception fırlatmasını önler).
- 11 yeni test: 7 `BridgeProtocolTests` (Codable roundtrip, path validation, BridgeClient missing socket) + 4 `ControlSocketServerTests` (e2e bind + connect + dispatch, unknown tool failure, notify success, notify-without-title rejection, start/stop idempotency).
- Toplam test: **166 → 177** yeşil.
- [ADR-0018](docs/adr/0018-mcp-bridge-unix-socket.md): Unix socket bridge tasarımı + alternatif analizi (TCP localhost / XPC / NSDistributedNotificationCenter / AppleEvents reddedildi).

### Added — Plan Mode (22 May 2026)
- `PixelCore.ChatOptions` (yeni struct): `planMode: Bool` ve sonraki opsiyonlar için extension noktası.
- `ChatBackend.send(messages:system:options:)` — yeni 3-argümanlı method; 2-arg overload extension'da default `ChatOptions()` ile sarmalanmış (eski call-site'ları kırmaz; impl'ler ekspisit güncellendi).
- `CLIBackend.arguments(for:prompt:options:)`: Claude için `options.planMode == true` ise `--permission-mode plan` flag'i; Codex/Gemini'de no-op.
- `ChatViewModel.planMode` @Published — `send()` çağrısında `ChatOptions(planMode:)` olarak backend'e geçilir.
- `PixelMacApp` top bar: `Toggle(.button)` "Plan" + `list.bullet.clipboard` icon; selected backend Claude değilse tooltip uyarısı. State per-app-launch (persist yok).
- `ChatView` ve `DualChatHost`: `planMode: Bool` parametresi + `.onAppear`/`.onChange` ile child `ChatViewModel.planMode`'a propagate.
- `ChatComposer`: plan mode aktifken placeholder "Plan modu — sadece okuma/araştırma" + TextField turuncu kontur overlay.
- 4 yeni CLIBackendTests (Claude args planMode on/off, Codex/Gemini'de no-op).
- [ADR-0017](docs/adr/0017-plan-mode.md): Plan Mode tasarımı.
- Toplam test: 162 → **166** yeşil.

### Notes
- v0.2 kalan yol haritası: Subagent dispatching, MCP Faz 2 (bundle-bağımlı tool'lar), LAN-only mode (Bonjour), App Store signing.

## [0.2.3] — 2026-05-22

Mac + iOS arasında **end-to-end ed25519 imzalı kanal**, **MCP server expose Faz 1** (5 saf-data tool, claude-cli uyumlu), iOS App Store asset/manifest hazırlığı, **162 test yeşil**. v0.1.0'dan beri biriken 10 commit'in 4 büyük başlığı bu sürümde.

### ⚠️ Breaking change
- Remote protocol v1 → v2. v0.1.x istemciler v0.2.3 relay'ine bağlanamaz; iOS app güncellenmeli + yeni QR taranmalı. UserDefaults pairing key `v1 → v2` (eski pairing'ler invalide).

### Added — MCP server expose Faz 1 (22 May 2026)
- **`PixelMCPServer`** kütüphanesi: `JSONValue` (tip-güvenli JSON ağacı), `JSONRPCMessage` (Request/Response/Error tipleri + standart error code'lar), `ToolRegistry` (`ToolDefinition` + descriptor üretimi), `MCPServer` actor (handle/processLine/runStdio).
- **`pixel-mcp-server`** executable target — `main.swift` 3 satır, `MCPServer.runStdio()` çağırır.
- **5 built-in tool**: `get_clipboard`, `set_clipboard`, `get_current_time`, `get_active_app`, `get_lan_ip` (hepsi bundle-bağımsız, standalone CLI'dan çalışır).
- `LANInterfaceAddress.primary()` — `getifaddrs` ile en0/en1 IPv4 tespiti (PixelMacApp'taki helper'dan kopya; ortak modüle taşıma TODO).
- MCP protocol version `2024-11-05`. Methods: `initialize`, `tools/list`, `tools/call`, `ping`, `initialized` (notification).
- 30 yeni test (5 JSONValue + 6 JSONRPCMessage + 11 MCPServer + 8 ToolRegistry). **Toplam 162 test yeşil.**
- `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | swift run pixel-mcp-server` ile end-to-end sanity doğrulandı.
- [ADR-0016](docs/adr/0016-mcp-server-expose.md): Faz 1 (saf-data tool'lar, stdio transport) landed; Faz 2 (bundle-bağımlı tool'lar Unix socket bridge ile) gelecek.

### Added — ed25519 envelope signing Faz 2 wire-up (22 May 2026)
- **Mac `RemoteHost`**: `init(keyStore:keyService:keyAccount:)` DI; `publicKeyBase64` expose (QR için); `isPaired` published state; receive loop'ta ilk envelope hello + publicKey olmazsa drop; sonraki envelope'lar peer pubkey ile verify edilir; `sendAssistantMessage` outbound imzalı.
- **`PairingView`** (PixelMacApp): QR payload `URLComponents` ile üretiliyor, `pk=<mac-pubkey-b64>` query param eklendi; %-encoding güvenli.
- **iOS `RemoteSession`**: `init(keyStore:)` DI (varsayılan KeychainKeyStore); `publicKeyBase64` hello için; `connect(pairing:)` bağlanır bağlanmaz hello envelope (unsigned, kendi pubkey'i) gönderir; outbound `EnvelopeSigner.sign`, inbound peer pubkey ile verify; UserDefaults key `pixel-agent.pairing.v1` → `v2` (eski pairing'ler invalide); `macPublicKey` PairingInfo'da zorunlu alan.
- **`PairingInfo`** (iOS): `macPublicKey: String` zorunlu; QR parser `pk` query item + base64 + 32-byte + Curve25519 validation; geçmezse nil (eski QR'lar reddedilir).
- 3 yeni RemoteHostTests (toplam 10): `publicKeyBase64` exposed + 32 byte raw; aynı KeyStore aynı pubkey üretir; farklı KeyStore'lar farklı pubkey'ler.
- Toplam test: 132 yeşil.
- ADR-0015 Faz 2 detayları güncellendi.

### Added — ed25519 envelope signing foundation (21 May 2026)
- `PixelRemote.EnvelopeSigner` (`sign(_:with:)`, `verify(_:with:)`, `canonicalBytes(of:)`) — Curve25519 EdDSA ile envelope imza/doğrulama. Canonical encoding: `sig` alanı boş bırakılır, `JSONEncoder(.sortedKeys)` ile encode edilir.
- `PixelRemote.KeyStoring` protocol + `KeychainKeyStore` (Security framework, `kSecAttrAccessibleAfterFirstUnlock`) + `InMemoryKeyStore` (test/CI için hermetic).
- `EnvelopePayload.publicKey: String?` alanı; `RemoteEnvelope.hello(publicKey:)` factory — handshake'in ilk envelope'u.
- `PixelRemote.protocolVersion` 1 → 2 (signed envelopes; geriye uyum yok).
- 14 yeni test: 8 EnvelopeSigner (sign/verify roundtrip, tampered sig, wrong pubkey, missing sig, corrupt base64, deterministic-vs-random check, canonical encoding sig-agnostic, re-sign), 6 KeyStore (round-trip, scoping by service/account, clear, persistence across loads).
- [ADR-0015](docs/adr/0015-ed25519-envelope-signing.md): Faz 1 (foundation) landed; Faz 2 (RemoteHost + RemoteSession wire-up) gelecek commit.

### Added — iOS App Store hazırlığı (21 May 2026)
- **AppIcon** (`ios/PixelAgentRemote/Assets.xcassets/AppIcon.appiconset/`): 1024×1024 master PNG, `PixelMascot.idleFrame` (12×12 ASCII grid) + default palette'ten türetiliyor. Xcode tek master'dan tüm boyutları üretir.
- **Launch screen**: `UILaunchScreen` Info.plist dictionary — `LaunchBackground` (koyu mor `#1C142E`) + `LaunchIcon` mascot imageset (@1x/@2x/@3x). Storyboard'a gerek yok.
- **AccentColor.colorset** — iOS tint mor (dark mode için ayrı varyant).
- **PrivacyInfo.xcprivacy** — App Store gereksinimi. `NSPrivacyTracking: false`; `NSPrivacyAccessedAPITypes` sadece UserDefaults reason `CA92.1` (pairing persist).
- `scripts/generate-app-icon.py` — PixelMascot ASCII grid + palette'ten AppIcon + LaunchIcon PNG'leri üreten reproducible Python script (Pillow dependency).
- `ios/project.yml`: `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor`; `CFBundleShortVersionString` 0.1.0 → 0.2.0; build 1 → 2.
- [ADR-0014](docs/adr/0014-ios-app-store-assets.md): icon/launch/privacy manifest tasarım kararı.
- `ios/README.md` xcodegen flow + asset üretim talimatı ile yeniden yazıldı (eski "Xcode New Project" manuel kurulum çıkarıldı).

### Test
- 91 (v0.1.0) → **162** test. 71 yeni: 14 ed25519 Faz 1 (8 EnvelopeSigner + 6 KeyStore), 5 Faz 2 (RemoteEnvelope + RemoteHost ek), 30 MCP server, 22 dual-agent + stream-json + Codex (önceki commit'lerden).

### Changed (v0.2.0 → v0.2.3 cumulative)
- Mac `ChatView` dual-agent paralel sohbet desteğine refactor (v0.2.1, e2d9fa4).
- Claude CLI stream-json parser ile gerçek token-by-token streaming (v0.2.2, 67723c7).
- 60s backend timeout watchdog (6aba9e9).
- Codex CLI desteği `exec --json` + stdin + `CodexJSONParser` (8bb11d1).
- iOS auto-reconnect 5s timeout (bc7bf49) + Hakkında sayfası.

### Removed
- v1 remote protocol. `pixel-agent.pairing.v1` UserDefaults key'leri sessizce yok sayılır (yeni QR taratılması beklenir).

## [0.1.0] — 2026-05-21

İlk public release. Mac core stabil; iOS uzak istemcisi pairing + bidirectional chat olarak iskelet hazır. 6 sprint, 7 commit, ~3000 satır Swift + TypeScript, 90+ test.

### Added — Hafta 6 (21 May 2026)
- **MIT lisansı** (`LICENSE`); README badge `tbd → MIT`; "Lisans" bölümü güncel.
- **DocC documentation pipeline**: `Sources/PixelCore/Documentation.docc/PixelCore.md` catalog; `swift-docc-plugin` 1.5 dependency; `.github/workflows/docs.yml` (multi-target combined documentation → GitHub Pages deploy).
- **iOS↔Mac bidirectional message forward** (en kritik Hafta 6 işi):
  - `PixelRemote.RemoteHost` (yeni, @MainActor ObservableObject): RelayClient wrap; `isConnected/pairingCode/lastError/relayURL` published state; `connect/disconnect/sendAssistantMessage/regenerateCode`; `inboundTexts: AsyncStream<String>` iOS userMessage envelope'larını text olarak yayar.
  - `PairingView` yeniden: `@ObservedObject RemoteHost`, "Bağlan/Kes" butonu, durum noktası (yeşil = bağlı), hata gösterimi.
  - `ChatView` refactor: `incomingRemoteText: Binding<String?>` + `onAssistantComplete: ((String) -> Void)?` parametreler; `.onChange(of: incomingRemoteText)` ile iOS mesajını backend'e gönder; assistant stream final → callback ile RemoteHost'a forward.
  - `ChatHost`: `@StateObject RemoteHost`, `.task` ile inbound stream consume → `incomingFromRemote` state'i güncelle; toolbar'da iOS bağlı icon (`iphone.gen3.radiowaves.left.and.right`); QR butonu PairingView sheet.
- Test: 7 yeni (91 toplam) — `RemoteHostTests` (init/relay URL/regenerate/connect error paths/send no-op/disconnect idempotent).

### Added — Hafta 5 (21 May 2026)
- **Cloudflare Worker relay** (`relay/`): TypeScript + Durable Objects. `RelaySession` her pairing code için tek-instance. Routes: `/connect/{code}` (Mac), `/listen/{code}` (iOS). Mesajları bidirectional forward; karşı taraf bağlı değilse 30s/200-frame buffer. `wrangler dev`/`wrangler deploy` script'leri. README deploy talimatı.
- `PixelRemote.RelayClient` (actor): `URLSessionWebSocketTask` wrap, `connect(relayURL:pairingCode:role:)` → `AsyncThrowingStream<RemoteEnvelope, Error>`, `send`, `disconnect`. Pairing code + WebSocket scheme validation.
- `PixelRemote.PairingCode`: 6-karakter, Crockford-benzeri alfabe (32 char, 0/1/O/I/L hariç). `generate()` + `isValid(_:)`.
- `PixelRemote.RelayError`: `notConnected`/`invalidRelayURL`/`invalidPairingCode`/`encodingFailed`/`decodingFailed` (Türkçe LocalizedError).
- `PixelRemote.RelayRole`: `mac` (→ `/connect`) / `ios` (→ `/listen`) path mapping.
- `PixelMacApp.PairingView`: QR kod görseli (CoreImage `CIFilter.qrCodeGenerator`), pairing code, relay URL. `pixel-agent-pair://?code=...&relay=...` payload. `ChatHost` toolbar'da QR butonu, sheet olarak açılır.
- **iOS app source** (`ios/PixelAgentRemote/`): `PixelAgentRemoteApp` (@main + RemoteSession StateObject), `ContentView` (bağlıysa ChatView, değilse PairingScannerView), `RemoteSession` (ObservableObject + RelayClient + PairingInfo parser), `PairingScannerView` (AVCaptureSession QR scanner, UIViewControllerRepresentable), `ChatView` (iOS mesaj listesi + composer), `Info.plist` (NSCameraUsageDescription). Xcode project kullanıcı tarafından setup edilecek — `ios/README.md` talimat içerir.
- [ADR-0013](docs/adr/0013-pairing-and-relay-protocol.md): pairing & relay protokol kararı (Crockford-32 alfabe, QR URI scheme, Cloudflare DO, auth modeli + Faz 2 ed25519 planı).

### Added — Hafta 4 (21 May 2026)
- `PixelMemory.ConversationStore` (actor): JSONL append-only conversation persist. `~/Library/Application Support/pixel-agent/conversation.jsonl`. `append/loadAll(limit:)/newConversation()/messageCount()`. `newConversation` mevcut dosyayı `archive/` altına timestamp ile taşır. Bozuk JSON satırlar atlanır (graceful degradation).
- `PixelMacApp`: `RootView` `ConversationStore` init eder; init hatası → `ErrorView`. `ChatView.task` ile açılışta son 200 mesaj restore. Her user/assistant mesajı stream sonunda store'a append. "Yeni sohbet" butonu (status bar'da, `plus.bubble` icon) → arşivle + ekranı temizle.
- `PixelRemote.RemoteEnvelope` (Codable + Sendable struct): `v/id/ts/type/payload?/sig?`. `EnvelopeType` enum (hello/ready/ping/ack/error/userMessage/assistantMessage). `EnvelopePayload` (flat optional fields: text/role/messageID/errorCode/errorMessage/metadata). Convenience factories: `.userMessage(text:)`, `.ping()`, `.ack(referenceID:)`, `.error(code:message:)`. [ADR-0012](docs/adr/0012-remote-envelope-schema.md).

### Added — Hafta 3 (21 May 2026)
- `PixelMascot`: 48×48 pixel-art sprite (12×12 ASCII grid + renk palette); 4 state (idle/thinking/speaking/error); `MascotView` SwiftUI `Canvas` render; `MascotPalette` özelleştirilebilir (default mor temalı); ascii grid → karakter map (X=body, H=highlight, S=shadow, O/o/x=göz, M/_=ağız).
- `PixelTools`: scope yeniden tanımlandı — CLI tool wrapper değil, native macOS toolkit ([ADR-0011](docs/adr/0011-native-macos-toolkit.md)). `DockBadge` (NSApp.dockTile.badgeLabel wrap, test ortamında no-op), `SystemNotifications` (UNUserNotificationCenter, Türkçe karakter destek), `SoundEffect` (Glass/Basso/Tink system sounds).
- `ChatView` entegrasyon: üst-sağ köşede `MascotView` (32px); stream başlat → `.thinking`; ilk token → `.speaking`; done → `.idle`; throw → `.error`. Foreground'da `SoundEffect.play`, background'da `DockBadge.set("1")` + `SystemNotifications.post`.
- `RootView.task`: açılışta `UNUserNotificationCenter.requestAuthorization`.

### Removed — Hafta 2.5 (21 May 2026)
- `AnthropicBackend` (URLSession + SSE streaming) silindi. Yerine `CLIBackend` geldi — gerekçe ve detay için bkz. [ADR-0010](docs/adr/0010-cli-subprocess-backend.md).
- `AnthropicError` → yerine jenerik `BackendError`.
- `SSEParser` → CLI subprocess'lerinde SSE yok, gereksiz.

### Added — Hafta 2.5 (21 May 2026)
- `PixelBackends`: `CLIBackend` (subprocess wrapper, claude/codex/gemini); `CLIDetector` (bilinen path + `which` fallback); `CLIProcessRunner` (Process API + async byte stream); `BackendError` (cliNotFound / processFailed / exitNonZero / noBackendAvailable, Türkçe LocalizedError).
- `PixelMacApp`: `RootView` artık `CLIDetector` ile yüklü CLI'ları tespit eder; `ChatHost` segmented Picker ile anlık backend değişimi; `MissingBackendView` seçili CLI yüklü değilse; `ErrorView` hiçbir CLI yoksa "Tekrar tara".

### Added — Hafta 2 (21 May 2026)
- `PixelCore`: `Message`, `MessageRole`, `StreamDelta`, `ChatBackend` protokolü, `AgentID`, `AgentContext` (TaskLocal scoping). ADR-0003 ve ADR-0004 hayata geçti.
- `PixelMacApp`: SwiftUI `ChatView` (mesaj listesi + canlı streaming composer + ESC ile iptal).

### Added — Hafta 1 (21 May 2026)
- Swift Package Manager monorepo iskeleti (6 library + 1 executable target).
- `PixelCore`, `PixelBackends`, `PixelTools`, `PixelMemory`, `PixelMascot`, `PixelRemote`, `PixelMacApp` modülleri (stub).
- 9 ADR (Architecture Decision Records) — `docs/adr/0001-0009`.
- `docs/architecture-decisions-from-v2.md` — pixel-agent2'den çıkarılan 14 mimari karar ve 3 anti-pattern.
- `docs/architecture.md` — mermaid modül + akış diyagramları.
- SwiftLint (`.swiftlint.yml`) ve swift-format (`.swift-format`) konfigürasyonları.
- `scripts/lint.sh`, `scripts/pre-commit.sh`, `scripts/install-hooks.sh` yardımcı scriptleri.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): build (debug+release), test (parallel + coverage), SwiftLint.
- Issue ve pull request şablonları.
- `SECURITY.md` güvenlik bildirim politikası.

### Test
- 90+ yeşil test (Hafta 1: 7 placeholder → Hafta 6: 91 toplam).

### Notes
- Swift toolchain: 6.0+ (Swift 6 language mode).
- Platform: macOS 14+, iOS 17+ (uzak istemci).
- Lisans: MIT.

[Unreleased]: https://github.com/ErkutYavuzer/pixel-agent/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.4
[0.2.3]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.3
[0.1.0]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.1.0
