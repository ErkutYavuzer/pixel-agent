# Changelog

`pixel-agent` projesindeki tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) tabanlıdır,
sürümleme [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) kurallarına uyar.

## [Unreleased]

### Added — Hafta 2 (21 May 2026)
- `PixelCore`: `Message`, `MessageRole`, `StreamDelta`, `ChatBackend` protokolü, `AgentID`, `AgentContext` (TaskLocal scoping). ADR-0003 ve ADR-0004 hayata geçti.
- `PixelBackends`: `AnthropicBackend` (URLSession + SSE streaming, default model `claude-sonnet-4-6`, ANTHROPIC_API_KEY ENV var); pure `SSEParser`; `AnthropicError` (LocalizedError).
- `PixelMacApp`: SwiftUI `ChatView` (mesaj listesi + canlı streaming composer + ESC ile iptal); `RootView` composition root; `ErrorView` (API key eksikse kullanıcı dostu mesaj + "Tekrar dene").
- Test kapsamı: **29 yeşil test** (Hafta 1: 7 placeholder + Hafta 2: 22 yeni — `MessageTests`, `AgentContextTests` (TaskLocal scope + child Task propagation), `MockChatBackendTests`, `AnthropicBackendTests` (init validation + localized error), `SSEParserTests` (content_block_delta, message_stop, edge cases, Unicode)).

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

### Notes
- Swift toolchain: 6.0+ (Swift 6 language mode).
- Platform: macOS 14+.
- Lisans henüz belirlenmedi.
