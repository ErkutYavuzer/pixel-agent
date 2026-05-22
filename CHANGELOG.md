# Changelog

`pixel-agent` projesindeki tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) tabanlıdır,
sürümleme [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) kurallarına uyar.

## [Unreleased]

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

### Notes
- v0.2 kalan yol haritası: MCP server expose, Plan Mode, Subagent dispatching, ed25519 envelope signing, LAN-only mode (Bonjour).

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

[Unreleased]: https://github.com/ErkutYavuzer/pixel-agent/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.1.0
