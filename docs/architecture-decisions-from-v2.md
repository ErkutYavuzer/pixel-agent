# pixel-agent2'den Çıkarılan Mimari Kararlar

> Bu doküman, `pixel-agent2` (~246 Swift dosya / ~64k LOC) kod tabanının analizinden çıkarılan **v3'te korunmaya değer 14 mimari karar deseni** ile **tekrar edilmemesi gereken 3 anti-pattern**'i kayıt altına alır. Her karar, v3'teki ADR çekirdek setine (`docs/adr/0001-0009`) zemin oluşturur.
>
> **Analiz tarihi:** 2026-05-21
> **Kaynak repo:** `~/Projects/pixel-agent2` (referans olarak korunur, kod kopyalanmaz)

---

## Karar 1: TaskLocal Scoping — Agent ve Subagent Context Yayılımı

**v2 referansı:** `Sources/PixelAgent/ToolDispatcher.swift:52-64`, `Sources/PixelAgent/Subagent/SubagentRuntime.swift:139-147`, `Sources/PixelAgent/ToolSchemas.swift:35,41`

**Ne yapıyor:** Swift Concurrency `@TaskLocal` ile agent kimliğini (`.primary`, `.secondary`), subagent UUID'sini ve depth'i task ağacı boyunca aktarır. `currentAgent`, `currentSubagentID`, `currentSubagentDepth`, `planModeAllowlist`, `subagentToolAllowlist` statik property'leri context-bound değişkenler. SubagentRuntime çalışırken kendi UUID'siyle sararak (`withValue`), nested tool çağrıları parent ID'sini biliyor.

**Çözdüğü problem:** Dual-agent paralel çalışırken her agent'ın sandbox'ı izole olmalı. Tool dispatch'in "hangi agent için" bilmesi gerek (approval reddedilirse doğru agent'a fark basılır). Subagent'lar ephemeral context taşır — nested dispatch'e karşı derinlik sınırı uygulanmalı.

**Alternatifler:** Global state dictionary → thread-unsafe; parameter chain → boilerplate; NotificationCenter → test izolasyonu zor. TaskLocal seçildi: concurrency-native, MainActor uyumlu, task cancel → context otomatik temizlenir.

**Neden iyi karar:**
- Test izolasyonu: testler kendi TaskLocal context'inde çalışır.
- Dual-agent safety: paralel stream'ler kendi agent ID'siyle istemeden diğerine yanlış olayları yayınlamaz.
- Nested dispatch yasağı enforced: depth ≥ 2 → exception.

**v3 önerisi:** **Koru.** TaskLocal pattern Swift Concurrency'nin merkezi. → **ADR-0003**

---

## Karar 2: Protocol-Driven Backend Abstraction — ChatBackend

**v2 referansı:** `Sources/PixelAgent/ChatBackend.swift:9-49`, ToolSchemas format renderers (anthropicFormat, openAIFormat, geminiFormat), ClaudeClient, GeminiChatClient, OpenAICompatClient

**Ne yapıyor:** `ChatBackend` protocol tek arayüz (stream, reset, setSystemPrompt, oneShot, oneShotMultimodal). Her provider (Claude, Gemini, OpenAI, Ollama, MiniMax, Codex CLI, Apple Intelligence) protokolü implemente eder. `ToolSchemas.allEnabled()` provider-agnostic tool kataloğu döner; her provider kendi format renderer'ıyla JSON Schema'yı API'sine çevirir.

**Çözdüğü problem:** LLM provider'ların tool API sözleşmeleri farklı (Anthropic Messages, OpenAI tool_calls, Gemini functionCall). ToolDispatcher tek dispatch path. Provider eklemek kolay olmalı.

**Alternatifler:** Monolithic switch → 500+ satır karmaşa; type erasure + reflection → performans cost; config-driven factory → MVP'de overkill.

**Neden iyi karar:**
- Open-closed: yeni provider için `ChatBackend` impl + format renderer yeter.
- Vision fallback: `oneShotMultimodal` default impl text-only `oneShot`'a düşer.
- Test mock: `MockChatBackend` tek satır.
- Backend swap: tek atama, akış kesintisiz.

**v3 önerisi:** **Koru + modülerleştir** (`PixelBackends/` klasör). MVP'de 1-2 provider. → **ADR-0004**

---

## Karar 3: Tool Arbiter — Resource Mutex + Path-Keyed File Lock

**v2 referansı:** `Sources/PixelAgent/ToolArbiter.swift`, `Sources/PixelAgent/ToolDispatcher.swift:77-103`

**Ne yapıyor:** Actor-based `ToolArbiter.shared` dual-agent paralel çalışırken fiziksel kaynakları serialize eder. `Resource` enum: `.input` (cursor+keyboard joint), `.clipboard`, `.mic`, `.speaker`, `.fileWrite(path)`. Tier D Faz 7: dosya yazımı path-keyed — iki agent aynı file'e paralel yazarsa kuyruğa düşer, farklı dosyalar paralel kalır. Global shell sentinel (`<shell>`) — komut metninden path çıkarılamayacağı için tüm shell çağrıları single-threaded. Re-entrant: aynı agent peş peşe `acquire` çağırırsa immediate geçer.

**Çözdüğü problem:** Dual-agent tek macOS ekrana erişir. Paralel iki agent cursor hareket ettirip tıklarsa denetim kaybolur. Clipboard race, file race önlenmelidir.

**Alternatifler:** Global lock → paralel tool yok; per-agent sandbox → macOS native değil; optimistic locking → conflict resolution model determinism'i bozar.

**Neden iyi karar:**
- Safety: deadlock-free (canonical order).
- Fairness: FIFO waiter queue.
- Observable: `onWaitStart` / `onWaitEnd` callbacks.
- Single-agent MVP'de acquire her zaman immediate; overhead sıfır.

**v3 önerisi:** **Koru.** Dual-agent MVP'de off olsa bile mimari hazır. → **ADR-0005**

---

## Karar 4: Ephemeral Conversation Store — Subagent In-Memory Log

**v2 referansı:** `Sources/PixelAgent/Subagent/EphemeralConversationStore.swift`, `SubagentRuntime.swift:30,66,197-199`

**Ne yapıyor:** Subagent'ın turn'leri `EphemeralConversationStore` (Main-Memory `[Entry]`) tutar — disk'e yazılmaz. Append-only, notification broadcast yok (MemoryIndexer tetiklenmez). Parent task sonu → subagent transcript'i bilinçli unutulur. Contrast: primary agent `ConversationStore` disk JSONL append-only.

**Çözdüğü problem:** Subagent 5-20 turn üretir, primary'nin tek tool çağrısına eşdeğer iş. Bu turn'leri disk'e yazarsa `memory.jsonl` şişer, vector index alaka düşer.

**Alternatifler:** Tag-filter ile disk'e yaz → tag mutation riski; in-memory + checkpoint → OOM riski.

**Neden iyi karar:**
- Clean data: disk'te high-value long-term bağlam kalır.
- Perf: MemoryIndexer increment yok.
- UX clarity: user turn log'unda subagent detay görmez.
- Failure semantics: subagent crash → result.error → parent dön, scaffold turn'leri unutuldu.

**v3 önerisi:** **Koru** (v0.2 subagent feature'ında). Audit gerekirse metadata-only disk entry. → ADR'a girmiyor (MVP'de subagent yok).

---

## Karar 5: TaskLocal Tool Allowlist — Plan Mode & Subagent Dispatch

**v2 referansı:** `Sources/PixelAgent/ToolSchemas.swift:31-41,46-64,71-94`, `AgentTools+Plan.swift:14-56`, `Subagent/SubagentRuntime.swift:142`

**Ne yapıyor:** İki `@TaskLocal` allowlist: `planModeAllowlist` (plan mode'da yalnız read-only tool'lar visible), `subagentToolAllowlist` (subagent context'inde belirli tool seti). `/plan` command'i `withValue(readOnlySet)` sarması → `allEnabled()` filtre uygular.

**Çözdüğü problem:** Plan mode'da `run_bash` çağrısı kilitlenmeli — model prompt'la söz versin diye değil, yapısal olarak. Subagent "unlimited tool" olmamalı.

**Alternatifler:** Static allowlist + dispatch runtime filter → code bloat; string-based blacklist → omission riski.

**Neden iyi karar:**
- Compile-time: TaskLocal scope dışına çıkamaz.
- Nested TaskLocal: intersection, stricter filter.
- Test coverage: `withValue` set, attempt → error, assertion pass.
- System prompt injection guard: model unlimited tool listesini hidden çağıramaz.

**v3 önerisi:** **Koru** (v0.2 Plan Mode + Subagent için). MVP'de yok. → ADR'a girmiyor.

---

## Karar 6: Append-Only JSONL Storage — Memory & Conversation

**v2 referansı:** `Sources/PixelAgent/ConversationStore.swift:35-90`, `MemoryStore.swift:1-150`, opsiyonel SessionStore FTS5 arşiv

**Ne yapıyor:** Disk dosya `~/Library/Application Support/PixelAgent2/conversation.jsonl` her turn'ü satır-wise JSON append eder. `memory.jsonl` entry'leri, `session.db` (SQLite FTS5) paralel arşiv. Bir satır bozuk → next satırlar okunur. `ConversationStore.append` notification post → MemoryIndexer incremental vectorize.

**Çözdüğü problem:** SQL daha güçlü query verir ama: migration version, concurrent write lock, encryption-at-rest zorluğu. JSONL + FTS5 hybrid: fast append (linear), rich search (FTS5), human-readable raw.

**Alternatifler:** UserDefaults (size limit), Core Data (relational overhead), DuckDB (cold start slower), plain text (parsing risk).

**Neden iyi karar:**
- Durability: append-only → crash → son satır eksik, prior turn'ler korunmuş.
- Incremental indexing: append notification → async vectorize.
- Version control: JSONL diffs readable.
- Privacy: raw JSON, encryption-at-rest kolay.
- Portability: drag-drop, iCloud Finder, Git backup.

**v3 önerisi:** **Koru + sadeleştir.** MVP'de sadece JSONL; FTS5 v0.3+'ta opsiyonel acceleration. → **ADR-0006**

---

## Karar 7: Remote Envelope — Tek Protocol Enum + Ed25519 Signing

**v2 referansı:** `Sources/PixelAgent/RemoteEnvelope.swift:3-27,104-179`, `RemoteLANServer.swift`, `RemoteCommandRouter.swift`

**Ne yapıyor:** `RemoteEnvelopeType` enum (28 case: ctrl.hello, live.audio, msg.user, ctrl.approval_request vb.) ve payload-agnostic JSON wrapper. Ed25519 HMAC (`sig` field) LAN pairing token ile optional.

**Çözdüğü problem:** Remote control untrusted network'te phishing vektörü. Payload type scattered JSON'da olsa boundary belirsiz.

**Alternatifler:** Protobuf/gRPC (binary, diff zor); HTTP REST (handshake overhead); custom binary (deserialization bugs).

**Neden iyi karar:**
- Single namespace: enum typo compile error.
- Versioning: `v: Int` field, backward compat.
- Signature optional: trusted peer skip overhead.
- JSON flexibility: type-driven parsing, future field elasticity.
- Debugging: `jq` ile raw LAN traffic okunur.

**v3 önerisi:** **Koru.** Hem Mac hem iOS aynı `PixelRemote` modülünden import etsin. → **ADR-0008**

---

## Karar 8: Element Grounding Cache — 3 dk TTL + BundleID::Query Key

**v2 referansı:** `Sources/PixelAgent/ElementGroundingCache.swift`, `UIAutomation.swift`

**Ne yapıyor:** OCR bulgusu `bundleID::normalized_query` key'le cache (in-memory, TTL=180s). Next 3 dakika içinde aynı app'teki aynı text'e tıklanırsa fresh OCR pass skip. TTL expired → entry drop. Low confidence (< 0.5) cache edilmez.

**Çözdüğü problem:** AX tree volatil. OCR/AX traversal 100-500ms → subagent çoklu dispatch'te birikir.

**Alternatifler:** Persistent cache (stale risk), no cache (yavaş), heuristic invalidate (false negative).

**Neden iyi karar:**
- Latency: cached hit < 1ms.
- Safety: TTL kısa, stale hit minimal.
- Confidence floor: low-confidence skip → model recover.
- Per-app isolation: bundleID key part.

**v3 önerisi:** **Koru** (v0.3+ computer-use tool'larıyla geldiğinde). MVP'de yok. → ADR'a girmiyor.

---

## Karar 9: Sprite/Mascot Architecture — Character Kit + PNG Fallback

**v2 referansı:** `CharacterKit.swift:19-164`, `Characters/PixelMascot48.swift`, `ProCharacterKits.swift`

**Ne yapıyor:** `CharacterKit` struct: sprite grid (48×48 px), frame set'leri, colors. String symbol mapping (X=body, H=highlight, S=shadow, O=eye) → NSImage render. V3 Stage 9.5: optional `pngFolderPath` PNG asset folder fallback.

**Çözdüğü problem:** String-grid 48×48 sade karakterler için yeterli; daha detaylı sanat için PNG asset pipeline gerek.

**Alternatifler:** Pure SVG (pixel art estetik yok), Lottie (ağır), Unity sprite export (binary LFS), emoji (Apple copyright).

**Neden iyi karar:**
- Fallback grace: pngFolderPath nil → string-grid play.
- Version control: string grid `git diff` readable.
- Personality: custom art portfolio çarpan.
- Fast iteration: string-grid test 1s.

**v3 önerisi:** **Koru.** MVP'de tek karakter string-grid. v3.1+ designer pipeline. → ADR'a girmiyor (Hafta 4 implementation note).

---

## Karar 10: Test Isolation — MockChatBackend + TaskLocal Context Scoping

**v2 referansı:** `Tests/PixelAgentTests/*.swift` (441 test), `MockChatBackend.swift`

**Ne yapıyor:** Test suite MockChatBackend (canned response) inject, real API bypass. TaskLocal context test'te explicit set: `withValue(...) { ... test body ... }`.

**Çözdüğü problem:** Real network test = flaky + slow. Global state'e dependency = test order coupling.

**Alternatifler:** Constructor DI (boilerplate), Environment key (type-unsafe), test mode flag (sprawl).

**Neden iyi karar:**
- Hermetic: no network, parallel safe.
- Determinism: fixed response.
- Coverage: integration testler bile mock + real dispatcher.
- Correctness: TaskLocal test isolation.

**v3 önerisi:** **Koru.** MVP test suite zaten 7 test (foundation seviyesinde). → **ADR-0007**

---

## Karar 11: AppDelegate Extension Modularization

**v2 referansı:** `AppDelegate.swift` (~120 satır çekirdek), `AppDelegate+*.swift` (11 extension): AutoResume, Backend, Drop, Lifecycle, Menu, RealtimeVoice, RemoteLAN, Slash, Telegram, Windows

**Ne yapıyor:** AppDelegate god class riski → her focus alanı ayrı extension. Her extension logical grup.

**Çözdüğü problem:** AppDelegate spaghetti. Ama gerçek bağımsızlık değil, sadece dosya bölmesi.

**Alternatifler:** VIPER/MVC (overkill), modular framework (CI slow), monolithic ViewController (pattern mismatch).

**Neden iyi karar (kısmen):**
- Navigable: extension'lar Xcode jump bar readable.
- Git blame: extension find responsibility.
- Deferral: feature group'ları v3.1+ için defer.

**v3 önerisi:** **Yapısal olarak değiştir** — AppDelegate yerine SwiftUI App lifecycle (ADR-0002) + modüler SPM (ADR-0001). Extension pattern modül seviyesine taşınır.

---

## Karar 12: Graceful Vision Fallback — Backend oneShotMultimodal + Embedding Chain

**v2 referansı:** `ChatBackend.swift:34-48` (protocol default impl), `PlaybookLearner.swift:32-40`, `EmbeddingProvider.swift`

**Ne yapıyor:** Backend'e image pass edilse provider vision desteğini yok sayarsa default impl text-only `oneShot()` fallback. PlaybookLearner embedding unavailable → empty string return. ToolCritic screenshot-required tool → vision-unavailable backend'de LLM check skip → proceed.

**Çözdüğü problem:** Provider vision capability bilinmez (runtime probe slow). Crash yerine graceful degrade.

**Alternatifler:** Strict mode (vision required, reject), runtime capability probe (startup slow), hardcoded capability table (maintenance burden).

**Neden iyi karar:**
- Resilience: vision unavailable → graceful.
- Platform flexibility: Apple Intelligence vision yok şu an, çalışır.
- Smooth UX: model "görsel alamadım, text tabanlı çöz".

**v3 önerisi:** **Koru** (`ChatBackend` protokol default impl olarak). → ADR-0004'ün bir bölümü.

---

## Karar 13: Plan Mode — TaskLocal Flag + System Prompt Injection

**v2 referansı:** `AgentTools+Plan.swift:14-122`, `ToolSchemas.swift:35-64`, `/plan` slash command

**Ne yapıyor:** `/plan <task>` TaskLocal `planModeAllowlist` set'ler. Model "Bunu yapma planı markdown'da steps çıkar" system prompt alır. Return → `ProposedStep[]` parse, PlanWindow ek accept/reject.

**Çözdüğü problem:** Model plan ekstra-step yazabilir (run_bash hidden) — system prompt güveni yetmez, yapısal gate gerek.

**Alternatifler:** Separate plan agent (backend duplik), prompt engineering (jailbreak cycle), arbiter-like gate (UX noisy).

**Neden iyi karar:**
- Lightweight: TaskLocal switch, backend instance reuse.
- Visible: PlanWindow user'a plan gösterir.
- Correctness: tool allowlist compile-time enum + runtime filter.

**v3 önerisi:** **Koru** (v0.2 Plan Mode feature'ında). MVP'de yok.

---

## Karar 14: Settings Segmentation — SettingsStore+*.swift Extensions

**v2 referansı:** `SettingsStore.swift`, `SettingsStore+Tools.swift`, `+UI.swift`, `+Autonomy.swift`, `+Budget.swift`, `+Models.swift`

**Ne yapıyor:** Monolithic UserDefaults store logical extension'larla bölünmüş. Her extension UserDefaults aynı singleton'a yazır.

**Çözdüğü problem:** Settings 200+ property — single file 1500 satır.

**Alternatifler:** Nested config (encoding versioning), JSON file (boilerplate), LaunchDarkly (overkill).

**Neden iyi karar:**
- Scalable: feature branch `+NewFeature.swift`, zero conflict.
- Type-safe: UserDefaults key collision risk yok.
- Test friendly: extension defaults, test override.

**v3 önerisi:** **Koru + modülerleştir.** MVP'de `SettingsStore.swift` + 2-3 extension. → ADR'a girmiyor (Hafta 4-5 implementation note).

---

## Anti-Pattern'ler — v3'te Tekrarlama

### Anti-Pattern 1: AppDelegate God Class (Monolithic)

v2'de belirli bir dönemde 10 extension olmadığında AppDelegate 3000+ satır monolith oldu. Sonradan extension'lara bölündü ama "tüm yollar AppDelegate'e çıkıyor" eğilimi yapısal olarak kaldı.

**v3 yapısal çözüm:** SwiftUI App lifecycle (ADR-0002), modüler SPM (ADR-0001). AppDelegate adapter sadece zaruri macOS hook'ları için, küçük tutulur.

### Anti-Pattern 2: Global Backend State (`static let shared`)

v1 dönem `shared` global ChatBackend singleton vardı → test swap imkânsız, race condition. v2 fix: `AppDelegate.backend` property, init inject. Ama AppDelegate hâlâ singleton-benzeri (NSApplication.shared.delegate).

**v3 yapısal çözüm:** DI over singletons (ADR-0009). Composition root `PixelMacApp` servisleri instantiate eder, child'a init/Environment ile geçirir. `ToolArbiter.shared` tek istisna (gerçek fiziksel kaynak mutex).

### Anti-Pattern 3: Disk-to-RAM-to-Vector Loop (Memory Leak)

Subagent turn'leri disk'e yazılıp MemoryIndexer immediately vector index'e yükledi → 1000 subagent call → memory.jsonl 100MB, RAM index 200MB.

**v3 yapısal çözüm:** Karar 4 (ephemeral conversation store). Subagent turn'leri RAM-only. Audit gerekirse metadata-only disk entry (summary), full transcript ephemeral.

---

## v3 ADR Eşleme Tablosu

| v2 Karar | v3 ADR | Durum |
|---|---|---|
| 1. TaskLocal scoping | ADR-0003 | ✓ MVP'de |
| 2. ChatBackend protocol | ADR-0004 | ✓ MVP'de |
| 3. ToolArbiter mutex | ADR-0005 | ✓ MVP'de |
| 4. Ephemeral subagent store | — | v0.2+ (subagent feature ile) |
| 5. TaskLocal tool allowlist | — | v0.2+ (plan mode + subagent ile) |
| 6. JSONL append-only | ADR-0006 | ✓ MVP'de |
| 7. Remote envelope | ADR-0008 | ✓ MVP'de (Hafta 5) |
| 8. Element grounding cache | — | v0.3+ (computer-use ile) |
| 9. Sprite/mascot kit | — | Hafta 4 implementation note |
| 10. Test isolation | ADR-0007 | ✓ MVP'de |
| 11. AppDelegate extensions | ADR-0002 (değiştirildi) | Yapısal pivot |
| 12. Vision fallback | ADR-0004 (parça) | ✓ MVP'de |
| 13. Plan Mode | — | v0.2+ |
| 14. Settings segmentation | — | Hafta 4-5 implementation note |

**Yeni v3 ADR'ları (v2'de yoktu):**
- ADR-0001: Modular SPM monorepo (v2'nin tek-target'lığına karşı)
- ADR-0002: SwiftUI App lifecycle (anti-pattern 1'i yapısal engelle)
- ADR-0009: DI over singletons (anti-pattern 2'yi yapısal engelle)
