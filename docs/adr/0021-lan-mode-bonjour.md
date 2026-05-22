# ADR-0021: LAN-Only Mode — Bonjour + Network.framework (Relay Bypass)

**Status:** Accepted (Faz 1 landed)
**Date:** 2026-05-22
**Tags:** transport, bonjour, network-framework, lan

## Context

[ADR-0013](0013-pairing-and-relay-protocol.md) pairing'i Cloudflare Worker relay üzerinden tasarladı: Mac ↔ iOS arası tüm trafik internet üzerinden Worker'a uğruyor. Faydaları açık (3G, farklı WiFi, NAT geçişi), ama:

- LAN'da gereksiz round-trip (iki cihaz aynı router'a bağlıysa relay'e gitmek ironik).
- Latency relay'e bağlı (Cloudflare PoP < 50 ms ideal, ama LAN < 5 ms).
- İnternet kesintisi → tüm Mac↔iOS köprüsü çöker.
- Privacy: relay payload'ları görür (sadece bytes ama yine de).

v0.2 yol haritasının son ☐ teknik başlığı: **LAN-only mode** — iki cihaz aynı yerel ağda ise Bonjour ile birbirini bulsun, doğrudan TCP bağlansın, relay bypass.

## Decision

### Yeni library: `PixelLAN`

`PixelRemote`'a depend eder (envelope tipleri için), kendi SPM target'ı.

Public API:
- `LANServiceType` — Bonjour `_pixel-agent._tcp` constant'ları.
- `LANFraming` — envelope ↔ newline-delimited JSON encode/decode. Bridge ve relay framing'iyle aynı pattern.
- `LANService` (actor, Mac) — `NWListener` üzerinden `_pixel-agent._tcp` Bonjour advertise, accept loop, gelen bağlantıları `LANServerConnection` olarak yayınlayan stream.
- `LANServerConnection` — accept edilen client; `incoming: AsyncThrowingStream<RemoteEnvelope>` + `send(_:)` API.
- `LANClient` (actor, iOS+Mac) — `NWBrowser` ile discovery (`DiscoveredHost` listesi), `NWConnection` ile bağlantı + envelope send/receive.

### Transport tasarımı

- **Protokol**: TCP. WebSocket değil — Network.framework'te server-side WebSocket frame parsing manuel iş; raw TCP + newline-delimited JSON çok daha sade.
- **Framing**: `<json>\n` per envelope. Aynı format MCP stdio + relay'le tutarlı; lossless geçiş yapılabilir.
- **Port**: Default 0 (OS auto-assign). Kullanıcı `Configuration.port` ile manuel set edebilir (firewall whitelist senaryoları).
- **Service type**: `_pixel-agent._tcp` — RFC 6335 short name (≤15 char `pixel-agent` OK). Domain `local.`.

### Bonjour TXT record — şimdilik kapalı

İdeal: Mac'in ed25519 public key'i (`pk`) ve protocol version (`v`) TXT record'da. iOS browse ettiğinde hangi Mac'in hangi pubkey olduğunu görür, QR scan'siz tanıyabilir.

Sorun: `NWListener.Service(name:type:domain:txtRecord:)` initializer'ı macOS/iOS sürümleri arasında imzasal değişkenlik gösteriyor (`Data?` vs `NWTXTRecord`). Faz 1'de minimum surface; TXT record Faz 2'de eklenecek.

Şimdilik: Bonjour name'i (kullanıcının cihaz adı) hangi Mac olduğunu söyler. Auth hâlâ pairing code + ed25519 sig üzerinden.

### Faz 1 / Faz 2 / Faz 3 ayrımı

**Faz 1 (landed, bu ADR):**
- `PixelLAN` library + framing + service + client + tests
- Standalone testable
- `RemoteHost` / `RemoteSession` integrasyonu **YOK** — kütüphane caller'a sahip değil

**Faz 2 (gelecek):**
- TXT record (pk + version)
- `RemoteTransport` protocol: `RelayClient` ve `LANClient`'ı abstract eder
- `RemoteHost` + `RemoteSession` constructor'ları transport'u kabul eder
- Otomatik fallback: önce LAN dene, başarısızsa relay'e geç
- `PairingView`'da "LAN bağlı" indicator

**Faz 3 (opsiyonel):**
- WebSocket protokolü (Network.framework `NWProtocolWebSocket.Options`) — relay ile transport-bazlı pariteyi getirir.
- mDNS multicast suppression (örn. corporate networks)
- Pairing-via-Bonjour-TXT: QR scan gerekmeden ilk eşleşme.

### Bağımlılık disiplini

`PixelLAN` → `PixelRemote` → `PixelCore`. Hiçbir UI modül, executable target, MCP server'a bağımlılık yok. SPM ile compile-time döngü engellenir.

## Consequences

**Olumlu:**
- LAN bypass'ın gerekli bütün altyapı parçaları yerinde — Faz 2'de wire-up sadece adapter işi.
- Library standalone testable; CI'da Bonjour broadcast'a bağımlı değil (instantiation + framing testleri).
- Framing pattern bridge/relay/MCP ile aynı — kavramsal yük az.
- Mac/iOS ortak kod (`LANClient` Mac'te de çalışır; sembol paritesi).

**Olumsuz:**
- Bonjour broadcast'in çalışıp çalışmadığı kullanıcı ağ koşullarına bağlı (corporate firewall, multicast suppression). Faz 2'de fallback mantığı kritik.
- TXT record olmadan iOS browser hangi Mac olduğunu sadece cihaz adı + pairing code üzerinden bilebilir. UX biraz zayıf — Faz 2'de fixlenir.
- End-to-end testler bu committe yok; Bonjour CI'da reliable değil. Manual QA gerekli.

## Alternatives

- **WebSocket Faz 1'de**: `NWProtocolWebSocket.Options` mevcut, ama server-side frame handling manual değil — iOS client `URLSessionWebSocketTask` reuse edilebilir. Avantaj. Ama Network.framework WebSocket server-side hâlâ az dokümante; raw TCP + framing daha güvenli ve test edilebilir. Faz 3'e ertelendi.
- **gRPC / Protocol Buffers**: standart, hızlı, ama Swift gRPC kütüphanesi heavy. JSON yeterli (envelope zaten Codable).
- **mDNS olmadan, statik IP + manual config**: kullanıcı IP girer. UX awful, reddedildi.
- **DNS-SD direkt API (`<dns_sd.h>`)**: low-level, ama Network.framework wrapper yeterince ince. Reddedildi.

## Test stratejisi

16 unit test:
- `LANFramingTests` (8): encode/decode roundtrip, multi-line buffer, partial leftover, empty buffer, invalid JSON throws, blank lines ignored, Turkish UTF-8 survival.
- `LANServiceTypeTests` (4): RFC 6335 short-name compliance, domain, TXT key strings, default port.
- `LANInstantiationTests` (4): `LANService` + `LANClient` + `Configuration` construction sanity.

End-to-end (advertise → browse → connect → send) Faz 2'de wire-up sonrası manual QA + integration tests.

## References

- `Sources/PixelLAN/LANServiceType.swift`
- `Sources/PixelLAN/LANFraming.swift`
- `Sources/PixelLAN/LANService.swift`
- `Sources/PixelLAN/LANClient.swift`
- `Tests/PixelLANTests/` (16 test)
- [ADR-0013](0013-pairing-and-relay-protocol.md) — Cloudflare relay tasarımı (Faz 2'de transport adapter ile yan yana çalışacak)
- [Apple — NWListener documentation](https://developer.apple.com/documentation/network/nwlistener)
- [Apple — NWBrowser documentation](https://developer.apple.com/documentation/network/nwbrowser)
