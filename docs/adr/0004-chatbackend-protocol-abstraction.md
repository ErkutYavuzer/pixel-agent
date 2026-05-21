# ADR-0004: ChatBackend Protokol Soyutlaması

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, multi-provider

## Context

MVP'de tek backend (Anthropic) ile başlıyoruz, ama mimari farklı LLM provider'ları (OpenAI, Gemini, Apple FoundationModels, CLI subprocess'leri) eklemeye açık olmalı. Tool API sözleşmeleri provider'lar arasında farklıdır (Anthropic Messages, OpenAI tool_calls, Gemini functionCall) — bu farkı orchestration katmanından gizlemek gerek.

## Decision

`ChatBackend` protokolü tek arayüz tanımlar:

```swift
public protocol ChatBackend: Sendable {
    var acceptsImage: Bool { get }
    func setSystemPrompt(_ prompt: String) async
    func stream(_ messages: [Message]) -> AsyncThrowingStream<StreamDelta, Error>
    func oneShot(_ messages: [Message]) async throws -> String
    func oneShotMultimodal(_ messages: [Message], images: [Image]) async throws -> String
}
```

Her provider bu protokolü implement eder. Tool schema format çevirisi her implementer'ın sorumluluğunda. `oneShotMultimodal` default implementation text-only `oneShot`'a düşer — vision-uyumsuz backend graceful fallback.

## Alternatives considered

- **Monolithic switch statement** — `ToolDispatcher` içinde `switch provider` — 500+ satır spaghetti, yeni provider eklemek için merkezi dosya güncellemek gerek.
- **Type erasure + reflection** — `AnyChatBackend` runtime type check; Swift type-safety kaybolur, performans cost.
- **Config-driven factory (JSON spec)** — Provider tanımı JSON'da; MVP için aşırı, sınanması zor.

## Consequences

**Positive**
- Open-closed: yeni provider için tek bir dosya (protokol impl + format renderer) yeter.
- Test mock'u tek satır: `class MockChatBackend: ChatBackend { ... }`.
- `AppDelegate.backend = AnthropicBackend()` tek atama; akış kesintisiz.
- Vision fallback graceful (default impl).

**Negative / tradeoffs**
- Protokol genişlerse (yeni method eklenirse) tüm implementer'lara baskı.
- `Sendable` conformance her implementer için disipline gerektirir.

## Lessons from pixel-agent2

v2'de `ChatBackend` 7 provider'ı aynı dispatch path'inde yönetti (Anthropic API + CLI, OpenAI-compat, Gemini, Ollama, MiniMax, Apple Intelligence, Codex CLI). Yeni provider eklemek günler değil saatler aldı. Vision fallback chain (Anthropic → Gemini → OpenAI) `oneShotMultimodal` default impl üzerinde kuruldu.

## References

- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-2)
