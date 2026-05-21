# ADR-0012: Remote Envelope Schema

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** protocol, cross-platform

## Context

[ADR-0008](0008-remote-envelope-shared-module.md) `PixelRemote` modülünün Mac + iOS arasında paylaşılmasını kararlaştırdı. Bu ADR, envelope'un somut şemasını ve veri tipleme stratejisini sabitler — iOS Xcode project Hafta 5'te bağlanacak; kontrat şimdiden donmalı, sonradan değişim cross-platform sync derdine dönmesin.

## Decision

### Tek struct, enum-driven tipleme

```swift
public struct RemoteEnvelope: Codable, Sendable, Equatable {
    public let v: Int                  // protocol version (şu an 1)
    public let id: String              // UUID (ULID v0.2+)
    public let ts: Int                 // unix saniye
    public let type: EnvelopeType      // enum (case-driven dispatch)
    public let payload: EnvelopePayload?
    public let sig: String?            // ed25519 imza (Faz 2+)
}
```

### `EnvelopeType` — closed enum

```swift
public enum EnvelopeType: String, Codable, Sendable, CaseIterable {
    case hello, ready, ping, ack, error, userMessage, assistantMessage
}
```

MVP'de 7 case. Closed enum'un anlamı: bilinmeyen `type` string'i decode hatası verir. Bu kasıtlı — eski iOS client yeni Mac envelope tipi göremezse fail-loud, sessiz drop yok.

### `EnvelopePayload` — flat optional fields

```swift
public struct EnvelopePayload: Codable, Sendable, Equatable {
    public var text: String?
    public var role: String?
    public var messageID: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]?
}
```

Associated value'lu enum yerine flat optional fields. Sebep:
- Codable conformance otomatik (associated value enum için custom encode/decode lazım)
- JSON şeması düz (debug için `jq` ile okunur)
- Yeni alan eklemek = optional field ekle (backward compat korunur)

### Factory helpers

`RemoteEnvelope.userMessage(text:)`, `.ping()`, `.ack(referenceID:)`, `.error(code:message:)` gibi convenience constructor'lar. Tip + payload doğru eşleşmesini compile-time enforced eder.

### Backward compatibility

`JSONDecoder` default davranışı: extra JSON field'ları decode sırasında ignore edilir (Codable struct kendisi listelenmemiş key'leri görmez). Test edildi (`testExtraJSONFieldsAreIgnored`).

Sonuç: iOS client Mac'tan extra field içeren bir envelope alırsa hata olmaz; sadece tanıdığı alanları kullanır.

## Alternatives considered

- **Associated value enum** (`case userMessage(text: String)`) — daha tip-güvenli ama Codable boilerplate ciddi. JSON şeması da `{"userMessage": {...}}` gibi olur, düz değil.
- **Generic `Payload<T>` parametresi** — her tip için ayrı `RemoteEnvelope<UserMessagePayload>`. Type erasure sorunu, transport katmanında karışıklık.
- **Open enum (Codable extra case tolerance)** — `unknown(String)` case'i eklemek. Sessiz drop davranışına yol açar; debug zor. Tercih edilmedi.
- **Protobuf** — binary serialization, schema codegen. Setup overhead MVP için fazla.

## Consequences

**Positive**
- Tek source-of-truth tip; Mac + iOS aynı struct'ı import eder.
- JSON şeması düz, `jq` ile debug edilir.
- Extra field tolerance: protokol evrim yumuşak.
- Closed enum + missing field throw: fail-loud davranış, sessiz veri kaybı yok.

**Negative / tradeoffs**
- `EnvelopePayload`'ın optional field listesi büyürse "kullanılan field'lar neler?" netliği azalır. Cevap: ileride payload'ı varyant struct'lara ayır (mesaj türü başına ayrı payload tipi); şimdilik MVP'de overkill.
- ULID yerine UUID kullanıldı (sade). Sıralama gerektiren senaryolarda ULID'ye geçilebilir (v0.2).

## Lessons from pixel-agent2

v2'de `RemoteEnvelopeType` 28 case'a kadar şişti (live audio, approval request, ctrl, tool result, vb.). Her case için payload ihtiyaçları farklıydı. Flat optional field yaklaşımı 28 case'de sürdürülebilir kalmadı; field listesi 20+ oldu. v3'te MVP'de 7 case ile başlanır; case 12-15'e ulaştığında payload'ı varyant struct'lara ayırma kararı yeniden gözden geçirilir.

## References

- [ADR-0008 — Remote envelope shared module](0008-remote-envelope-shared-module.md)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-7) — v2 envelope deneyimi
