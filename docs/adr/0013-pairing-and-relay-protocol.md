# ADR-0013: Pairing ve Relay Protokolü

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** protocol, security, cross-platform

## Context

Mac ↔ iOS arasında WebSocket köprüsünü kurmak için iki tarafın aynı "session"a bağlanması gerek. Tarafların çoğunlukla farklı IP'lerde (3G, ev WiFi, kafe WiFi) olabileceği için doğrudan P2P pratik değil — bir relay sunucusu zorunlu. Pairing mekanizması ve auth modeli, MVP basitliği ile güvenlik dengesi gerektiriyor.

## Decision

### Pairing code

- **6 karakter, Crockford-benzeri alfabe**: `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (32 karakter)
- 0/O, 1/I/L kasıtlı **dışlandı** (karışıklık riski)
- Toplam kombinasyon: `32^6 ≈ 1.07B` — kısa ömürlü pairing için yeterli
- Crypto-rastgele üretilir (`Int.random` — MVP; ileride `SystemRandomNumberGenerator` veya `SecRandomCopyBytes`)
- `PairingCode.isValid(_:)` server-side ve client-side validation

### QR payload formatı

```
pixel-agent-pair://?code=ABCXYZ&relay=wss://pixel-agent-relay.erkut.workers.dev
```

- Custom URI scheme: `pixel-agent-pair`
- Query params: `code` (6-char), `relay` (full WSS URL)
- iOS `PairingInfo.init(qrPayload:)` parser
- Schema iOS app `Info.plist` URL handler ile de açılabilir (gelecekte deep link)

### Relay (Cloudflare Worker)

- **Routes:**
  - `GET /connect/{code}` — Mac istemcisi WebSocket upgrade
  - `GET /listen/{code}` — iOS istemcisi WebSocket upgrade
- **Durable Object** (`RelaySession`): her pairing code için tek-instance in-memory state
- **Forward**: bir tarafın gönderdiği mesaj, eşleşen diğer tarafa text frame olarak forward
- **Buffer**: karşı taraf bağlı değilse mesaj **30 saniye** boyunca saklanır (max **200 frame**)
- **Replace**: aynı role için ikinci bağlantı gelirse eski socket `close(1000, 'replaced')` ile kapatılır

### Auth (MVP v0.1)

- **Sadece pairing code** = ortak secret. URL path'inde olduğu için intercept edilirse session compromise olur.
- **TLS** (wss://) zorunlu — Cloudflare otomatik sağlar.
- Pairing code 5 dakikadan kısa sürede çiftlenmeli (idle-out v0.2'de eklenecek).

### Auth (Faz 2, v0.2+)

- Ed25519 anahtar çifti pairing sırasında değiş tokuşlanır
- Her envelope `sig` alanı: payload + ts + id imzalanır
- Relay her iki tarafı imza üzerinden doğrular (relay'in private key yok, sadece public key cache)

## Alternatives considered

- **Bonjour / LAN-only discovery** (v2 yaklaşımı) — aynı WiFi'de zorunlu; uzak çalışmada işe yaramaz. Faz 4 olarak optional.
- **WebRTC peer-to-peer** — STUN/TURN gerekiyor, complexity yüksek; relay daha basit MVP için.
- **OAuth provider** (Google/Apple Sign-in) — kullanıcı zaten kendisi; OAuth gereksiz.
- **WebSocket bearer token** (URL param ek) — pairing code zaten URL'de; ekstra token ek katman ama MVP'de tek source-of-truth tercih edildi.

## Consequences

**Positive**
- Setup 30 saniye: Mac'te QR aç, telefonda tara, bağlandı.
- Cloudflare Worker free tier yeterli (10M req/gün).
- Pairing code human-readable, yedek olarak el yazımı da OK.
- Crockford-benzeri alfabe el yazımı/OCR hatasını azaltır.

**Negative / tradeoffs**
- Tek pairing code session boyunca geçerli — leak olursa session compromise. v0.2'de pairing → kalıcı device key takası ile aşılacak.
- Cloudflare bağımlılığı (LAN-only fallback yok MVP'de).
- Buffer 200 frame / 30s sınırı: yavaş istemci yetişemezse mesaj kaybı. Test edilmeli.

## Lessons from pixel-agent2

v2'de envelope `sig` field'ı vardı (ed25519) ama production'a alınmadı — pairing zaten LAN-token kullanıyordu, sig optional kaldı. v3 MVP'de aynı strateji: önce çalışır pipeline, sonra Faz 2 sig zorunluluğu. Cross-repo sync derdinden de ders: pairing kontratı ([ADR-0012](0012-remote-envelope-schema.md) + bu) PixelRemote modülünde tek noktada tanımlı.

## References

- [ADR-0008 — Remote envelope shared module](0008-remote-envelope-shared-module.md)
- [ADR-0012 — Remote envelope schema](0012-remote-envelope-schema.md)
- [relay/README.md](../../relay/README.md) — deploy talimatları
- [ios/README.md](../../ios/README.md) — iOS Xcode project setup
