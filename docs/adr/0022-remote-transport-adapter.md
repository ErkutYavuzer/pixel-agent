# ADR-0022: `RemoteTransport` Protokolü + Transport Adapter Layer (LAN Faz 2)

**Status:** Accepted (Faz 2 landed)
**Date:** 2026-05-22
**Tags:** transport, abstraction, lan, fallback

## Context

[ADR-0021](0021-lan-mode-bonjour.md) Faz 1'de `PixelLAN` library landed: `LANService`, `LANServerConnection`, `LANClient`. Standalone test edildi ama hiç wired değildi. `RemoteHost` ve iOS `RemoteSession` hâlâ doğrudan `RelayClient`'a bağımlıydı.

Faz 2'nin hedefi: `RemoteHost` ve `RemoteSession`'ı transport-agnostic hâle getirmek + LAN-first-fallback-relay composite'i hazırlamak.

## Decision

### `RemoteTransport` protokolü (`PixelRemote`)

```swift
public protocol RemoteTransport: Sendable {
    func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error>
    func send(_ envelope: RemoteEnvelope) async throws
    func disconnect() async
}
```

Concrete impl'ler:
- **`RelayTransport`** (PixelRemote) — mevcut `RelayClient`'ı sarmalar. URL + pairing code + role (`.mac`/`.ios`) construction time.
- **`LANServerTransport`** (PixelLAN, Mac) — `LANService`'i sarmalar. Birden çok client bağlanırsa inbound stream'leri birleştirir; outbound envelope tüm bağlı client'lara broadcast.
- **`LANClientTransport`** (PixelLAN, iOS+Mac) — `LANClient` + `NWBrowser` ile ilk bulunan host'a `discoveryTimeout` ile bağlanır (varsayılan 2s).
- **`FallbackTransport`** (PixelLAN) — `(primary, fallback)` çifti. `connect()` önce primary'i dener; throws ise fallback'e geçer. `currentSelection: .none | .primary | .fallback` published state.

### `RemoteHost` (Mac) — backward-compatible DI

İki init:

```swift
// Eski API — relayURL'den otomatik RelayTransport oluşturur (v0.2.x test'leri bozmaz)
public init(relayURL: String = "ws://localhost:8787", keyStore: ..., keyService: ..., keyAccount: ...)

// Yeni API — DI ile herhangi bir transport (LAN-server, fallback, vs.)
public init(transport: any RemoteTransport, keyStore: ..., keyService: ..., keyAccount: ...)
```

İç implementasyon `providedTransport: (any RemoteTransport)?` + `activeTransport`. Eski init `nil` set eder; `connect()` runtime'da RelayTransport inşa eder. Yeni init önceden verilmiş transport'u kullanır.

### iOS `RemoteSession` — TransportFactory DI

`RemoteTransportFactory: @Sendable (PairingInfo) -> any RemoteTransport` typealias. Default `defaultRelayTransportFactory` (free fonksiyon — `init` default parameter ifadesi `Self.` referansı taşıyamadığı için class member yerine free function).

```swift
init(keyStore: KeyStoring = ..., transportFactory: @escaping RemoteTransportFactory = defaultRelayTransportFactory)
```

UI'da LAN-first istemek için:

```swift
RemoteSession(transportFactory: { pairing in
    let lan = LANClientTransport(discoveryTimeout: 2.0)
    let relay = RelayTransport(relayURL: ..., pairingCode: pairing.code, role: .ios)
    return FallbackTransport(primary: lan, fallback: relay)
})
```

### `FallbackTransport` semantiği

- `connect()`: primary throws ise primary'nin partial state'ini `disconnect()` ile temizler, sonra fallback'i dener.
- Her iki transport da fail ederse fallback'in hatası propagate eder.
- `send()`: yalnız active transport'a yönlenir. Active yoksa `FallbackError.notConnected`.
- `disconnect()`: active'i kapatır, selection `.none`.

## Backward compatibility

- Eski `RemoteHost(relayURL:...)` init aynen çalışır. Mevcut PixelMacApp kodu değişmedi.
- Eski iOS `RemoteSession()` init de aynen çalışır (factory default = relay).
- `RelayClient` API'si hiç değişmedi; `RelayTransport` thin wrapper.
- 226 test yeşil (211 → +15 yeni transport + fallback testleri).

## Wire-up durumu (UI defaults — Faz 3'e ertelendi)

Bu commit yalnızca **altyapı** landed. Hâlâ:
- **PixelMacApp**: `RemoteHost(relayURL: ...)` ile eski path; LAN sunucusu açık değil.
- **iOS app**: `RemoteSession()` default factory = relay.

Faz 3 (gelecek commit):
- PixelMacApp `RemoteHost(transport: LANServerTransport(...))` + relay'i side-by-side çalıştır (multi-host listener).
- iOS app `RemoteSession(transportFactory: { FallbackTransport(LAN, Relay) })` default.
- TXT record (`pk` + `v`) Bonjour service'e eklenir.
- PairingView'da "LAN bağlı" indicator.

## Test stratejisi

Network.framework bind/browse Bonjour-dependent → CI'da flaky. Bu commit'te:

**Eklenen 15 test:**
- 5 `RelayTransportTests` — init varyantları, invalid pairing code propagation, disconnect idempotency.
- 6 `FallbackTransportTests` — primary success → primary selected; primary fail → fallback selected (+ primary disconnected); both fail → error; send before connect → throws; send routed to active; disconnect resets selection. Test-only `StubTransport` actor ile mock'lanıyor.
- 4 `LANTransportInstantiationTests` — LANServerTransport / LANClientTransport construction sanity.

End-to-end (Bonjour advertise → browse → connect → envelope round-trip) Faz 3 UI wire-up sonrası manual QA + integration tests.

## Consequences

**Olumlu:**
- `RemoteHost` ve `RemoteSession` transport-agnostic. Test edilebilir mock transport ile.
- LAN ve Relay aynı çatı altında — kavramsal yük az.
- `FallbackTransport` reusable; ileride başka kombinasyonlar (örn. WebSocket P2P + LAN + relay) için temel.
- Backward compat tam — v0.2.6 test'lerini hiç bozmadı.

**Olumsuz:**
- Soyutlama bedeli: yeni `RemoteTransport` protokolü + 4 concrete tip = ek dosya + ek kavram.
- iOS `defaultRelayTransportFactory` free fonksiyon olarak (init default parameter Swift kısıtı) — class member ile parite kayıp.
- LAN bind/browse CI'da test edilmiyor; manual QA gerekiyor.

## Alternatives

- **Tek `Transport` enum** (`.relay(...)`, `.lanServer(...)`, `.lanClient(...)`, `.fallback(...)`): switch statement her yere yayılır; protocol abstraction daha temiz.
- **Strategy pattern + closure**: `connect: () async throws -> AsyncThrowingStream` closure'unu doğrudan pass etmek. send/disconnect olmadan yetersiz.
- **`URLSessionWebSocketTask` direkt RemoteHost'ta**: relay-specific; LAN için çözüm değil.
- **Mac side LAN ve Relay otomatik side-by-side** (PixelMacApp app açılışta her ikisini başlatır): Faz 3'e ertelendi — multi-transport receive loop merge tasarımı gerekli.

## References

- `Sources/PixelRemote/RemoteTransport.swift` (protocol)
- `Sources/PixelRemote/RelayTransport.swift`
- `Sources/PixelRemote/RemoteHost.swift` (transport DI)
- `Sources/PixelLAN/LANServerTransport.swift`
- `Sources/PixelLAN/LANClientTransport.swift`
- `Sources/PixelLAN/FallbackTransport.swift`
- `ios/PixelAgentRemote/RemoteSession.swift` (transport factory DI)
- `Tests/PixelRemoteTests/RelayTransportTests.swift`
- `Tests/PixelLANTests/FallbackTransportTests.swift`
- `Tests/PixelLANTests/LANTransportInstantiationTests.swift`
- [ADR-0021](0021-lan-mode-bonjour.md) — Faz 1 PixelLAN library
- [ADR-0008](0008-remote-envelope-shared-module.md) — shared envelope module gerekçesi
