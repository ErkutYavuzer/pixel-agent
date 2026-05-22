# ADR-0025: iOS LAN-First Default + TXT Record + Transport Indicator (LAN Faz 4)

**Status:** Accepted (Faz 4 landed)
**Date:** 2026-05-22
**Tags:** lan, ios, bonjour, transport

## Context

[ADR-0021](0021-lan-mode-bonjour.md) Faz 1'de `PixelLAN` library altyapısı landed; [ADR-0022](0022-remote-transport-adapter.md) Faz 2'de `RemoteTransport` protocol + 4 adapter (`RelayTransport`, `LANServerTransport`, `LANClientTransport`, `FallbackTransport`); [ADR-0023](0023-merge-transport-and-mac-wire-up.md) Faz 3'te `MergeTransport` ile Mac side LAN+Relay paralel yayın.

Üç eksik kaldı:

1. **TXT record pasifti** — `LANService.Configuration.publicKeyBase64` + `protocolVersionTXT` parametreleri vardı ama `NWListener.Service`'e iletilmiyordu. ADR-0021 "platform sürümü değişkenliği" diye Faz 2'ye ertelendi.
2. **iOS hâlâ relay-only** — `defaultRelayTransportFactory` default'tu. Aynı LAN'da Mac↔iPhone arası tüm trafik Cloudflare relay'den geçiyor (ironik, latency yüksek).
3. **Bağlantı tipi görünmüyor** — kullanıcı LAN'da mı internet üzerinden mi bağlandığını bilmiyor. UX + privacy şeffaflığı eksik.

Faz 4 bu üçünü kapatır.

## Decision

### TXT record (LANService → Bonjour)

Yeni `LANTXTRecord` helper (`Sources/PixelLAN/LANTXTRecord.swift`):

```swift
public enum LANTXTRecord {
    public static func encode(_ entries: [String: String]) -> Data
    public static func decode(_ data: Data) -> [String: String]
}
```

DNS-SD wire format (RFC 6763 §6): her giriş `<length-byte><key=value-bytes>`. Anahtarlar alfabetik sıralanır → deterministic encoding (test edilebilirlik). 0 byte ve >255 byte girişler atlanır.

`LANService.start()` artık `Configuration`'dan TXT record üretip `NWListener.Service(txtRecord:)`'a iletiyor (`pk` + `v` anahtarları). `LANClient` zaten `NWBrowser.bonjourWithTXTRecord` kullanıyordu — `DiscoveredHost.publicKeyBase64` + `protocolVersionTXT` artık dolu gelir.

`NWTXTRecord` Apple wrapper'ı yerine manuel encoder tercih edildi: deterministic (test edilebilir), platform-version değişkenliği yok, RFC 6763'e birebir.

### iOS LAN-first default

`ios/PixelAgentRemote/RemoteSession.swift`'te iki factory:

```swift
@Sendable func defaultLANFirstTransportFactory(for pairing: PairingInfo) -> any RemoteTransport {
    let lan = LANClientTransport(discoveryTimeout: 2.0)
    let relay = relayTransport(for: pairing)
    return FallbackTransport(primary: lan, fallback: relay)
}

@Sendable func defaultRelayTransportFactory(for pairing: PairingInfo) -> any RemoteTransport {
    relayTransport(for: pairing)
}
```

`RemoteSession.init(transportFactory:)` default'u **`defaultLANFirstTransportFactory`** oldu. Aynı LAN'daysa Bonjour 2 saniye içinde Mac'i bulur → doğrudan TCP. Bulamazsa `FallbackTransport.connect()` `RelayTransport`'a düşer.

2 saniye discovery timeout pragma: corporate WiFi'lerde Bonjour multicast filtrelenebilir, kullanıcı çok bekleyemez.

### Transport indicator

`RemoteSession`'a `@Published var transportLabel: String?` eklendi. `connect()` sonrası aktif transport tipinden türetilir:
- `FallbackTransport.currentSelection == .primary` → `"LAN"`
- `FallbackTransport.currentSelection == .fallback` → `"Relay"`
- `LANClientTransport` direkt → `"LAN"`
- `RelayTransport` direkt → `"Relay"`
- Diğer → `"Bağlı"`

`ChatView` header'da pairing code'un solunda renkli capsule rozet:
- `LAN` → yeşil (yerel ağ, düşük gecikme)
- `Relay` → mavi (internet üzeri Cloudflare Worker)

`disconnect()` `transportLabel`'ı `nil`'e çeker.

### Mac PairingView yayın rozeti

`PairingView.statusRow` artık iki satır:
1. `Circle + "iPhone bağlı / Bağlı değil"` (mevcut)
2. `"Mac yayını: LAN (Bonjour) + Relay paralel"` (sabit bilgi metni)

Mac side `MergeTransport` her ikisini aynı anda dinler (ADR-0023). Hangi yoldan iOS'un geldiğini ayırt etmek için envelope-source tracking gerekirdi — Faz 4 scope dışı. Sabit bilgi metni şimdilik yeterli.

### Info.plist + xcodegen güncellemeleri

`ios/PixelAgentRemote/Info.plist`:
- `NSLocalNetworkUsageDescription` — "gelecekte LAN modu" → "LAN modu, Bonjour discovery" (artık aktif).
- `NSBonjourServices` array eklendi: `["_pixel-agent._tcp"]` (iOS 14+ zorunlu: app sadece Info.plist'te listelenmiş service type'ları browse edebilir).
- `CFBundleShortVersionString` → `0.2.11`, `CFBundleVersion` → `3`.

`ios/project.yml` aynı şekilde + `dependencies` artık `PixelLAN` ürününü de çekiyor.

## Consequences

**Olumlu:**
- Aynı ağdaki Mac↔iPhone trafiği relay'den geçmez — latency ~5 ms (LAN) vs ~50 ms (Cloudflare PoP).
- İnternet kesintisinde LAN üzerinden bağlantı korunur.
- TXT record sayesinde iOS browser hangi Mac'in hangi pubkey'e sahip olduğunu Bonjour'dan biliyor — gelecekte QR-less re-pairing imkânı.
- Kullanıcı bağlantı tipini görüyor (LAN vs Relay rozeti) → privacy şeffaflığı.
- Faz 1-3 altyapısı caller'a sahip oldu; v0.2 yol haritasındaki LAN-only mode kapandı.

**Olumsuz:**
- İlk bağlantıda 2 saniye discovery delay (LAN Bonjour timeout) — relay-only'ye göre yavaş ilk pairing. Re-connect daha hızlı (cached pairing + LAN listed).
- Corporate WiFi'lerde mDNS suppression varsa otomatik relay'e düşme şart; UX "neden 2 saniye sürdü" sorusunu doğurabilir.
- Mac side "hangi transport'tan iOS bağlandı" bilgisi yok — Faz 5'te envelope source tag ile çözülebilir.
- `LANClientTransport.discoveryTimeout` hard-coded 2s; settings UI Faz 5+'a ertelendi.

## Out of scope (Faz 5+)

- Mac side per-iOS transport tracking (LAN vs Relay rozeti Mac PairingView'da dinamik).
- TXT record üzerinden QR-less re-pairing (pairing kaydedilmiş + Mac aynı `pk` ile aynı LAN'da → auto-trust).
- mDNS multicast suppression detection (corporate WiFi early-warning).
- WebSocket protokol LAN (Network.framework `NWProtocolWebSocket`) — şu an raw TCP + newline JSON.

## Alternatives

- **TXT record Apple `NWTXTRecord` wrapper kullan**: SDK'ya bağımlı; deterministic değil (dict iteration order). Manuel encoder tercih edildi (test edilebilir).
- **iOS LAN-only**: relay fallback'i kaldır. Farklı ağdayken bağlantı kopar — reddedildi.
- **Discovery timeout configurable (UI)**: Faz 5'e. Şu an 2s sabit, çoğu LAN için yeterli.
- **Discovery sırasında loading indicator**: `isAutoConnecting` mevcut UX'i kullanıyor — yeterli.

## References

- `Sources/PixelLAN/LANTXTRecord.swift` (yeni)
- `Sources/PixelLAN/LANService.swift` — TXT record set
- `ios/PixelAgentRemote/RemoteSession.swift` — `defaultLANFirstTransportFactory` + `transportLabel`
- `ios/PixelAgentRemote/ChatView.swift` — transport badge
- `Sources/PixelMacApp/PairingView.swift` — Mac yayın rozeti
- `ios/PixelAgentRemote/Info.plist` + `ios/project.yml` — NSBonjourServices + PixelLAN dep + version bump
- `Tests/PixelLANTests/LANTXTRecordTests.swift` (6 yeni test)
- [ADR-0021](0021-lan-mode-bonjour.md) — PixelLAN Faz 1
- [ADR-0022](0022-remote-transport-adapter.md) — RemoteTransport adapter
- [ADR-0023](0023-merge-transport-and-mac-wire-up.md) — Mac side wire-up
- [RFC 6763 §6 — DNS-SD TXT records](https://datatracker.ietf.org/doc/html/rfc6763#section-6)
