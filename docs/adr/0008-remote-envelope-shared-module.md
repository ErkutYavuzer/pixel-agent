# ADR-0008: Remote Envelope Shared Module

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** protocol, cross-platform

## Context

Mac core ile iOS uzak istemci WebSocket üzerinden mesajlaşacak. Protokol kontratı (envelope tipleri, payload şemaları, imza scheme) her iki tarafta bire bir senkronize kalmalı. v2'de iki ayrı repo (`pixel-agent2` + `pixel-agent-remote`) olduğu için kontrat sync borç haline geldi: iOS tarafında 1100 satır Phone Tool kodu commit edilmeyi bekledi çünkü Mac receiver tarafı yoktu.

## Decision

`PixelRemote` modülü hem `PixelMacApp` (executable) hem iOS Xcode project tarafından import edilir. Envelope tipleri tek noktada tanımlı:

```swift
public enum EnvelopeType: String, Codable, Sendable {
    case hello, ready, ping, ack, error
    case userMessage, assistantMessage, toolMessage
    case toolInvoke, toolResult
    // ...
}

public struct RemoteEnvelope: Codable, Sendable {
    public let v: Int
    public let id: String       // ULID
    public let ts: Int          // unix sec
    public let type: EnvelopeType
    public let payload: Payload
    public let sig: String?     // ed25519, optional
}
```

iOS Xcode project SPM dependency olarak `pixel-agent` monorepo'sunu import eder (local path veya git remote). Envelope tipi değişimi Swift compile-time her iki tarafta kontrol edilir.

## Alternatives considered

- **Cross-repo manuel sync** — v2 pattern, sync derdi büyüdü; reddedildi.
- **Protobuf code generation** — `.proto` dosyası tek kaynak, Swift+TS code gen; setup overhead, Cloudflare Worker bundling karmaşıklığı.
- **OpenAPI spec + codegen** — REST için tasarlandı, WebSocket streaming için awkward.

## Consequences

**Positive**
- Kontrat tek kaynaktan; mismatch compile-time yakalanır.
- iOS tarafı Mac değişimini otomatik görür (SPM resolve).
- Test edilebilir: aynı struct'ı her iki platformda XCTest ile encode/decode round-trip.

**Negative / tradeoffs**
- iOS Xcode project ↔ SPM local dependency kurulumu (relative path veya git submodule).
- Cloudflare Worker (TypeScript) bu Swift modülünü kullanamaz — JSON şeması ayrıca dokümante edilmeli (`docs/protocol/envelope.md` ileride).

## Lessons from pixel-agent2

v2 ↔ v2-remote sync boşluğu canlı bir örnek: iOS `ctrlToolInvoke` envelope tipi tanımlandı, 1100 satır handler yazıldı, ama Mac `RemoteCommandRouter` receiver implement edilmediği için commit edilemedi. Tek modül pattern bu derdi yapısal olarak imkânsız kılar.

## References

- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-7)
