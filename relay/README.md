# pixel-agent relay (Cloudflare Worker)

WebSocket forward server. Mac (`/connect/{code}`) ve iOS (`/listen/{code}`) tarafları aynı 6-haneli pairing code ile eşleşir; mesajlar bidirectional forward edilir.

**Mimari:** Durable Object (`RelaySession`) her pairing code için tek-instance state tutar. Karşı taraf bağlı değilse mesajlar 30s boyunca buffer'lanır (max 200 frame).

## Geliştirme

```bash
cd relay
npm install
npm run dev          # local wrangler dev server (port 8787)
```

Local test için Mac istemci `ws://localhost:8787/connect/ABC123`, iOS istemci `ws://localhost:8787/listen/ABC123`.

## Deploy

```bash
npm install
npx wrangler login    # ilk kez
npm run deploy        # Cloudflare hesabına push
```

Deploy sonrası endpoint: `wss://pixel-agent-relay.<your-subdomain>.workers.dev`.

## API

| Route | Yön | Açıklama |
|---|---|---|
| `GET /connect/{code}` | Mac → relay | WebSocket upgrade, 6-haneli pairing code |
| `GET /listen/{code}` | iOS → relay | WebSocket upgrade, aynı pairing code |
| `GET /` | — | Health check (text plain) |

Pairing code formatı: `[A-Z0-9]{6}` (case-sensitive, uppercase + rakam). Format dışı → 400.

## Mesaj formatı

Text frame'ler `RemoteEnvelope` JSON serialization (Swift `PixelRemote` modülü). Binary frame'ler şu anda forward edilmez (text-only relay).

## Sınırlamalar (v0.1.0)

- Auth: pairing code dışında ek bearer token yok (v0.2'de ed25519 sig).
- Buffer in-memory (Durable Object restart → buffer kaybı).
- Frame size limit yok; Worker default 100MB request, 1MB WebSocket message.
- Cross-region: Durable Object tek lokasyonda; coğrafi gecikmeler olabilir.

## Logs

```bash
npm run tail
```
