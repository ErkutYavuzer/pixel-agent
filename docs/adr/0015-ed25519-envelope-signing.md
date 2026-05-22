# ADR-0015: ed25519 Envelope Signing (Faz 2 Auth)

**Status:** Accepted (Faz 1: foundation landed; Faz 2: handshake wire-up landed)
**Date:** 2026-05-21 (Faz 1) → 2026-05-22 (Faz 2)
**Tags:** security, protocol, cross-platform

## Context

v0.1.x'te Mac ↔ iOS arası tek auth katmanı 6-karakter pairing code'du ([ADR-0013](0013-pairing-and-relay-protocol.md)). Pairing code:
- Cloudflare relay'in URL'inde transit ediyor (relay görür).
- Tek seferlik short-lived olsa bile, **relay compromise olursa MITM** mümkün — relay sahte envelope inject edebilir.
- iOS app'te UserDefaults'a persist ediliyor; cihaz kaybolursa veya backup leak olursa pairing kalıcı reuse edilebilir.

ADR-0013'te "Faz 2: ed25519 message signing" planlanmıştı. Bu ADR Faz 2'nin **foundation katmanını** (Faz 1: signer + key store) tanımlıyor; pairing handshake'e wire up Faz 2'de yapılacak.

## Decision

### Algorithm

- **ed25519** (Curve25519 EdDSA). CryptoKit native, macOS 14+ ve iOS 17+'da hazır.
- Public key: 32 byte → base64 ~44 karakter.
- Signature: 64 byte → base64 ~88 karakter.
- Apple CryptoKit `signature(for:)` **ek randomness** kullanır — aynı (key, payload) ikilisi her seferinde farklı geçerli imza üretebilir. Bu API kontratıdır, deterministic ed25519 assumption'ı yapılmamalı.

### Canonical encoding

Hem imzalama hem doğrulama, envelope'un **`sig` alanı boşaltılmış** (`nil`) halinin `JSONEncoder` ile `outputFormatting: [.sortedKeys]` set edilerek encode edilmiş byte temsilini hesaplar. Bu sayede:
- Aynı semantik içerikten her zaman aynı byte stream çıkar (Swift JSONEncoder default'u sıralı değildir).
- Mevcut `sig` alanı yoksayılır — re-signing destekli.

### Key store

`KeyStoring` protocol + iki concrete impl:
- `KeychainKeyStore`: production. Security framework, `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`. Raw 32-byte private key `kSecValueData` olarak saklanır.
- `InMemoryKeyStore`: test/CI. Sandbox dışındaki Swift unit testleri Keychain erişimi alamayabilir; CI'da hermetic tutmak için.

`loadOrCreate(service:account:)` tek atom işlem: kayıt varsa onu döner, yoksa yeni üretip kaydedip döner.

### Protocol version

`PixelRemote.protocolVersion` 1 → 2. **Geriye uyum kasıtlı kırıldı** (v3 monorepo memory'sine göre: "Avoid backwards-compatibility hacks when you can just change the code"). v0.1.x istemciler bağlanamayacak; kullanıcı bilgilendirilmesi gerek.

### Hello envelope

`EnvelopePayload`'a `publicKey: String?` alanı eklendi. `RemoteEnvelope.hello(publicKey:)` factory'si handshake'in ilk envelope'unu üretir; her iki taraf (Mac + iOS) bağlantı kurar kurmaz public key'ini hello envelope'unda gönderir.

## Faz 1 — foundation (BU ADR ile landed)

- `Sources/PixelRemote/EnvelopeSigner.swift`: `sign(_:with:)`, `verify(_:with:)`, `canonicalBytes(of:)`.
- `Sources/PixelRemote/KeyStore.swift`: `KeyStoring` protocol + `KeychainKeyStore` + `InMemoryKeyStore`.
- `EnvelopePayload.publicKey` field; `RemoteEnvelope.hello(publicKey:)` factory.
- `PixelRemote.protocolVersion = 2`.
- 14 yeni test (8 EnvelopeSigner + 6 KeyStore).

## Faz 2 — wire-up (landed)

- **Mac `RemoteHost`**:
  - `init(keyStore: KeyStoring, keyService:, keyAccount:)` DI ile signing key yüklenir.
  - `publicKeyBase64` property QR payload için expose.
  - `isPaired` state — iOS hello aldığımızda `true`.
  - `connect()` sonrası ilk envelope **hello + publicKey** olmak zorunda; aksi sessizce drop edilir.
  - Hello'dan iOS pubkey çıkarılır, `peerPublicKey` set edilir.
  - Sonraki tüm envelope'lar `EnvelopeSigner.verify(_:with: peerPublicKey)` ile doğrulanır; geçmezse drop.
  - `sendAssistantMessage` outbound'u önce imzalar.
- **`PairingView`** (PixelMacApp): QR payload `URLComponents` ile `pk=<mac-pubkey-b64>` query param eklenir; %-encoding güvenli.
- **iOS `RemoteSession`**:
  - `init(keyStore:)` DI.
  - `publicKeyBase64` property hello için.
  - `connect(pairing:)` başarılı WS connect sonrası **ilk iş** `RemoteEnvelope.hello(publicKey:)` gönderir (unsigned — chicken-and-egg).
  - Outbound mesaj `EnvelopeSigner.sign` ile imzalanır; inbound mesaj `peerPublicKey = pairing.macPublicKey` ile verify edilir, geçmezse drop.
  - `macPublicKey` `pairing` içinden gelir; UserDefaults `pixel-agent.pairing.v2` key'inde `pk` ile birlikte persist.
- **`PairingInfo`** (iOS): `macPublicKey: String` zorunlu alan; QR parser `pk` query item'ı + base64 + 32-byte + Curve25519 validation yapar; yoksa nil döner (eski QR'lar geçersiz).
- **Relay (Cloudflare Worker)** değişmez — relay görmüyor, sadece forward.
- **Handshake özeti**: iOS QR'dan Mac pubkey'i alır → bağlanır → hello (unsigned, kendi pubkey'i ile) → Mac peer pubkey'i öğrenir → bundan sonra iki taraf da her envelope'u imzalar/doğrular.

## Consequences

**Olumlu:**
- Relay compromise olsa bile MITM mümkün değil — saldırgan geçerli imza üretemez.
- Replay attack: `ts` alanı + sliding window ile bonus güvence (Faz 2'de).
- Foundation tamamen test edildi, Faz 2'de sadece "wire up" işi kalıyor.

**Olumsuz:**
- Protocol break: v0.1.x istemciler v0.2.x relay'ine bağlanamaz. Memory'deki "no compat hack" kuralına uyumlu ama kullanıcı iletişimi gerek.
- Pairing QR uzar (~50 karakter daha). QR kod yoğunluğu artar.
- Keychain üzerinde key yönetimi: kullanıcı app'i silip yeniden kurarsa yeni keypair çıkar → eski pairing'ler invalide olur. Bu kabul edilebilir (security feature).

## Alternatives

- **TLS client cert**: relay'in TLS termination yapması ve cert pinning. Daha karmaşık, Cloudflare Worker'da yapması zor, debug-friendly değil.
- **HMAC pre-shared key**: simetrik, pairing-time'da paylaşılır. ed25519'dan daha basit ama: relay PSK'yı görür → relay compromise senaryosunda yine kırılır. Asimetrik tercih edildi.
- **Noise Protocol (Noise_NK)**: profesyonel düzeyde tasarım ama scope için aşırı; explicit handshake + AEAD ekstra karmaşıklık getirir. v0.x için ed25519 raw signing yeterli.

## References

- [Apple — Curve25519.Signing](https://developer.apple.com/documentation/cryptokit/curve25519/signing)
- [ADR-0013 Pairing & relay protokolü](0013-pairing-and-relay-protocol.md) — Faz 2 referansı buradan
- `Sources/PixelRemote/EnvelopeSigner.swift`
- `Sources/PixelRemote/KeyStore.swift`
