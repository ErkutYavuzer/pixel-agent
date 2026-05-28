# ADR-0036: Relay Launcher + URL Resolver — Zero-Setup iOS Connectivity

**Status:** Accepted (Sprint 47-49 landed; v0.2.75 → v0.2.78) · ⚠️ production URL Cloudflare cert ile bloke
**Date:** 2026-05-27
**Tags:** relay, cloudflare, wrangler, websocket, connectivity, deployment

## Context

iOS↔Mac pairing baştan beri ([ADR-0013](0013-pairing-and-relay-protocol.md)) Cloudflare Worker relay üzerinden çalışıyordu, ama relay **manuel** başlatılıyordu: kullanıcı `cd relay && npx wrangler dev --ip 0.0.0.0` çalıştırmak zorundaydı. Sorunlar:

1. **Mac restart sonrası relay düşük** — kullanıcı her açılışta terminal'den wrangler başlatmayı unutuyordu → "iOS bağlanmıyor" raporu.
2. **Homebrew install kullanıcıları** repo'yu klonlamadığı için `relay/` dizinine erişemiyordu.
3. **Mac sleep/quit'te relay tamamen düşüyor** — telefon Mac'ten bağımsız bağlanamıyordu.

LAN-only mode ([ADR-0021](0021-lan-mode-bonjour.md)) aynı ağda çözüyor ama uzaktan (cellular) erişim relay'e bağımlı. Hedef: **sıfır-setup connectivity** — kullanıcı hiçbir şey yapmadan iOS bağlanabilsin.

## Decision

Üç katmanlı çözüm (sprint sırasıyla), hepsi `Sources/PixelMacApp/` içinde:

### Katman 1 — Otomatik subprocess + URL resolver (Sprint 47, v0.2.75)

- **`RelayLauncher`** (`@MainActor` ObservableObject) — `npx wrangler dev` subprocess'ini app launch'ta otomatik spawn eder. Watchdog (5s cooldown, max 3 restart) + SIGTERM/SIGKILL graceful exit (`NSApplication.willTerminateNotification`).
- **`RelayURLResolver`** (saf enum) — 5-tier fallback chain + `.Source` introspection (UI'da hangi tier aktif gösterilir):

  ```
  1. UserDefaults custom URL    (kullanıcı Settings'te girdi)
  2. PIXEL_RELAY_URL env        (dev override)
  3. production Cloudflare URL   (hardcoded, Sprint 49)
  4. LAN IP                      (Bonjour, ADR-0021)
  5. localhost                   (son çare, lokal wrangler)
  ```

- **`scripts/deploy-relay.sh`** — `wrangler whoami` + `wrangler deploy` automation.
- Settings "Bağlantı" tab — auto-start toggle + aktif URL + kaynak (`.Source`) + custom URL field.

### Katman 2 — Bundle portability (Sprint 48, v0.2.76)

Homebrew kullanıcıları için relay'i app içine taşı:
- **Build-time** (`scripts/build-app.sh`): `relay/{wrangler.toml, package.json, package-lock.json, src/}` → `Contents/Resources/relay/`. **`node_modules` HARİÇ** (167MB → bundle 7.9MB).
- **First launch:** `RelayLauncher.ensureWritableCopy(from:to:)` → `~/Library/Application Support/pixel-agent/relay/` (idempotent, `package-lock.json` byte-diff check).
- **Lazy install:** `node_modules` yoksa `runNpmInstall()` async (`npm install --no-audit --no-fund --prefer-offline`, ~30s). `isInstallingDependencies` @Published → Settings ProgressView.

### Katman 3 — Production Cloudflare deploy (Sprint 49, v0.2.77)

- `wrangler deploy` → `pixel-agent-relay.erkutyavuzer.workers.dev`. Free plan compat için SQLite DO migration (`new_classes` → `new_sqlite_classes`).
- `RelayURLResolver.productionURL` = `"wss://pixel-agent-relay.erkutyavuzer.workers.dev"` (Sprint 47'de nil placeholder).
- `RelayLauncher.isAutoStartEnabled` default `false` — production URL var, lokal wrangler opsiyonel.

## ⚠️ Active blocker — Cloudflare workers.dev cert (Sprint 49.1, v0.2.78)

`wrangler deploy` başarılı, subdomain Cloudflare dashboard'da listeli (`erkutyavuzer.workers.dev`, 4.12k lifetime request) **ama production URL TLS handshake'i `Cipher 0000` ile reddediyor**. Tanı: hesap-seviyesi workers.dev wildcard cert provisioning'i **2024 Workers Free Plan policy değişikliğiyle de-provisioned**. Lokal TLS stack sağlam (`cloudflare.com` handshake OK), sorun edge cert'inde.

**Code-side çözülemez** — Cloudflare support ticket veya yeni subdomain/custom domain gerek. Hot-fix (v0.2.78): `isAutoStartEnabled` default `false` → `true` revert → lokal wrangler + LAN ile çalışmaya devam. `productionURL` kodda kalır; Cloudflare-side fix olunca resolver chain otomatik devreye girer (Sprint 49.2 ile default tekrar OFF).

## Alternatives considered

- **Relay'i tamamen Cloudflare'e taşı, lokal wrangler'ı kaldır** — cert blocker bunu şu an imkansız kılıyor; lokal subprocess fallback olarak korundu (sağlam karar — blocker'a karşı dayanıklılık).
- **`node_modules`'ı bundle'a dahil et** — 167MB bundle (7.9MB yerine); lazy `npm install` ~30s ilk-launch maliyeti karşılığında bundle küçük kalır.
- **Custom domain (kendi alan adı)** — cert sorununu çözer ama domain satın alma + DNS setup kullanıcı işi; workers.dev subdomain "ücretsiz" yolu tercih edildi (şimdilik cert'le bloke).
- **Key-value DO (SQLite yerine)** — free plan key-value DO'ları desteklemiyor (2024 policy); SQLite-backed DO migration zorunlu, API transparan.
- **Alternatif relay host (Fly.io, Railway, self-hosted)** — Cloudflare çözülmezse açık seçenek; relay kodu Worker-spesifik (Durable Object) olduğu için port maliyeti var.

## Consequences

**Olumlu:**
- Fresh install → app aç → (lokal wrangler veya production) iOS bağlanır, manuel terminal yok.
- Bundle portability ile Homebrew kullanıcıları repo klonlamadan relay kullanır.
- 5-tier resolver chain dayanıklı: bir tier düşse alt tier devreye girer; `.Source` introspection ile debug edilebilir.
- productionURL kodda hazır — Cloudflare fix anında kod değişikliği gerektirmez.

**Olumsuz:**
- **Production relay şu an çalışmıyor (cert blocker)** — iOS cellular erişim lokal wrangler'a (Mac açık olmalı) veya LAN'a bağımlı; Mac sleep/quit'te düşer.
- Lokal wrangler subprocess + lazy npm install Mac kaynağı tüketir + ilk launch ~30s.
- `node` PATH bağımlılığı (Launchpad-spawned app minimal PATH — v0.2.17 EnvironmentBuilder ile kısmen çözülmüş ama wrangler için node şart).
- Cloudflare hesap/billing'e bağımlılık (vendor lock-in riski).

## Plan (iterative)

- **Sprint 47 ✓** (v0.2.75, v0.2.76'da bundle): RelayLauncher + RelayURLResolver + deploy-relay.sh + Settings "Bağlantı" tab.
- **Sprint 48 ✓** (v0.2.76): bundle copy (node_modules hariç) + ensureWritableCopy + lazy npm install.
- **Sprint 49 ✓** (v0.2.77): production deploy + productionURL hardcoded + auto-start default false.
- **Sprint 49.1 ✓** (v0.2.78): cert blocker hot-fix — auto-start default true revert.
- **🔴 Açık (kullanıcı/Cloudflare):** workers.dev cert provisioning (support ticket / yeni subdomain / custom domain). Çözülünce **Sprint 49.2**: auto-start default OFF + production canlı.

## References

- [`Sources/PixelMacApp/RelayLauncher.swift`](../../Sources/PixelMacApp/RelayLauncher.swift)
- [`Sources/PixelMacApp/RelayURLResolver.swift`](../../Sources/PixelMacApp/RelayURLResolver.swift)
- [`relay/`](../../relay/) — Cloudflare Worker (Durable Object) + wrangler.toml
- [`scripts/deploy-relay.sh`](../../scripts/deploy-relay.sh)
- [ADR-0013 — Pairing ve Relay Protokolü](0013-pairing-and-relay-protocol.md)
- [ADR-0021 — LAN-Only Mode (Bonjour)](0021-lan-mode-bonjour.md) (relay fallback'i)
- [Cloudflare — Durable Objects (free plan SQLite)](https://developers.cloudflare.com/durable-objects/)
