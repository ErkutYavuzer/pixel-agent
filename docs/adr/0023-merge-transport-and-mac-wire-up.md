# ADR-0023: `MergeTransport` + PixelMacApp LAN Wire-Up (LAN Faz 3 — Mac side)

**Status:** Accepted (Mac wire-up landed; iOS LAN-first default Faz 4)
**Date:** 2026-05-22
**Tags:** lan, transport, mac

## Context

[ADR-0022](0022-remote-transport-adapter.md) LAN Faz 2'de `RemoteTransport` protocol + 4 adapter (`RelayTransport`, `LANServerTransport`, `LANClientTransport`, `FallbackTransport`) landed. Altyapı tam, ama UI defaults değişmedi: Mac hâlâ relay-only, iOS hâlâ relay-only.

LAN Faz 3'ün hedefi: **Mac side defaults flip** — iPhone'un hangi yoldan gelirse alabilmek için LAN advertise + relay paralel çalıştır.

`FallbackTransport` sequential (primary fail → fallback). Bu Mac side için yetersiz: hem LAN dinlemeli HEM relay'e bağlı olmalı. **Paralel multi-transport** lazım.

## Decision

### Yeni primitive: `MergeTransport` (PixelLAN)

```swift
MergeTransport(transports: [
    LANServerTransport(configuration: .init(serviceName: nil)),
    RelayTransport(relayURL: url, pairingCode: code, role: .mac),
])
```

Semantik:
- `connect()` her child transport'u sırayla başlatır; throws olan child'ları log'lar (stderr) ve atlar. Hiçbiri bağlanamazsa `MergeError.allTransportsFailed`.
- **Inbound**: tüm live child stream'lerinin envelope'ları tek merged stream'de birleşir. Bir child stream throws ile biterse merged stream **biter saymaz** — diğer child'lar üretmeye devam edebilir.
- **Outbound**: `send(_:)` tüm live child'lara broadcast. En az birine başarılı gönderildiyse return; hepsi fail ederse son hatayı throw eder.
- `disconnect()` idempotent (`isDisconnecting` flag); cascade ile tüm child'ları kapatır.

### `RemoteHost.TransportBuilder` — circular dep çözümü

Mac MergeTransport'unun **iki ihtiyacı** var:
- LANServerTransport: Mac'in `publicKeyBase64`'üne (TXT record metadata için, Faz 4'te).
- RelayTransport: Mac'in `pairingCode`'una (URL path'inde).

Ama Mac'in `RemoteHost` bunları kendi init'inde generate ediyor. Circular: transport, RemoteHost'a; RemoteHost, transport'a ihtiyaç duyar.

Çözüm: yeni init overload **closure builder pattern**:

```swift
public typealias TransportBuilder =
    @MainActor (_ pairingCode: String, _ publicKeyBase64: String) -> any RemoteTransport

public init(
    relayURL: String,
    keyStore: KeyStoring = ...,
    keyService: ..., keyAccount: ...,
    transportBuilder: @escaping TransportBuilder
)
```

`connect()` zamanında builder çağrılır; RemoteHost'un generate ettiği pairingCode + publicKey closure'a enjekte edilir.

Eski init'ler (`init(relayURL:)` ve `init(transport:relayURL:)`) backward-compat — değişmedi.

### PixelMacApp wire-up

```swift
let relayURL = Self.defaultRelayURL
_remoteHost = StateObject(
    wrappedValue: RemoteHost(
        relayURL: relayURL,
        transportBuilder: { code, _ in
            let lan = LANServerTransport(configuration: .init(serviceName: nil))
            if let url = URL(string: relayURL) {
                let relay = RelayTransport(relayURL: url, pairingCode: code, role: .mac)
                return MergeTransport(transports: [lan, relay])
            } else {
                return MergeTransport(transports: [lan])
            }
        }
    )
)
```

iPhone hangi yoldan gelirse:
- Aynı LAN'daysa → Bonjour discovery → LANServerTransport'a TCP connect → handshake → envelope flow
- Farklı ağdaysa → Cloudflare relay → RelayTransport'a → handshake → envelope flow

Mac'in tarafından şeffaf: aynı `RemoteHost.handle(envelope:)` her iki yoldan da çalışır; ed25519 verify zaten transport-bağımsız.

### iOS tarafında değişiklik **yok**

iOS hâlâ relay-only (`RemoteSession` default factory = `defaultRelayTransportFactory`). Yani:
- Mac advertise yapıyor, dinliyor — ama iOS'tan kimse LAN'a connect etmiyor.
- iPhone hâlâ relay üzerinden bağlanıyor — eskisi gibi çalışıyor.

**Bu kasıtlı.** Faz 4'te iOS UI'da LAN-first toggle (UserDefaults persist) + PairingView'da "LAN bağlı" indicator. Backward-compat için iOS'un default'unu flip etmek ilk pairing flow'u kıracak (LAN browse timeout + relay fallback = ekstra 2s latency).

### TXT record durumu

[ADR-0021](0021-lan-mode-bonjour.md) Faz 1'de TXT record `NWListener.Service` API'sinin macOS/iOS sürüm değişkenliği nedeniyle ertelendi. **Faz 3'te de hâlâ kapalı** — Faz 4 (iOS LAN-first default) ile birlikte aktive edilecek (`pk` + `v` TXT keys). Şimdilik iOS LAN browse, Bonjour service adından Mac'i tanır; ed25519 verification authentication için yeterli.

## Consequences

**Olumlu:**
- Mac side artık iki yoldan da iPhone kabul ediyor — kullanıcı LAN'a girince otomatik fayda (relay round-trip kaybolur, latency düşer).
- `MergeTransport` reusable primitive — ileride 3+ transport için (WebRTC P2P + relay + LAN gibi).
- Backward compat tam — eski testler bozulmadı; eski `RemoteHost(relayURL:)` init'i hâlâ çalışıyor.
- Faz 4 iş yükü düşük (sadece iOS factory swap + TXT record + UI indicator).

**Olumsuz:**
- Mac başlangıçta hem listener hem WS client açar; iPhone hâlâ relay üzerinden bağlanıyorsa LAN listener idle (resource overhead ~kB-mertebesi).
- LAN listener Bonjour'u broadcast etmeye çalışırken corporate firewall / multicast suppression olan ağlarda silently fail eder (stderr log'lanır, ama UI'da görünmez).
- iOS opt-in olmadığı için Faz 3'ün "user-facing" değişikliği yok — sadece altyapı flip.

## Faz 4 — gelecek (bu ADR'de değil)

- iOS RemoteSession default factory: `FallbackTransport(LANClientTransport(...), RelayTransport(...))`. UserDefaults flag `pixel-agent.lan-first.v1` (default true).
- TXT record (`pk` + `v`) Bonjour service'e eklenir; iOS browse sonucunda Mac'i pubkey ile validate edebilir (QR scan'sız ilk pairing roadmap'i).
- PairingView'da "LAN bağlı" / "Relay" indicator + manual switch.
- `MergeTransport.currentActiveSource` published state — UI hangi transport'tan envelope geldiğini görsel olarak gösterir.

## Test stratejisi

9 yeni `MergeTransportTests` (test-only `StubTransport` actor ile):
- `testConnectStartsAllChildren` — N child → N connect call
- `testPartialConnectFailureKeepsRemainingActive` — bad child atlanır, good devam
- `testAllConnectFailuresThrows` — `MergeError.allTransportsFailed`
- `testSendBroadcastsToAllLiveTransports` — outbound broadcast
- `testSendSucceedsIfAtLeastOneTransportSucceeds` — partial send fail tolere
- `testSendThrowsIfAllTransportsFail` — total fail propagation
- `testSendBeforeConnectThrows` — `noActiveTransports`
- `testDisconnectCascadesToAllChildren` — child disconnect cascade + idempotency
- `testMergedStreamReceivesFromAllSources` — inbound merge (actor-isolated `Collector` ile data-race-free)

Bonjour broadcast / NWBrowser bind end-to-end Faz 4'te manual QA.

226 → 235 yeşil.

## Alternatives

- **İki ayrı `RemoteHost` instance (LAN + Relay)**: UI iki state ile karmaşıklaşır; `ChatView` hangisini dinleyeceğini bilmez.
- **`RoundRobinTransport`**: outbound'da paylaşım kontrolü zor; iPhone'un cevabını hangi yoldan yollaması belirsiz.
- **Tek transport, dinamik switch**: connect zamanında bilinmeyen "best" transport seçimi. Faz 4'te eklenebilir; şimdilik broadcast yeterli.

## References

- `Sources/PixelLAN/MergeTransport.swift`
- `Sources/PixelRemote/RemoteHost.swift` (`TransportBuilder` overload)
- `Sources/PixelMacApp/PixelMacApp.swift` (PixelLAN dep + MergeTransport wire-up)
- `Tests/PixelLANTests/MergeTransportTests.swift` (9 test)
- [ADR-0021](0021-lan-mode-bonjour.md) — Faz 1 PixelLAN library
- [ADR-0022](0022-remote-transport-adapter.md) — Faz 2 RemoteTransport protocol + adapter layer
