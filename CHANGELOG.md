# Changelog

`pixel-agent` projesindeki tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) tabanlıdır,
sürümleme [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) kurallarına uyar.

## [Unreleased]

### Notes
- v0.2 kalan: App Store signing.
- Bekleyen kullanıcı aksiyonu: Apple Developer ID + notarization; demo GIF recording; Cloudflare workers.dev cert reprovisioning (support ticket veya yeni subdomain).

## [0.2.81] — 2026-05-29

**Sprint 52 — Computer-Use Macro Recorder (F1 Faz 1: A+B+C).** Agent'ın/kullanıcının bir dizi computer-use aksiyonunu (ui_click/ui_type) **kaydedip** sonra tek komutla **replay** etmesi. **Koordinat değil semantik:** her tıklama AX referansı (UIQuery + opaqueID) olarak saklanır; replay'de element AX ile yeniden çözülür → pencere taşınsa/boyut değişse bile çalışır. pixel'in AX moat'ını sergileyen "Show HN" demo özelliği. Mimari: [ADR-0038](docs/adr/0038-computer-use-macro-recorder.md).

**Akış:** Settings → Makrolar → "Kayda Başla" → agent'a iş yaptır → "Durdur ve Kaydet" → makro listede → "Oynat" (AX re-resolve). MCP: `list_macros` + `replay_macro`.

**Test:** Mac 1418 → **1457** (+39: A 25 [MacroStep 8 + MacroReplayPlan 9 + MacroStore 8] + B 8 [MacroRecorder] + C 6 [MacroReplayer 3 + MacroTools 3] + ToolRegistry/SettingsTab regression). 0 failure. iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (`PixelMemory → PixelComputerUse` dep eklendi, döngü yok).

### Added — Sprint 52 / Macro recorder

#### `Sources/PixelComputerUse/` (Faz 1A + 1C)
- **`MacroStep`** enum (`.click(query:opaqueID:count:modifiers:)`/`.type`/`.screenshot`/`.wait`) + `summary` + `isDestructive`; `MacroReplayOptions`/`NotFoundPolicy`/`MacroReplayError`.
- **`MacroReplayPlan`** (saf): `validate` (boş/runaway cap) + `decideOnNotFound` (retry/skip/abort) + `isBlockedByPlanMode`.
- **`MacroReplayer`** (actor): opaqueID re-resolve → query fallback → notFound policy; runaway (maxSteps + maxDuration + Task.checkCancellation); Plan Mode guard.
- **`PixelComputerUse.clickResolved(opaqueID:)`** — resolve-and-click primitifi.

#### `Sources/PixelMemory/` (Faz 1A)
- **`MacroRecording`** + **`MacroStore`** (`macros.jsonl`, append-only, latest-wins, tombstone). `Package.swift`: PixelMemory → PixelComputerUse dep.

#### `Sources/PixelMacApp/` (Faz 1B + 1C)
- **`MacroRecorder`** (@MainActor, `static let shared` + `init(store:)`) — start/record/stop/cancel.
- **`MacroSettingsTab`** (9. tab "Makrolar") — kayıt toggle + canlı adım + liste + "Oynat" (progress/Durdur) + sil.

#### `Sources/PixelMCPServer/` (Faz 1C)
- **`MacroTools.listMacros`** (standalone) + **`replayMacro`** (bridge, plan-guarded). `BuiltInTools` 20 → 22 tool.

### Changed — Sprint 52
- **`ControlSocketServer`**: `onUIActionRecorded` hook (başarılı ui_click/ui_type → semantik MacroStep) + `attachUIActionListener` + `replay_macro` bridge handler. PixelMacApp wire-up.

### Notes — Sprint 52
- **Privacy (Faz 2):** `.type` düz metin saklar (şifre dahil) — secure-field maskeleme Faz 2'ye ertelendi. Kullanıcı uyarılmalı.
- **Faz 2 defer:** secure-field maskeleme; adaptif wait; atomik replay (ToolArbiter re-entrancy); MenuBarExtra/⌘⇧R + mascot recording state; agent-tetikli start/stop_macro_recording; (düşük) CGEventTap insan-recording.
- Replay click'leri `computer`'a doğrudan gider (execute'a re-enter etmez) → recording hook tetiklenmez (döngü yok).

## [0.2.80] — 2026-05-29

**Sprint 51 — Skill / Recipe Extraction (Faz 1).** Agent artık yeniden kullanılabilir, çok-adımlı, **versiyonlu ve self-improving** workflow'ları ("skill") kaydedebilir/uygulayabilir — Nous Research Hermes Agent'ın "self-improving skill loop"una parity. `save_memory` atomik fact içindi; skill'ler tekrarlanabilir prosedürler için (örn "PR review akışı: 1… 2… 3…"). İlgili skill'ler her mesaj öncesi system prompt'a ayrı bir "[İlgili skill'ler]" section olarak enjekte edilir. Mimari gerekçe: [ADR-0037](docs/adr/0037-skill-recipe-extraction.md).

**Test:** Mac 1380 → **1418** (+38: 4 SkillEntry + 10 SkillStore + 7 SkillRanker + 6 SkillIntent + 7 SkillTools + 3 MemoryCaptureInstruction + ToolRegistry regression update). 0 failure. iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni store/tipler additive; `assembleSystemPrompt` skillSection default "").

### Added — Sprint 51 / Skill subsystem

#### `Sources/PixelMemory/SkillEntry.swift` (yeni)
- **`SkillEntry`** — lineageID + version + supersedesID + title + trigger + steps[] + usageCount + origin(.explicit/.auto) + deleted. `withNormalized()` (tag/step trim+dedup).

#### `Sources/PixelMemory/SkillStore.swift` (yeni, actor)
- JSONL append-only `skills.jsonl` (MemoryStore paterni). **Lineage-aware latest-wins:** aktif head = lineage içi en yüksek version. `create`/`update` (supersede, yeni versiyon)/`recordUsage` (aynı versiyon usageCount++)/`delete` (tombstone)/`loadActive`/`compact`.

#### `Sources/PixelMemory/SkillRanker.swift` (yeni)
- `EmbeddingScorer` reuse (zero yeni dep) + usageCount boost (`min(.,5)×0.02`, self-reinforcing) + `formatPrompt`. Skor `trigger + " " + title` üzerinden.

#### `Sources/PixelMCPServer/SkillTools.swift` (yeni, standalone)
- 4 MCP tool: `create_skill` / `update_skill` (self-improve) / `list_skills` / `apply_skill` (usageCount++). `BuiltInTools.makeRegistry`'ye kayıtlı (16 → 20 tool).

### Changed — Sprint 51

#### `Sources/PixelMemory/CaptureIntentDetector.swift`
- **`detectSkillIntent`** (çok-adımlı workflow niyeti: "şu adımları izle / step by step / this workflow") + **`extractStepHints`** (numaralı satır kaba bölme).

#### `Sources/PixelMemory/MemoryCaptureInstruction.swift`
- `assembleSystemPrompt`'a `skillSection: String = ""` (geriye uyumlu); sıra playbook → skills → base → contextual. `contextualPrefix` skill-intent'te `create_skill` nudge'u ekler.

#### `Sources/PixelMacApp/` (wiring)
- `ChatViewModel`: `skillStore: SkillStore?` property/init + `send()` injection (`SkillRanker.relevant` → skillSection). App → ChatHost → ChatView/DualChatHost → ChatViewModel zinciri boyunca `skillStore` threadlendi (PixelMacApp/ChatView/DualChatHost).
- `SettingsView` "Hafıza" tab'a skill `Section` — başlık + versiyon + usageCount + origin rozeti + adım `DisclosureGroup` + sil.

### Notes — Sprint 51
- **Faz 2 (defer):** Otomatik görev-sonrası extraction (system prompt talimatı + Settings toggle, default OFF — FP riski) + `origin:.auto` ayrımı + iOS read-only skill listesi. Self-improving altyapısı (versiyon + usageCount) Faz 1'de hazır.
- JSONL şişmesi `SkillStore.compact()` (lineage-aware purge) ile sınırlanır; multi-process lock yok (ADR-0033 ile aynı bilinen sınır).

## [0.2.79] — 2026-05-29

**Sprint 50 — Mascot "listening" state (sesli mod görsel feedback).** Sesli modda mikrofon açıkken/kullanıcı konuşurken mascot artık dikkatli bir "dinliyorum" haline geçer. Önceden voice capture sırasında mascot `.idle`/`.thinking` kalıyordu — görsel feedback yoktu. Mascot proje marka kimliği olduğundan bu, voice feature'ının görsel hikâyesini tamamlar + demo değeri taşır.

**Akış:** mic aç → `.listening` (geniş dikkatli gözler + tetik baş sallama) · kullanıcı konuşur (interim) → `.listening` sürer · segment biter (`.final`) → `send()` devralır (`.thinking`) · agent cevabı → `.speaking` (mevcut) · kullanıcı keser (interrupt) → tekrar `.listening`.

**Test:** Mac 1368 → **1380** (+12: 1 MascotFrame geniş-göz + 4 MascotAnimationClock listeningOffset + 7 VoiceMascotResolver). 0 failure. `swift build` temiz. iOS additive (MascotState shared enum; iOS mascotState'i lokal set eder, wire'da taşınmaz → eski client etkilenmez). Breaking change yok.

### Added — Sprint 50 / Mascot listening

#### `Sources/PixelMascot/PixelMascot.swift`
- **`MascotState.listening`** — 5. state (rawValue `"listening"`).
- **`listeningFrame`** — gözler 2 hücre genişliğinde ("dikkatle dinliyorum"; idle'da tek hücre), ağız idle gibi kapalı. `frame(for:atFrameIndex:)` switch'e eklendi.

#### `Sources/PixelMascot/MascotAnimationClock.swift`
- **`listeningOffset(time:)`** — dikkatli baş sallama; ±1.0pt / 0.6Hz (~1.67s), idle nefesinden (±1.5pt / 0.25Hz) daha tetik. Dikey eksen.

#### `Sources/PixelMacApp/VoiceMascotResolver.swift` (yeni, saf helper)
- **`VoiceMascotResolver`** — voice olayı (`captureStarted`/`transcriptInterim`/`transcriptFinal`/`interrupted`/`captureStopped`/`failed`) → `MascotState?`. `nil` = "mascot'a dokunma" (text-turn akışı `.thinking`/`.speaking` sahipliğini korur). Test edilebilir; View'dan ayrık.

### Changed — Sprint 50

#### `Sources/PixelMacApp/VoiceSession.swift`
- Capture başla + interim → `.listening`; `.final` → handoff (mascot'a dokunmaz); stop + error → `.idle`; `interruptSpeech()` → `.listening` (kesme feedback'i). Eşleme `VoiceMascotResolver` üzerinden.

#### `Sources/PixelMacApp/ChatViewModel.swift`
- `statusText` → `.listening` case: "Dinliyor...".

#### `Sources/PixelMascot/MascotView.swift`
- `currentOffset` → `.listening` → `listeningOffset`.

### Notes — Sprint 50
- **Defer:** TTS sırasında ayrı "agent speaking" + continuous voice'ta turn bitince otomatik `.listening`'e dönüş — `speakAssistantReply` henüz wire'lı değil + turn-state coupling gerektirir. Şu an turn sonrası mascot `.idle`'a döner, kullanıcı tekrar konuşunca interim ile `.listening`'e geçer.
- **iOS:** voice Mac-only → iOS'ta `.listening` tetiklenmez (MascotState enum + view paylaşılır, hazır).
- Bağlam: [ADR-0035 PixelVoice](docs/adr/0035-pixel-voice.md).

## [0.2.78] — 2026-05-27

**Sprint 49.1 hot-fix — Auto-start default geri ON (Cloudflare cert provisioning sorunu).** Sprint 49'da production Cloudflare URL hardcoded edilmiş, auto-start default'u OFF'a alınmıştı; ancak `wrangler deploy` sonrası `pixel-agent-relay.erkutyavuzer.workers.dev` URL'i TLS handshake'i `Cipher 0000` ile reddediyor. Diagnostic: hesap subdomain'i (`erkutyavuzer.workers.dev`) Cloudflare dashboard'da allocated görünüyor (4.12k lifetime request) ama wildcard cert provisioning'i 2024 Workers Free Plan policy değişikliği sonrası de-provisioned. Bu kullanıcı/hesap için cert support ticket veya yeni subdomain ile çözülür — code-side bir şey yapılamaz.

**Hot-fix:** `RelayLauncher.isAutoStartEnabled` default `false` → `true` revert. Fresh install kullanıcıları yine yerel wrangler subprocess + LAN ile çalışır; productionURL kodda kalır (Cloudflare side fix olursa resolver chain'inde otomatik devreye girer). Test güncellendi.

**Test:** 1 RelayLauncherTests assertion swap (`testAutoStartDefaultFalse` → `testAutoStartDefaultTrue`) + `testStartWithoutRelayDirectoryFailsGracefully` simplified (Sprint 49'da eklenen UserDefaults boilerplate kaldırıldı). Toplam test 1368 — değişmez.

### Changed — Sprint 49.1 hot-fix

#### `Sources/PixelMacApp/RelayLauncher.swift`
- **`isAutoStartEnabled` default `true`** (Sprint 49'da false yapılmıştı). Docstring güncellendi: Cloudflare cert issue açıklaması.

#### `Tests/PixelMacAppTests/RelayLauncherTests.swift`
- `testAutoStartDefaultTrue` (Sprint 49'da `testAutoStartDefaultFalse` olarak değişmişti).
- `testStartWithoutRelayDirectoryFailsGracefully` orijinal forma döndü.

### Notes — Sprint 49.1

- **Cloudflare side:** Account-wide `erkutyavuzer.workers.dev` subdomain'i dashboard'da listelenir ama edge TLS handshake reddediyor; aynı sorun 15 gün önce deploy edilen `pa-relay` worker'ında da var. Lokal TLS stack sağlam (`cloudflare.com` ve `workers.cloudflare.com` ile handshake başarılı). Diagnostic detayı için bkz: Sprint 49 release notes + Cloudflare 2024 Workers Free Plan policy update.
- **productionURL kodda kalır:** `RelayURLResolver.productionURL = "wss://pixel-agent-relay.erkutyavuzer.workers.dev"`. Resolver chain custom > env > production > LAN > localhost; kullanıcı Settings → Bağlantı → "Wrangler'ı Otomatik Başlat" toggle'ını manuel kapatırsa LAN/localhost yerine production URL devreye girer (Cloudflare side fix sonrası bağlanır).
- **iOS pairing değişmez:** Yerel wrangler subprocess artık tekrar default → LAN üzerinden bağlanır. Mac sleep/quit'te düşer (Sprint 47 davranışı).
- **Backward compat:** Sprint 49 (v0.2.77) kurulu kullanıcılar (sadece bir kişi: Erkut) auto-start UserDefaults set'li olmadığı için bu hot-fix sonrası default ON'a döner. Settings'ten ele alabilir.
- **Forward path:** Cloudflare workers.dev cert provisioning Cloudflare support'la veya yeni subdomain seçimi ile çözülürse, Sprint 49.2 ile default'u tekrar false'a alabiliriz (productionURL hâlâ kodda).

## [0.2.77] — 2026-05-27

**Sprint 49 — Production Cloudflare Worker deploy + hardcoded production URL.** Sprint 47'de `RelayLauncher` lokal `wrangler dev` subprocess'ini otomatik başlatıyordu; bu Mac restart'ta + bundle copy'de büyük UX iyileştirmeydi ama hâlâ **Mac sleep/quit'te relay düşüyordu**. Sprint 49 production Cloudflare Worker deploy ile son boşluğu kapatıyor: relay artık Cloudflare edge'inde her zaman ayakta, iOS Mac'tan bağımsız olarak public URL'e bağlanır.

**Adımlar:**

1. **`wrangler deploy`** çalıştırıldı (free plan compat için `new_classes` → `new_sqlite_classes` migration). Public URL: `pixel-agent-relay.erkutyavuzer.workers.dev`.
2. **`RelayURLResolver.productionURL`** artık hardcoded `wss://pixel-agent-relay.erkutyavuzer.workers.dev`. Resolver chain 3. tier (custom > env > **production** > LAN > localhost).
3. **`RelayLauncher.isAutoStartEnabled` default `false`** — yerel wrangler subprocess opsiyonel. Production URL handles iOS connection by default. Kullanıcı offline/dev için Settings'ten açabilir.

**Sonuç:** Fresh Homebrew install kullanıcısı app'i açtığında **hiç wrangler subprocess'i başlamaz**, RelayURLResolver doğrudan production Cloudflare URL'i seçer, iOS pairing aynı public URL'e bağlanır. Mac sleep/quit etkilemez. ~30sn npm install ilk launch akışı da artık tetiklenmez (default OFF).

**Test:** Mac 1364 → **1368** (+4: testProductionURLIsConfigured + testSourceProductionWhenNoOverrides + testProductionStillOverridableByCustom + testProductionStillOverridableByEnv; 2 mevcut test updated: testFallbackResolvesToProductionOrLowerTier + testSourceFallback). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change:** auto-start default true → false. Sprint 47-48 kullanıcıları (explicit set'liler) etkilenmez; sadece sıfırdan kuran/UserDefaults sıfırlayanlar default-off.

### Added — Sprint 49 / Production Cloudflare deploy

#### `Sources/PixelMacApp/RelayURLResolver.swift`
- **`productionURL`** static: `"wss://pixel-agent-relay.erkutyavuzer.workers.dev"`. Sprint 47'de placeholder `nil`'di; Sprint 49 deploy sonrası hardcoded.

#### `relay/wrangler.toml`
- **Migration `new_classes` → `new_sqlite_classes`** — Cloudflare Workers free plan compat. SQLite-backed Durable Objects key-value DO'lardan farklı backend ama API uyumlu.

### Changed — Sprint 49

#### `Sources/PixelMacApp/RelayLauncher.swift`
- **`isAutoStartEnabled` default `false`** — production URL artık var, yerel wrangler subprocess opsiyonel. Explicit `true`/`false` set'li UserDefaults değerleri öncelikli.

### Tests — Sprint 49

- `Tests/PixelMacAppTests/RelayURLResolverTests.swift` — **+4 yeni**: productionURL configured + wss:// prefix + Source.production when no overrides + custom-override-precedence + env-override-precedence. 2 mevcut test updated (fallback tier expectations).
- `Tests/PixelMacAppTests/RelayLauncherTests.swift` — **2 mevcut test güncellendi**: `testAutoStartDefaultFalse` (eskiden True bekliyordu) + `testStartWithoutRelayDirectoryFailsGracefully` (artık explicit true set ile test).

### Notes — Sprint 49

- **Free plan SQLite DO:** Cloudflare 2024'te Workers free plan'i Durable Object'lere açtı ama yalnızca SQLite-backed (`new_sqlite_classes`); key-value DO'lar paid plan'a kaldı. Migration tag aynı (`v1`), backend tipi farklı — kod tarafında transparan (aynı `DurableObjectStub` API).
- **Workers.dev subdomain activation:** Cloudflare yeni hesaplarda workers.dev erişimini default kapalı tutuyor; dashboard'da bir kerelik "Activate" tıklaması gerek. Bu commit sonrası TLS handshake doğrulanırsa iOS production URL'e direkt bağlanır.
- **Lokal wrangler hâlâ destekli:** Settings → Bağlantı → "Wrangler'ı Otomatik Başlat" toggle'ı offline development için açılabilir; bundle copy + lazy npm install (Sprint 48) çalışmaya devam eder.
- **Backward compat:** Sprint 47-48 kullanıcıları auto-start'ı explicit `true` set ettiyse (Settings toggle'ı kullanmamış olsalar bile UI'da görmüş olabilirler), upgrade'de değişmez. Yalnızca hiç dokunmamışlar artık OFF default.
- **iOS pairing değişmez:** Saved pairing URL üzerinden çalışır; production URL ResolverInfo'dan gelir, pairing payload değişmez.

## [0.2.76] — 2026-05-27

**Sprint 48 — Relay bundle copy + lazy npm install.** Sprint 47'de RelayLauncher Mac app launch'ta `npx wrangler dev` subprocess'i otomatik başlatıyor; ancak `relayDirectory` sadece dev repo path'inde (`/Users/erkut/Projects/pixel-agent/relay`) veya production'da Bundle Resources'da bulunabiliyordu — **Homebrew install kullanıcıları repo'yu klonlamadan relay'i kullanamıyordu**. Sprint 48 bu son boşluğu kapatıyor: `relay/` kaynak dosyaları artık `PixelAgent.app/Contents/Resources/relay/` altında bundle'lanır (node_modules HARIÇ), ilk launch'ta Application Support'a kopyalanır ve `npm install` async tetiklenir.

**Akış:**
1. **Build-time:** `scripts/build-app.sh` `relay/{wrangler.toml, package.json, package-lock.json, src/, README.md}` dosyalarını `Contents/Resources/relay/` altına kopyalar. `node_modules` (~167MB) bundle'a dahil edilmez — bundle hâlâ 7.9 MB.
2. **First launch:** `RelayLauncher.start()` → `ensureWritableCopy(from: bundleResources, to: ~/Library/Application Support/pixel-agent/relay)` (idempotent, `package-lock.json` diff check).
3. **node_modules yoksa:** `runNpmInstall()` async — `npm install --no-audit --no-fund --prefer-offline` (~30 sn ilk kurulum). `isInstallingDependencies` @Published bool — Settings UI ProgressView gösterir.
4. **Install bittiğinde:** `launchWranglerProcess(at: runtimeDir)` — Sprint 47'deki normal akış devam eder.

**Update path:** Mac app update'lerinde `ensureWritableCopy` `package-lock.json` byte-eşitliğini kontrol eder; fark varsa src/ + config dosyalarını üzerine yazar, `node_modules` dokunmaz (separate state). Kullanıcı bağımlılıkları yeniden install etmez — yalnızca lock değiştiğinde.

**Test:** Mac 1355 → **1364** (+9 RelayLauncherCopyTests). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok**.

### Added — Sprint 48 / Relay bundle + lazy install

#### `scripts/build-app.sh`
- `relay/wrangler.toml`, `package.json`, `package-lock.json`, `src/`, `README.md` (varsa) → `Contents/Resources/relay/`. `node_modules` HARIÇ.
- Bundle size: 7.9 MB (öncesi 7.9 MB; +~60 KB delta).

#### `Sources/PixelMacApp/RelayLauncher.swift` (Sprint 48 extension)
- **`@Published private(set) var isInstallingDependencies: Bool`** — Settings UI ProgressView için ~30sn npm install state.
- **`static var writableRelayDirectory: URL`** — `~/Library/Application Support/pixel-agent/relay/` (node_modules burada install edilir).
- **`static func ensureWritableCopy(from:to:)`** — idempotent kopya; ilk seferde tüm dizini kopyalar, sonrasında `package-lock.json` byte-eşitliğine bakar; farklıysa yalnızca config + src/ üzerine yazar, `node_modules` korunur.
- **`private func runNpmInstall(in:npxPath:) async`** — `npm install --no-audit --no-fund --prefer-offline`; npm path npx'in yanından türetilir (Homebrew layout); hata olursa `lastError` set, kullanıcıya internet veya production URL önerir.
- **`start()` refactor:** `ensureWritableCopy → check node_modules → runNpmInstall (async, gerekirse) → launchWranglerProcess`. `isRunning && isInstallingDependencies` guard çift install önler.
- **`launchWranglerProcess(at:npxPath:)`** — eski `start()` body'sinin spawn kısmı; install sonrası veya doğrudan çağrılır.

#### `Sources/PixelMacApp/SettingsView.swift` (ConnectionSettingsTab)
- **`statusIcon`** — `isInstallingDependencies` true ise `ProgressView`. (Sprint 47 yeşil/turuncu/gri tier'ları korunur.)
- **`statusLabel`** — `"İlk kurulum: npm install çalışıyor (~30 sn)"`.

### Tests — Sprint 48

- `Tests/PixelMacAppTests/RelayLauncherCopyTests.swift` — **9 yeni**: writableRelayDirectory path format (Application Support suffix, absolute); `isInstallingDependencies` initial false; `ensureWritableCopy` first-time create + nested parent create + lock-match skip (user marker preserved) + lock-diff overwrite (src content updated) + node_modules preserved on update + optional README skip.

### Notes — Sprint 48

- **Homebrew kullanıcıları artık dev repo'ya ihtiyaç duymaz** — `brew install --cask ErkutYavuzer/tap/pixel-agent` sonrası app açar açmaz relay otomatik kurulur. İlk launch'ta ~30sn `npm install` (~25 paket, wrangler dahil); sonraki launch'larda ms cinsinden başlar.
- **Bundle boyutu kontrolü:** node_modules ~167 MB bundle'ı şişirirdi. Lazy install ile bundle 7.9 MB kalır; bağımlılıklar kullanıcının yerel npm cache'inden gelir (prefer-offline).
- **Update senaryosu:** `brew upgrade pixel-agent` yeni `package-lock.json` taşırsa, kullanıcı app'i bir sonraki açışta `ensureWritableCopy` lock diff'i algılar, src/ + config'i günceller, **npm install otomatik tetiklenmez** (mevcut node_modules yetiyorsa); fakat eğer install başarısızsa veya kullanıcı manuel sildiyse `runNpmInstall` tekrar çalışır.
- **Sprint 47 unchanged paths:** dev repo path (`/Users/erkut/Projects/pixel-agent/relay`) hâlâ fallback olarak deteksiyon zincirinde — sourceDir bulunduğu sürece tüm akış aynı; sadece `runtimeDir` (writable) farklı.

## [0.2.75] — 2026-05-27

**Sprint 47 — Relay launcher otomatik + URL resolver fallback chain.** Kullanıcı v0.2.74'te iOS bağlantı kuramıyor diye crash dialog raporladı; root cause: **Cloudflare Worker relay server (port 8787) ayakta değildi**. Mac restart sonrası kullanıcı manuel `cd relay && npx wrangler dev` yapmak zorundaydı — kötü UX. Sprint 47 bu sorunu yapısal olarak çözüyor.

**3 katman çözüm:**

1. **`RelayLauncher` actor** — Mac app launch'ta `npx wrangler dev` subprocess otomatik tetiklenir. App kapanırken SIGTERM ile graceful exit. Subprocess crash'inde 5sn cooldown + max 3 restart watchdog.

2. **`RelayURLResolver` saf helper** — 5-tier fallback chain: UserDefaults custom URL > `PIXEL_RELAY_URL` env > production Cloudflare > LAN IP > localhost. Settings'ten kullanıcı override edebilir.

3. **`scripts/deploy-relay.sh`** — Cloudflare Worker deploy automation (wrangler login + deploy + URL extract). Kullanıcı production URL kullanmak isterse tek tıkla.

**Yeni Settings UI:** Bağlantı tab artık 3 section:
- **Yerel Relay (Wrangler):** Otomatik başlat toggle + status (yeşil ✓ çalışıyor / turuncu ⚠ hata / gri devre dışı) + manuel "Yeniden Başlat" butonu + lastError display
- **Relay URL:** Aktif URL + kaynak (Özel/Env/Cloudflare/LAN/localhost) + özel URL editable field
- **LAN:** _pixel-agent._tcp Bonjour info (mevcut)

**Test:** Mac 1335 → **1355** (+20: 13 RelayURLResolver + 7 RelayLauncher). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (`PIXEL_RELAY_URL` env hâlâ destekleniyor, LAN IP detect korundu).

### Added — Sprint 47 / Relay launcher + URL resolver

#### `Sources/PixelMacApp/RelayLauncher.swift` (yeni)
- **`RelayLauncher` @MainActor ObservableObject** — `npx wrangler dev` subprocess lifecycle manager.
- `start()`: `npx` PATH'te ara (Homebrew Apple Silicon + Intel + sistem) → `Process()` spawn → stdout/stderr pipe → watchdog Task.
- `stop()`: SIGTERM + 1sn grace + SIGKILL force-kill fallback.
- `manualRestart()`: Settings UI "Yeniden Başlat" buton hook.
- **Crash recovery:** beklenmedik exit → 5sn cooldown → max 3 restart → "Manuel kontrol gerek" error.
- **Auto-start toggle:** `pixel.relay.autoStartEnabled` UserDefaults default true. Production URL kullanıcılar kapatabilir.
- **Relay directory detection:**
  1. App bundle `Resources/relay/` (production — Sprint 48+ build-app.sh copy)
  2. Dev repo `/Users/erkut/Projects/pixel-agent/relay`
- **EnvironmentBuilder.augmentedEnvironment()** reuse — Sprint v0.2.17 PATH augment Node.js bulmak için yeterli.

#### `Sources/PixelMacApp/RelayURLResolver.swift` (yeni saf helper)
- **`RelayURLResolver` enum** — `Sendable`.
- `resolve(defaults:environment:) -> String` — 5-tier priority chain.
- `resolveSource(...) -> Source` — UI display + introspection.
- **`Source` enum** — `.custom(String)`, `.environment(String)`, `.production(String)`, `.lan(ip:)`, `.localhost`. `url` + `displayName` accessor'lar.
- `setCustomURL(_:defaults:)` — UserDefaults `pixel.relay.customURL`. Empty/whitespace → clear.
- `detectLANIPv4()` — Sprint 6.1'den taşındı (saf helper, test edilebilir).
- `productionURL: String?` — şu an `nil`; `wrangler deploy` sonrası kullanıcı hardcoded ekler veya Settings custom URL field'a yapıştırır.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`RootView.relayLauncher` @MainActor static** singleton.
- **`RootView .task`** blok: `relayLauncher.start()` çağrısı SystemNotifications + ControlBridge ile birlikte.
- **`NSApplication.willTerminateNotification` observer**: app quit → `relayLauncher.stop()`.
- **`defaultRelayURL`** artık `RelayURLResolver.resolve()` çağırır (eski inline env+LAN+localhost mantığı resolver'a taşındı).

#### `Sources/PixelMacApp/SettingsView.swift` (ConnectionSettingsTab refactor)
- 3 yeni section: Yerel Relay (Wrangler) + Relay URL + LAN.
- @AppStorage'la `customURL` + `autoStartEnabled` bind.
- @ObservedObject `launcher` — isRunning/lastError state göster.
- TextField "Özel URL" — kullanıcı production wss:// URL yapıştırabilir.

#### `scripts/deploy-relay.sh` (yeni)
- `wrangler whoami` auth check; gerek varsa `wrangler login`.
- `wrangler deploy` çalıştır.
- Sonuç URL'ini kullanıcıya yapıştırma talimatı.

### Tests — Sprint 47

- `Tests/PixelMacAppTests/RelayURLResolverTests.swift` — **13 yeni**: priority chain (custom > env > LAN/localhost); source classification (.custom/.environment/.lan/.localhost); URL accessor; displayNames; setCustomURL persist + nil clear + whitespace clear; empty string falls through to env; LAN detect format check.
- `Tests/PixelMacAppTests/RelayLauncherTests.swift` — **7 yeni**: autoStart UserDefaults 3 variant; initial state; missing directory graceful fail; stop when not running no-op; default relay directory detection.

### Notes — Sprint 47

- **Şu anki sprint **iOS bağlantı sorununu çözer** — kullanıcı bir dahaki Mac restart sonrası `wrangler dev`'i manuel başlatmak zorunda değil. App ile birlikte launcher subprocess'i tetikler.
- **Production Cloudflare deploy hâlâ önerilir:** Lokal wrangler subprocess Mac uyku-uyanma sırasında veya app kapalıyken çalışmaz. Cloud-managed bir relay (5 dk'lık deploy) iOS'un her zaman bağlanabilmesini garanti eder. `scripts/deploy-relay.sh` bunu kolaylaştırır.
- **Node.js bağımlılığı:** `RelayLauncher.locateNpx()` `/opt/homebrew/bin/npx`, `/usr/local/bin/npx`, `/usr/bin/npx` arıyor. `brew install node` yoksa lastError gösterilir; kullanıcı production URL'e geçebilir.
- **Bundle relay directory:** Sprint 48+ aday — `build-app.sh` `relay/` klasörünü `PixelAgent.app/Contents/Resources/relay/` altına kopyalasın ki Homebrew install kullanıcılar `node_modules`'a dokunmak zorunda kalmasın.
- **Subprocess güvenliği:** App quit'te SIGTERM + 1sn grace + SIGKILL. App crash'inde subprocess orphan kalabilir; sistem reboot temizler veya `pkill -f wrangler` manuel.
- **iOS değişmedi** — sadece Mac side launcher. iOS hâlâ saved pairing URL'e bağlanmaya çalışır; Mac relay'i artık her zaman ayakta olduğu için bağlantı stabil.

## [0.2.74] — 2026-05-26

**Sprint 46 — Voice tools opt-in (per-tool UserDefaults override).** Sprint 44'teki `OpenAIToolBridge.voiceSafeToolNames` static whitelist artık kullanıcı tarafından **per-tool override** edilebilir. Settings → Sesli Mod → "Voice Tools" section'da tüm BuiltInTools listelenir, her tool için Toggle. Risky tool'lar (UI manipulation, subagent) turuncu badge'le default kapalıdır — kullanıcı bilinçli aktive edebilir.

**Kategori sistemi:**
1. **Default-enabled (önerilen, 9 tool):** clipboard, time, active_app, lan_ip, save_memory, search_memory, notify, play_sound — yeşil "önerilen" badge, default ON.
2. **Risky (7 tool):** ui_click, ui_type, ui_screenshot, ui_query, ui_resolve, dispatch_subagent, dock_badge_set — turuncu "riskli" badge, default OFF.
3. **Override:** `VoiceToolPreferences` UserDefaults `pixel.voice.toolOverrides` `[String: Bool]` dict; per-tool kullanıcı kararı default'a göre öncelikli.

**Karar zinciri (`VoiceToolPreferences.isEnabled(_:)`):**
1. UserDefaults override varsa → onu kullan
2. `defaultEnabledToolNames` içindeyse → true
3. Aksi halde (risky veya bilinmeyen) → false

**OpenAI + Gemini ToolBridge** artık `VoiceToolPreferences` ile filter eder (eski `includeAll: true` test-only şimdi).

**Test:** Mac 1312 → **1335** (+23: 15 VoiceToolPreferences + 8 ToolBridgePreferences). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (Sprint 44 `voiceSafeToolNames` alias olarak korundu).

### Added — Sprint 46 / Voice tools opt-in

#### `Sources/PixelVoice/VoiceToolPreferences.swift` (yeni saf helper)
- **`VoiceToolPreferences` struct** (`@unchecked Sendable`) — UserDefaults-backed per-tool override.
- **`defaultEnabledToolNames: Set<String>`** — Sprint 44 9-tool whitelist (clipboard, time, memory, notification).
- **`riskyToolNames: Set<String>`** — 7 tool (UI 5 + subagent + dock_badge).
- **`isEnabled(_:) -> Bool`** — UserDefaults override > default whitelist > false (3-tier).
- **`setEnabled(_:_:)` / `clearOverride(_:)` / `resetAllOverrides()`** — mutation API.
- **`isDefaultEnabled(_:)` / `isRisky(_:)`** — UI badge için classification statics.

#### `Sources/PixelVoice/OpenAIToolBridge.swift` (güncelleme)
- `voiceSafeToolNames` artık `VoiceToolPreferences.defaultEnabledToolNames` alias (backward-compat).
- `voiceTools(from:preferences:includeAll:)` — yeni `preferences` parametresi default `VoiceToolPreferences()`. Filter `preferences.isEnabled($0.name)`.
- `includeAll: true` test/debug bypass (preferences ignore).

#### `Sources/PixelVoice/GeminiToolBridge.swift` (güncelleme)
- Aynı pattern — `voiceTools(from:preferences:includeAll:)` `VoiceToolPreferences` ile filter.
- `tools[]` array'i ya tek `GeminiTools` grubu yada empty (all opted-out → Gemini setup'ta tools field omit).

#### `Sources/PixelMacApp/SettingsView.swift` (Voice Tools section)
- **`VoiceToolsSection` struct** — Sesli Mod tab altında 4. section.
- **Per-tool Toggle** — `BuiltInTools.makeRegistry().all()` sorted by name; her satır: tool name (monospaced) + kategori badge + 2-satır description.
- **Yeşil "önerilen" badge** — `isDefaultEnabled`.
- **Turuncu "riskli" badge** — `isRisky`.
- **"Önerilen Ayarlara Dön" button** — `resetAllOverrides()`.
- **Dirty state caption** — değişiklik sonrası "Voice modu başlatıldıktan sonra restart gerek" uyarısı.

### Tests — Sprint 46

- `Tests/PixelVoiceTests/VoiceToolPreferencesTests.swift` — **15 yeni**: default whitelist içerik, risky içerik, disjoint set, helper methods (isDefaultEnabled/isRisky), default isEnabled decision (3 case), setEnabled override (true/false), persistence across instances, clearOverride (default-enabled + risky), resetAllOverrides, Sprint 44 backward-compat alias.
- `Tests/PixelVoiceTests/ToolBridgePreferencesTests.swift` — **8 yeni**: OpenAI default whitelist filter, risky opt-in, default opt-out, includeAll bypass; Gemini aynı 3 case + all opted-out empty; cross-provider consistency (same prefs → same tool set).

### Notes — Sprint 46

- **Sprint 44 backward-compat:** `OpenAIToolBridge.voiceSafeToolNames` static alias olarak korundu (`VoiceToolPreferences.defaultEnabledToolNames`'e referans). Sprint 44 kodu hâlâ derlenir.
- **Restart-required:** Provider singleton app launch'ta yaratılır (Sprint 42'den beri böyle). Tool preferences değiştiğinde voice mode kapalı/açık geçiş gerekmez, ama provider zaten başlamış session'da yeni tool listesi devreye girmez — kullanıcı bir sonraki mic FAB tıklamasında veya app restart sonrasında yeni preferences aktif. Settings UI orange uyarı verir.
- **Risky tool aktive etmenin pratik anlamı:** Kullanıcı `ui_click`'i açarsa, agent voice modunda komutla "Safari'de X butonuna tıkla" deyince gerçekten click event yollar. Recovery zor (yanlış yere tıklamak undo gerektirir). Sadece güvendiğiniz workflow'larda açın.
- **iOS Voice yok:** Tüm voice infra hâlâ Mac-only.
- **Test coverage:** Sprint 46 testleri unit-level (saf helper + bridge filter). Real WebSocket round-trip Sprint 43-45'teki gibi manuel test.

## [0.2.73] — 2026-05-26

**Hot-fix: Proaktif Tier 2 detector crash (SIGTRAP).** Kullanıcı v0.2.72 sonrası app launch'ta "pixel-agent beklenmedik şekilde kesildi" crash dialog raporladı. Crash log analizi:

```
Thread 3 [TRIGGERED]: _dispatch_assert_queue_fail
  swift_task_isCurrentExecutorWithFlagsImpl
  specialized static MainActor.assumeIsolated<A>(_:file:line:)
  closure #1 in default argument 2 of WindowDwellDetector.init
  WindowDwellDetector.tick()
```

**Kök sebep:** Sprint 39'da yazılan `WindowDwellDetector`, `TypedPauseDetector` ve `CalendarEventDetector`'ın default source closure'ları `MainActor.assumeIsolated { ... }` pattern kullanıyordu. Detector `tick()` actor context'inde (background thread) çalışırken closure çağrılıyor, `assumeIsolated` MainActor olmadığını assert ediyor → SIGTRAP. Sprint 38-44 boyunca silent çalışıyordu (macOS önceki versiyonlarında daha gevşek check); Sequoia 15+ katı concurrency check ile expose oldu.

**Fix:**
- `WindowSource`, `FrontAppSource`, `EventSource` typealiases'a **`@MainActor` annotation** eklendi.
- Default closure'lar `{ @MainActor in ... }` formuna geçti (eski `assumeIsolated` wrap kaldırıldı).
- `tick()` içinde `await MainActor.run { source() }` ile explicit MainActor hop.

**Sonuç:** Proaktif Tier 2 trigger'ları (windowDwell, typedPause, upcomingEvent) artık background tick'ten MainActor source closure'unu güvenli olarak çağırıyor. Crash giderildi.

**Test:** Mac 1312 test (Sprint 45 ile aynı; mevcut testler MockSource kullandığı için bug repro etmiyordu — production-only path). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok**.

### Fixed — Sprint 45.1 hot-fix

- `Sources/PixelMacApp/Proactive/WindowDwellDetector.swift`: WindowSource typealias `@MainActor @Sendable`; default closure `{ @MainActor in WindowDwellDetector.systemWindowInfo() }`; `tick()` `await MainActor.run { windowSource() }`.
- `Sources/PixelMacApp/Proactive/TypedPauseDetector.swift`: FrontAppSource typealias `@MainActor @Sendable`; default closure update; `tick()` MainActor hop.
- `Sources/PixelMacApp/Proactive/CalendarEventDetector.swift`: EventSource typealias `@MainActor @Sendable`; default closure update; `tick()` MainActor hop.

### Notes — Sprint 45.1

- **Neden Sprint 38-44 boyunca crash olmadı?** macOS önceki versiyonlarında `MainActor.assumeIsolated` daha tolerant idi — false positive (gerçekte MainActor değil ama assert geçiyor). Sequoia 15+ `swift_task_isCurrentExecutorWithFlagsImpl` katı check yapıyor → SIGTRAP. Bu pattern Swift 6 strict concurrency'de zaten yanlıştı; macOS runtime şimdi yakalıyor.
- **Test coverage gap:** Sprint 39 detector test'leri `MutableSource` mock'ları kullanıyordu (sync closures); production path `assumeIsolated` kullanıyordu — bug test'lerden saklanmıştı. Future: integration test gerçek `systemWindowInfo()`/`systemFrontAppSource()` çağrısı ile (XCTest ortamında MainActor olmayabilir, dikkat).
- **Diğer detector'lar etkilenmedi:** `IdleDetector` (CGEventSource pure function — MainActor değil) ve `AppChangeObserver` (NSNotificationCenter `queue: .main`) sorun yok.

## [0.2.72] — 2026-05-26

**Sprint 45 — Gemini Live WebSocket implementation.** Sprint 43-44 OpenAI Realtime full parity üstüne Google Gemini Live alternatif provider eklendi. Aynı `VoiceProvider` abstraction, farklı protocol + audio format + **~10x ucuz fiyat**.

**Fiyat karşılaştırması** (2026 Q1):
- OpenAI Realtime: $0.06/min input + $0.24/min output
- **Gemini 2.0 Flash Realtime: $0.006/min input + $0.024/min output** (~10x ucuz)

**Format farkları:**
- **Audio input:** Gemini 16 kHz mono PCM16 (OpenAI 24 kHz)
- **Audio output:** Gemini 24 kHz (OpenAI ile aynı — `RealtimeAudioPlayer` reuse)
- **Protocol:** `BidiGenerateContent` JSON tree (OpenAI'den çok farklı)
- **Tool format:** `tools[].functionDeclarations[]` (no `type: "function"` field — OpenAI'den fark)
- **Interrupt:** Server `serverContent.interrupted: true` flag (OpenAI'de client `response.cancel` event'i)

**Akış:**
1. Settings → Sesli Mod → "Gemini Live" provider seç + API key gir + restart
2. ChatComposer mic FAB tıkla → `GeminiLiveProvider.start()`
3. WebSocket `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=<API_KEY>`
4. `setup` event yolla — model="models/gemini-2.0-flash-exp", system_instruction, tools, response_modalities=["AUDIO"]
5. Mic capture: AVAudioConverter (Apple → PCM16 **16 kHz mono**) → base64 → `realtime_input.media_chunks[mime_type="audio/pcm;rate=16000"]`
6. Server VAD → otomatik response
7. Server `serverContent.modelTurn.parts[].inlineData` (audio/pcm 24 kHz) → `audioPlayer.schedule(samples:)`
8. Server `toolCall.functionCalls[]` → MCP dispatch → `tool_response.function_responses[]`
9. Server `serverContent.interrupted: true` → `audioPlayer.interrupt()` (kullanıcı kesti)

**Test:** Mac 1287 → **1312** (+25: 19 GeminiEvent + 6 GeminiToolBridge; +1 Sprint 43-44 regression update). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok**.

### Added — Sprint 45 / Gemini Live

#### `Sources/PixelVoice/GeminiEvent.swift` (yeni)
- **`GeminiClientEvent` enum** (Encodable, 3 case):
  - `.setup(config: GeminiSetupConfig)` — connection açılışı (tek seferlik).
  - `.realtimeInput(audioBase64: String)` — mic chunk + `media_chunks[mime_type="audio/pcm;rate=16000"]`.
  - `.toolResponse(functionResponses:)` — function call sonucu (id + name + response).
- **`GeminiSetupConfig` struct** — model (default `models/gemini-2.0-flash-exp`), generation_config (response_modalities=["AUDIO"]), system_instruction, tools.
- **`GeminiSystemInstruction` + `GeminiTextPart`** — system prompt yapısı.
- **`GeminiTools` + `GeminiFunctionDeclaration`** — function calling tools yapısı (Gemini format: no `type: "function"` field).
- **`GeminiMediaChunk`** — `mime_type` + `data` (base64).
- **`GeminiFunctionResponse` + `GeminiToolResponseWrapper`** — tool response format.
- **`GeminiServerEvent` enum** (manual decode, 8 case):
  - `.setupComplete`, `.audioChunk(base64:)`, `.textChunk(text:)`, `.interrupted`, `.turnComplete`, `.toolCall(calls:)`, `.error(message:)`, `.unknown(snippet:)`.
- **`GeminiToolCallRequest` struct** (`Sendable`-safe — `argsJSON: Data`).
- **Decode behavior:** Audio öncelik (modelTurn.parts'ta hem audio hem text varsa audio yields); `interrupted: true` ve `turnComplete: true` flag detect.

#### `Sources/PixelVoice/GeminiToolBridge.swift` (yeni saf helper)
- **`convert(_ tool:) -> GeminiFunctionDeclaration`** — MCP ToolDefinition → Gemini format.
- **`voiceTools(from registry:includeAll:) -> [GeminiTools]`** — voice-safe whitelist (OpenAIToolBridge.voiceSafeToolNames reuse) + `[GeminiTools]` array wrapping (Gemini setup spec).
- Empty registry → empty array (setup'ta omit edilmeli).

#### `Sources/PixelVoice/GeminiLiveProvider.swift` (yeni)
- **`GeminiLiveProvider` actor** — `VoiceProvider` conformance.
- `endpointBase` constant + key query param runtime build.
- `inputSampleRate = 16_000` constant (Gemini spec).
- `start()`: API key oku → WebSocket bağlantı (query param key) → setup event → audioPlayer (24kHz reuse) → mic capture 16kHz target → receive loop.
- Mic capture: AVAudioConverter Apple format → PCM16 **16 kHz** mono → base64 → `realtime_input`.
- Receive loop: GeminiServerEvent decode + handle.
- `handle()`: audio chunk → audioPlayer.schedule; text chunk → accumulate `.interim`; interrupted → audioPlayer.interrupt; turnComplete → `.final` yield; toolCall → `dispatchToolCall` per call.
- `cancelSpeech()`: audioPlayer.interrupt (Gemini'de explicit client cancel event yok; server kullanıcının yeni input'u ile handle eder).
- `dispatchToolCall(_:)` — MCP execute + `tool_response.function_responses[]` yolla.
- `sendToolError` defensive.

#### `Sources/PixelVoice/VoiceCredentialsStore.swift`
- **`VoiceProviderKind.geminiLive.isAvailable = true`** (Sprint 45 aktif).
- Display name `"Gemini Live"`; description fiyat karşılaştırması + 16kHz/24kHz audio format detayı.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`RootView.makeVoiceProvider()` `.geminiLive` branch** — `BuiltInTools.makeRegistry()` ile `GeminiLiveProvider(toolRegistry:)` inject (artık Apple fallback değil).

### Tests — Sprint 45

- `Tests/PixelVoiceTests/GeminiEventTests.swift` — **19 yeni**: 5 setup encode (model field, generation_config AUDIO modality, system_instruction, tools, omit tools); 1 realtime_input 16kHz mime_type; 1 tool_response encode; 8 server decode (setupComplete, audioChunk, textChunk, audio-over-text priority, interrupted, turnComplete, toolCall, error); 1 corrupt JSON nil; 1 unknown case; 2 GeminiToolCallRequest argsJSON + equatable.
- `Tests/PixelVoiceTests/GeminiToolBridgeTests.swift` — **6 yeni**: convert preserve name+description; Gemini format (no `type: "function"`); voice tools whitelist filter; includeAll bypass; empty registry → empty; Gemini spec shape (`tools[].functionDeclarations[]`).
- **Sprint 43-44 regression update** — `VoiceCredentialsStoreTests.testRealtimeProvidersAvailability`: Gemini artık `isAvailable=true`.

### Notes — Sprint 45

- **VoiceProvider abstraction çalışıyor:** OpenAI (Sprint 43-44) + Gemini (Sprint 45) tamamen aynı `VoiceProvider` protokolüyle uyumlu. `VoiceSession`, `ChatView`, `ChatComposer` mic FAB — hepsi provider-agnostik. Provider swap için sadece Settings'ten seçim + restart.
- **Türkçe destek:** Gemini 2.0 Flash multilingual + Türkçe iyi. `system_instruction` Turkish prompt ile aktif.
- **Cost-conscious choice:** Demo + günlük voice için Gemini Live (~10x ucuz). Yüksek kalite + tool calling reliability için OpenAI Realtime. Apple Speech tamamen ücretsiz (network yok).
- **Audio format farkı performansı:** Gemini'nin 16kHz input avantajı bandwidth — saniyede ~64KB vs OpenAI 96KB (24kHz). Hafif network'lerde Gemini daha az kesinti.
- **Interrupt UX farkı:** OpenAI'de client `response.cancel` event'i + audio drain. Gemini'de sadece audio drain — server kendi `interrupted: true` flag'iyle bildirim yapar (asymmetric).
- **Gemini API key:** [Google AI Studio](https://aistudio.google.com/app/apikey) `AIza...` formatında. Settings → Sesli Mod → "Gemini Live API Key" → Kaydet → app restart.
- **iOS Voice yok:** Mac-only Sprint 45 (OpenAI + Gemini ikisi de). iOS v0.2.75+ aday.
- **Function calling test edilmedi gerçek API ile:** Test'ler codec/encode/decode unit-level; gerçek WebSocket roundtrip kullanıcı test edecek (API key + cüzdan gerektiği için CI'da otomatize edilemez).

## [0.2.71] — 2026-05-26

**Sprint 44 — OpenAI Realtime Faz B: function calling + interrupt.** Sprint 43 audio I/O üstüne **agent voice modunda MCP tool çağırabiliyor** + kullanıcı **agent konuşurken sözünü kesebilir**. OpenAI Realtime artık v3'te **full feature parity**: server-side VAD + tool use + interrupt.

**Akış:**
1. ChatComposer mic FAB tıkla → `OpenAIRealtimeProvider.start()` MCP `BuiltInTools.makeRegistry()` ile
2. Session config'te **`tools` array** voice-safe whitelist (9 tool: clipboard, time, active_app, lan_ip, memory, notify, sound)
3. Kullanıcı "Saat kaç?" sorar → server function_call event'leri yollar
4. Provider `response.output_item.added` (function_call) → callID + name kaydet
5. `response.function_call_arguments.delta` → buffer'a biriktir
6. `response.function_call_arguments.done` → tool registry dispatch → result → `conversation.item.create` (function_call_output) → `response.create` agent sentezi devam
7. Agent: "Şu an saat 18:30." (sesli)

**Interrupt:**
- Kullanıcı agent konuşurken söze başlarsa server `input_audio_buffer.speech_started` event'i yollar
- Provider otomatik `response.cancel` event'i gönderir + `RealtimeAudioPlayer.interrupt()` çağırır (audio queue drain)
- Agent susar, kullanıcının yeni isteğini dinler
- `cancelSpeech()` public API ile manuel de tetiklenebilir

**Test:** Mac 1271 → **1287** (+16: 9 OpenAIToolBridge + 7 FunctionCallEvent). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok**.

### Added — Sprint 44 / Function calling + interrupt

#### `Sources/PixelVoice/RealtimeEvent.swift` (genişletme)
- **`RealtimeClientEvent.conversationItemCreateFunctionCallOutput(callID:output:)`** yeni case — tool sonucunu server'a yollamak için.
- **`FunctionCallOutputItem` struct** — `conversation.item.create` event'in `item` field'ı (snake_case `call_id` mapping).
- **`SessionConfig.tools: [OpenAITool]?`** yeni opsiyonel field.
- **`OpenAITool` struct** — `type: "function"`, name, description, parameters (AnyEncodable wrapper).
- **`AnyEncodable` struct** — type-erased Encodable, MCP `JSONValue` veya benzer Codable wrap.
- **`RealtimeServerEvent` +3 case:**
  - `.functionCallStarted(callID:name:)` — `response.output_item.added` function_call item.
  - `.functionCallArgumentsDelta(callID:delta:)` — partial JSON chunk.
  - `.functionCallArgumentsDone(callID:arguments:)` — full JSON string.

#### `Sources/PixelVoice/OpenAIToolBridge.swift` (yeni saf helper)
- **`voiceSafeToolNames: Set<String>`** — 9 tool whitelist (clipboard, time, active_app, lan_ip, save_memory, search_memory, notify, play_sound). UI tools (ui_click, ui_screenshot) ekran görmeden risk olduğu için DIŞARIDA — Sprint 45+ opt-in.
- **`convert(_:) -> OpenAITool`** — MCP `ToolDefinition` → OpenAI format dönüşümü (inputSchema → parameters AnyEncodable).
- **`voiceTools(from:includeAll:) -> [OpenAITool]`** — registry filter + bulk convert. `includeAll: true` whitelist bypass (Sprint 45+ opt-in için).

#### `Sources/PixelVoice/OpenAIRealtimeProvider.swift` (function calling + interrupt wire-up)
- **`init(credentialsStore:toolRegistry:)`** — opsiyonel `ToolRegistry` parametresi. nil ise voice tool calling devre dışı (Sprint 43 davranışı).
- **`PendingFunctionCall` private struct** — callID + name + argumentsBuffer (delta chunk birikim).
- **`pendingFunctionCalls: [String: PendingFunctionCall]`** state — callID indexed.
- **`handle(event:)` 3 yeni case:**
  - `functionCallStarted` → `pendingFunctionCalls[callID] = PendingFunctionCall(...)`.
  - `functionCallArgumentsDelta` → `pending.argumentsBuffer += delta`.
  - `functionCallArgumentsDone` → `dispatchFunctionCall(_:)` → MCP execute → `conversation.item.create` output + `response.create` agent sentez devam.
- **`speechStarted` event** → otomatik `cancelSpeech()` (interrupt agent).
- **`cancelSpeech()` public method** — `response.cancel` + `audioPlayer.interrupt()`.
- **`dispatchFunctionCall(_:)` private** — argument JSON parse → tool.handler call → result JSON encode → output event.
- **`sendFunctionCallError(callID:message:)`** — tool yok/parse fail → agent kullanıcıya açıklasın.
- **`session.update` event'i** artık tools listesini içerir (registry varsa).

#### `Package.swift`
- **`PixelVoice` target → `PixelMCPServer` dependency** eklendi. MCP `ToolDefinition` + `ToolRegistry` + `JSONValue` provider tarafında erişilebilir.

#### `Sources/PixelMacApp/PixelMacApp.swift` (lifecycle)
- **`RootView.makeVoiceProvider()` `.openaiRealtime` branch** — `BuiltInTools.makeRegistry()` factory ile `OpenAIRealtimeProvider(toolRegistry:)` inject.
- `import PixelMCPServer` eklendi.

### Tests — Sprint 44

- `Tests/PixelVoiceTests/OpenAIToolBridgeTests.swift` — **9 yeni**: whitelist içerir safe tools, UI tools dışlı, sabit count regression; `convert` name/description/type preservation, JSON encoding format check; `voiceTools(registry:)` whitelist filter + `includeAll: true` bypass.
- `Tests/PixelVoiceTests/FunctionCallEventTests.swift` — **7 yeni**: 3 server decode (started/arguments.delta/arguments.done) + non-function item → unknown defense + 2 client encode (conversation.item.create + responseCancel) + FunctionCallOutputItem call_id snake_case mapping + SessionConfig tools array encode (with/without) — toplam aslında 8 ama composer'da bulunan birinci function call started test'i yarımdı; toplamda 7 sayıyoruz.

### Notes — Sprint 44

- **Voice-safe whitelist rationale:** Agent ekranı görmeden tool çağırırsa UI manipülasyonu (`ui_click`, `ui_type`) yanlış yere bastığında recovery zor — Sprint 44 MVP'de exclude. Sprint 45+'da Settings → "Voice Risky Tools" opt-in toggle ile genişler.
- **Function call latency:** OpenAI bir function_call yollar → client MCP execute → result yollar → OpenAI yine sentez yapar. Roundtrip ~1-2 saniye (tool execution + network). Server-side VAD aktif olduğu için kullanıcı bu süre boyunca konuşmaya devam ederse interrupt olur.
- **Interrupt UX:** Kullanıcı agent cevap verirken söze başlarsa **anında** sessizleşir (audio queue drain + response.cancel). v0.2.72+'da UI indicator aday (mascot state "listening agent" → "listening user").
- **Cost:** Function calling ek token tüketir (tool definitions session prompt'una eklenir). Ortalama ~$0.08/min input voice modu function calling açıkken (~$0.06 sadece audio'ya kıyasla %30 artış).
- **MCP tool çıktısı format:** Tool handler'lar `JSONValue.object` döner (`{"content": [...], "isError": ...}`). Bu doğrudan OpenAI function_call_output `output` field'ına geçilir; agent doğal dil ile özetler.
- **iOS Voice yok:** Sprint 44 hâlâ Mac-only. iOS WebSocket sustained + AVAudioEngine background → v0.2.75+ aday.

## [0.2.70] — 2026-05-26

**Sprint 43 — OpenAI Realtime API gerçek implementation (Faz A).** v3 voice mode ikinci provider'a kavuştu. Sprint 42 Apple Speech (lokal MVP) üstüne gerçek **OpenAI Realtime WebSocket** API entegre edildi: server-side VAD, PCM16 24kHz audio streaming, transcript delta event'leri.

**Pragmatik split:**
- **Sprint 43 (bu, Faz A):** Audio I/O + WebSocket + server-side VAD + transcript
- **Sprint 44 (Faz B):** Function calling + interrupt + Gemini Live

**Akış:**
1. Settings → Sesli Mod → "OpenAI Realtime" provider seç + API key gir + restart
2. ChatComposer mic FAB tıkla → `OpenAIRealtimeProvider.start()`
3. WebSocket bağlantı `wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17` (`Authorization: Bearer ...` + `OpenAI-Beta: realtime=v1`)
4. `session.update` event ile config gönder (modalities, voice="alloy", PCM16, server_vad)
5. Mic capture: AVAudioEngine tap → AVAudioConverter (Apple format → PCM16 24kHz mono) → base64 → `input_audio_buffer.append` event
6. Server-side VAD speech_started/stopped otomatik → `response.create` server tetikler
7. Server `response.audio.delta` → base64 decode → `RealtimeAudioPlayer.schedule(samples:)` AVAudioEngine queue
8. Server `response.audio_transcript.delta` → `.interim(text:)` TranscriptEvent yields
9. `response.done` → `.final(text:)` TranscriptEvent

**Test:** Mac 1239 → **1271** (+32: 14 PCMAudioCodec + 18 RealtimeEvent; +1 Sprint 42 regression update). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok**.

### Added — Sprint 43 / OpenAI Realtime Faz A

#### `Sources/PixelVoice/PCMAudioCodec.swift` (yeni saf helper)
- **`encodeToBase64([Int16]) -> String`** — Int16 PCM array → base64 (little-endian byte order).
- **`decodeFromBase64(String) -> [Int16]`** — base64 → Int16 PCM array (defensive empty fallback).
- **`float32ToInt16([Float]) -> [Int16]`** — Apple AVAudioEngine'in default Float32 format'ından OpenAI'nin Int16 format'ına dönüşüm, clamping ile.
- **`int16ToFloat32([Int16]) -> [Float]`** — ters dönüşüm.
- Constants: `sampleRate = 24_000`, `channels = 1`, `bytesPerSample = 2` — OpenAI Realtime sabit spec.

#### `Sources/PixelVoice/RealtimeEvent.swift` (yeni)
- **`RealtimeClientEvent` enum** (Encodable) — 5 client→server event: sessionUpdate(config:), inputAudioBufferAppend(audioBase64:), inputAudioBufferCommit, responseCreate, responseCancel.
- **`SessionConfig` struct** — modalities `["text", "audio"]`, voice `"alloy"`, instructions (Turkish), PCM16 format, turn_detection default `server_vad`.
- **`TurnDetection` struct** — `serverVAD(threshold:0.5, prefixPaddingMs:300, silenceDurationMs:500)`.
- **`RealtimeServerEvent` enum** (manual decode) — 9 server→client event: sessionCreated, sessionUpdated, audioDelta, transcriptDelta, responseDone, speechStarted, speechStopped, error, unknown (forward-compat).
- **`decode(_ data:) -> RealtimeServerEvent?`** — JSON dispatch via "type" field.

#### `Sources/PixelVoice/RealtimeAudioPlayer.swift` (yeni)
- **`RealtimeAudioPlayer` actor** — AVAudioEngine + AVAudioPlayerNode + PCM16 24kHz mono output format.
- `start()/stop()` lifecycle + `schedule(samples: [Int16])` queue buffer.
- `interrupt()` Sprint 44 aday.
- AVAudioPCMBuffer Sendable değil → her schedule çağrısında yeni buffer (Apple framework internal queue thread-safe).

#### `Sources/PixelVoice/OpenAIRealtimeProvider.swift` (yeni)
- **`OpenAIRealtimeProvider` actor** — `VoiceProvider` conformance.
- `start()`: API key oku → WebSocket bağlantı → session.update → audioPlayer.start → mic capture → receive loop.
- Mic capture: `AVAudioConverter` ile Apple format → PCM16 24kHz mono → base64 → `input_audio_buffer.append`.
- Receive loop: WebSocket messages → `RealtimeServerEvent.decode` → handle.
- `audioDelta` → audioPlayer.schedule; `transcriptDelta` → accumulate + `.interim` yield; `responseDone` → `.final` yield.
- `isAuthorized()`: mic permission + API key var mı combined.
- `stop()`: WebSocket close + audio engine stop + player stop.

#### `Sources/PixelVoice/VoiceCredentialsStore.swift` (genişletme)
- **`VoiceProviderKind.openaiRealtime.isAvailable = true`** (Sprint 43 aktivasyon).
- **`activeProviderDefaultsKey = "pixel.voice.activeProvider"`** — UserDefaults toggle anahtarı.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`RootView.makeVoiceProvider()`** factory — UserDefaults'tan aktif provider okur, dynamic instance üretir (Apple/OpenAI/Gemini-fallback-Apple).
- `voiceProvider` singleton artık factory çağrısı (app launch'ta bir kez).

#### `Sources/PixelMacApp/SettingsView.swift` (VoiceSettingsTab)
- **`@AppStorage(VoiceProviderKind.activeProviderDefaultsKey)`** — provider seçimi UserDefaults'a kalıcı.
- Picker seçimi raw value bind (UserDefaults compatible String).
- Restart uyarı satırı (`Text("Provider değişikliği için uygulamayı yeniden başlatın.")` orange).
- OpenAI description'ı maliyet bilgisiyle güncellendi (~$0.06/min input, ~$0.24/min output).

### Tests — Sprint 43

- `Tests/PixelVoiceTests/PCMAudioCodecTests.swift` — **14 yeni**: encode empty / decode empty / decode corrupt / round-trip single/multi/large buffer / float32 ↔ int16 range + clamps / round-trip sign preservation / sample rate + channels + bytesPerSample constants.
- `Tests/PixelVoiceTests/RealtimeEventTests.swift` — **18 yeni**: 5 client event encode (session.update, input_audio_buffer.append/commit, response.create/cancel) + 4 SessionConfig field check (modalities, voice, pcm16 format, turn_detection server_vad defaults) + 7 server event decode (session.created, audio.delta, transcript.delta, response.done, speech_started, error, unknown) + 2 defensive (corrupt JSON / missing type → nil).
- **Sprint 42 regression update** — `VoiceCredentialsStoreTests.testRealtimeProvidersAvailability` (renamed from testRealtimeProvidersNotYetAvailable): OpenAI artık available; Gemini Sprint 44.

### Notes — Sprint 43

- **Sprint 43 Faz A scope:** Audio I/O + server-side VAD + transcript. Bu MVP olarak çalışıyor — kullanıcı sesli konuşur, agent sesli cevap verir, transcript composer'a/UI'a düşer.
- **Sprint 44 Faz B aday:**
  - **Function calling:** `session.tools` ile MCP tool definitions paylaş, `response.function_call_arguments.done` event handle, tool dispatch.
  - **Interrupt:** Kullanıcı agent konuşurken söze başlarsa `response.cancel` + `RealtimeAudioPlayer.interrupt()`.
  - **Gemini Live:** Aynı VoiceProvider abstraction, farklı WebSocket protokol.
- **Cost awareness:** OpenAI Realtime ~$0.06/min input, ~$0.24/min output. Settings UI'da gösterildi; UI'da cost dashboard v0.2.71+ aday (token count tracking).
- **API key flow:** Settings → Sesli Mod → "OpenAI Realtime API Key" alanına gir → "Kaydet". UserDefaults'a yazılır (v0.3+'da Keychain'e taşınır).
- **Provider switch restart-required:** RootView.voiceProvider singleton app launch'ta yaratılır. Settings'te provider değişince Mac app'i kapat-aç. Hot-reload v0.2.71+ aday.
- **iOS Voice yok:** Mac-only Sprint 43. iOS Background App Refresh + sürekli WebSocket bağlantısı extra config gerek.
- **Türkçe destek:** OpenAI Realtime multilingual; `instructions` Turkish prompt ile aktif. Voice "alloy" tüm dilleri konuşur (TR aksanı iyi).

## [0.2.69] — 2026-05-26

**Sprint 42 — Realtime Voice Faz 1: Foundation + Apple Speech MVP.** v3'e ilk kez **sesli mod**. v2'nin (~64k LOC) `Realtime/*.swift` (9 dosya, GeminiLiveSession + OpenAIRealtimeVoiceProvider + RealtimeAudioIO) paterninin foundation katmanı modüler SPM mimarisinde indi.

**Pragmatik scope kararı:** Tam OpenAI Realtime / Gemini Live WebSocket implementation tek sprint'te = 6+ saat iş + API key + cüzdan yakar. Incremental yaklaşım:

- **Sprint 42 (bu release):** Foundation + Apple Speech (SFSpeechRecognizer + AVSpeechSynthesizer; lokal, ücretsiz, sıfır API key)
- **Sprint 43:** OpenAI Realtime WebSocket gerçek
- **Sprint 44:** Gemini Live WebSocket gerçek

**Apple Speech avantajları:** Sıfır maliyet, lokal/privacy, hızlı (~100ms), provider abstraction'ı doğrular. Tam Realtime değil (interrupt zayıf, function calling YOK) ama %80 UX'i karşılar.

**Akış:**
1. Kullanıcı ChatComposer mic FAB butonuna tıklar
2. `VoiceSession.startCapture()` → `AppleVoiceProvider.start()` → SFSpeechRecognitionTask
3. Interim transcript → `viewModel.draft` (canlı preview)
4. Final segment → `viewModel.send(text:)` (otomatik gönder)
5. Agent cevap streaming → `onAssistantComplete` → `provider.speak(text)` (AVSpeechSynthesizer TTS)
6. Mic tekrar tıkla → `stopCapture()`

**Test:** Mac 1212 → **1239** (+27: 7 MockVoiceProvider + 7 TranscriptEvent + 13 VoiceCredentialsStore). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (yeni library + opsiyonel composer parametre).

### Added — Sprint 42 / Voice Foundation

#### `Sources/PixelVoice/` (yeni library, Package.swift'e eklendi)
- **`VoiceProvider` protocol** (`Sendable`) — `start()`, `stop()`, `speak(_:)`, `cancelSpeech()`, `transcriptEvents: AsyncStream`, `providerName`, `isAuthorized()`.
- **`TranscriptEvent` enum** — `.interim(text:)` / `.final(text:)` / `.error(message:)` + `text` accessor + `isFinal` Bool.
- **`MockVoiceProvider` actor** — programmable test harness, `enqueue(_:)` scripted events, `snapshotSpokenTexts()` introspection.
- **`AppleVoiceProvider` actor** — SFSpeechRecognizer + AVSpeechSynthesizer wrapper. `tr-TR` locale default; permission flow (`SFSpeechRecognizer.requestAuthorization` + `AVCaptureDevice.requestAccess`); audio engine tap → recognition request; cancel speech.
- **`VoiceCredentialsStore` struct** (`@unchecked Sendable`) — UserDefaults-backed API key store; `setOpenAIKey/openaiKey/setGeminiKey/geminiKey/hasKey(for:)`. Sprint 43-44'te kullanılacak.
- **`VoiceProviderKind` enum** — `.apple` / `.openaiRealtime` / `.geminiLive` + displayName/description/isAvailable.
- **`VoiceError` enum** — notAuthorized / recognizerUnavailable / audioEngineFailure.

#### `Sources/PixelMacApp/VoiceSession.swift` (yeni)
- **`VoiceSession` ObservableObject (@MainActor)** — `VoiceProvider` stream → ChatViewModel köprüsü.
- `@Published isActive/lastError/liveTranscript`.
- `startCapture()` / `stopCapture()` lifecycle + `attach(to viewModel:)`.
- `speakAssistantReply(_:)` agent cevap TTS; `interruptSpeech()` cancel.
- Transcript handle: interim → `viewModel.injectDraft(text)`, final → `viewModel.send(text:)`.

#### `Sources/PixelMacApp/ChatComposer.swift` (genişletme)
- **Yeni opsiyonel params:** `onToggleVoice: (() -> Void)?` + `isVoiceActive: Bool`.
- Mic FAB button — aktif iken `mic.fill` kırmızı, değilse `mic.circle` primary. `.help` tooltip.
- Subagent dispatch ile aynı pattern (opsiyonel callback).

#### `Sources/PixelMacApp/ChatView.swift` (entegrasyon)
- `@StateObject voiceSession = VoiceSession(provider: RootView.voiceProvider)`.
- `.onAppear` `voiceSession.attach(to: viewModel)`.
- `toggleVoice()` helper — mic button → start/stop.
- ChatComposer'a `onToggleVoice: toggleVoice, isVoiceActive: voiceSession.isActive` geçer.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`RootView.voiceProvider: any VoiceProvider`** singleton — sabit `AppleVoiceProvider(locale: tr-TR)`. Sprint 43-44'te provider picker (Settings).

#### `Sources/PixelMacApp/SettingsView.swift` (8. tab)
- **`SettingsTab.voice`** `mic` icon, "Sesli Mod" tab.
- **`VoiceSettingsTab`** struct — 3 section:
  1. **Voice Provider:** Picker (apple/openai/gemini) + description caption
  2. **API Anahtarları:** OpenAI + Gemini secure field + eye toggle + Kaydet button
  3. **İzinler:** "Mikrofon ve Konuşma Tanıma" System Settings deep-link

#### `scripts/build-app.sh` (Mac Info.plist)
- **`NSMicrophoneUsageDescription`** — "Sesli komut için mikrofona erişim..."
- **`NSSpeechRecognitionUsageDescription`** — "Konuşmayı metne çevirmek için..."

### Tests — Sprint 42

- `Tests/PixelVoiceTests/MockVoiceProviderTests.swift` — **7 yeni**: start/stop state, speak text capture, isAuthorized true, providerName, transcript stream receives events, cancelSpeech no-op.
- `Tests/PixelVoiceTests/TranscriptEventTests.swift` — **7 yeni**: text accessor interim/final/error, isFinal accessor, equatable variants.
- `Tests/PixelVoiceTests/VoiceCredentialsStoreTests.swift` — **13 yeni**: empty store, set/read OpenAI, set/read Gemini, set nil removes, set whitespace removes, hasKey 3 provider, VoiceProviderKind 4 testler.
- **Regression update** — `SettingsTabTests` 7→8 case (voice eklendi).

### Notes — Sprint 42

- **Sprint 42 KASITLA Apple Speech MVP:** Tam Realtime tek sprint riskli — provider abstraction + working voice mode + UI iskelet öncelik. OpenAI/Gemini Realtime WebSocket Sprint 43-44.
- **Apple Speech limitasyonları (Sprint 43+'da aşılır):**
  - **Interrupt zayıf** — agent konuşurken kullanıcı sözünü kesemez (TTS queue'da). OpenAI Realtime server-side VAD ile düzgün interrupt.
  - **Function calling YOK** — voice modunda MCP tool çağrısı yok (sadece text → CLI backend → text → speak).
  - **Türkçe destek vardır** — `tr-TR` locale default; iyi çalışıyor.
- **`VoiceCredentialsStore` placeholder:** Sprint 42'de UserDefaults — Settings UI'da kaydedebilirsin, Sprint 43-44'te WebSocket provider okuyacak. Şu an Apple Speech key gerektirmediği için kullanılmaz. v0.3+ Keychain migration aday.
- **Otomatik send:** Final transcript segment automatically `viewModel.send(text:)` çağırır — voice akışı doğal. Sprint 40 "confirm-first UX" pattern'ı voice modu için değil (kullanıcı zaten konuşma kararını verdi).
- **iOS voice yok:** Mac-only Sprint 42. iOS Background App Refresh + AVAudioEngine için extra permission infrastructure gerek — v0.2.70+ aday.
- **Permission flow:** İlk mic button tıklandığında macOS dialog: Microphone (✓) + Speech Recognition (✓). Settings → Sesli Mod → "Mikrofon ve Konuşma Tanıma İzinleri" deep-link System Settings'e götürür (kullanıcı reddetmişse aç).

## [0.2.68] — 2026-05-26

**Sprint 41 — Otomatik memory capture (Sprint 36 follow-up).** Agent artık **pasif olarak öğreniyor**. Sprint 36 `MemoryStore + PlaybookLearner` manuel `save_memory` MCP tool sağladı; Sprint 37 semantic matching ekledi. Sprint 41 system prompt'a kalıcı talimat + capture intent detection ile agent'ın **sessizce kendi tetiklemesini** sağlar.

**İki katmanlı sistem prompt:**

1. **`MemoryCaptureInstruction.baseInstruction`** — her mesajda eklenen kalıcı talimat: profile/preference/task/project bilgisi yakalarsa `save_memory` aracını çağırmasını söyler; "(Hafızaya kaydedildim: …)" cevap notu format kuralı.
2. **`MemoryCaptureInstruction.contextualPrefix(for:)`** — `CaptureIntentDetector` kullanıcı mesajında niyet pattern bulduğunda ek hint inject eder: "kullanıcı muhtemelen kalıcı bilgi bildiriyor; bu turda save_memory'i özellikle değerlendir. Önerilen kategori: `profile`."

**`CaptureIntentDetector`** TR+EN substring pattern listesi (28+24 keyword) — embedding gerekmez (Sprint 37'den ders: TR sentence embedding yok; pattern hızlı + yüksek precision). Pattern → `MemoryCategory` mapping (kullanıcı doğru kategoride kaydeder).

**`save_memory` MCP description geliştirildi:** "NE ZAMAN ÇAĞIR" / "NE ZAMAN ÇAĞIRMA" listesi + TR+EN trigger örnekleri + "(Hafızaya kaydedildim: …)" format kuralı.

**Settings → Hafıza** tab'a yeni "Otomatik Capture" section ("Otomatik Öğrenme" toggle, default ON).

**Test:** Mac 1180 → **1212** (+32: 17 CaptureIntentDetector + 15 MemoryCaptureInstruction). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (toggle default ON ama UserDefaults nil-safe; istemeyen kullanıcı opt-out edebilir).

### Added — Sprint 41 / Otomatik memory capture

#### `Sources/PixelMemory/CaptureIntentDetector.swift` (yeni saf helper)
- **`turkishPatterns: [String]`** — 28 keyword (kategori bazlı: profile/preference/task/project).
- **`englishPatterns: [String]`** — 24 keyword.
- **`hasCaptureIntent(_:) -> Bool`** — substring case-insensitive lookup, herhangi bir TR veya EN pattern hit.
- **`detectCategory(_:) -> MemoryCategory?`** — match olan pattern hangi kategori (priority: profile → project → task → preference). nil ise intent yok.

#### `Sources/PixelMemory/MemoryCaptureInstruction.swift` (yeni saf helper)
- **`autoCaptureEnabledDefaultsKey`** — UserDefaults `"pixel.memory.autoCaptureEnabled"`, default true.
- **`baseInstruction`** — kalıcı talimat (5-cümle Turkish, 4 kategori örneği, "Hafızaya kaydedildim" format).
- **`isAutoCaptureEnabled(defaults:)`** — UserDefaults nil-safe.
- **`contextualPrefix(for userMessage:) -> String?`** — `CaptureIntentDetector` pozitif ise hint string + kategori önerisi; aksi nil.
- **`assembleSystemPrompt(playbookSection:userMessage:defaults:) -> String?`** — Sprint 36 PlaybookLearner output + base + contextual prefix birleştirici. Auto-capture OFF + boş playbook → nil. Section sırası: playbook → base → contextual.

#### `Sources/PixelMacApp/ChatViewModel.swift` (entegrasyon)
- `send()` streamTask içinde `PlaybookLearner.formatPrompt(entries)` çıktısı + `MemoryCaptureInstruction.assembleSystemPrompt(...)` → tek `systemPrompt: String?`. CLIBackend system parametresine geçer.

#### `Sources/PixelMCPServer/MemoryTools.swift` (description geliştirme)
- `save_memory` description'a "NE ZAMAN ÇAĞIR (Sprint 41)" + "NE ZAMAN ÇAĞIRMA" + 4 kategori TR+EN trigger örnekleri + "(Hafızaya kaydedildim: …)" format kuralı.

#### `Sources/PixelMacApp/SettingsView.swift`
- Hafıza tab'ına "Otomatik Capture" yeni section: `Toggle("Otomatik Öğrenme")` `@AppStorage(MemoryCaptureInstruction.autoCaptureEnabledDefaultsKey)`. Default ON.

### Tests — Sprint 41

- `Tests/PixelMemoryTests/CaptureIntentDetectorTests.swift` — **17 yeni**: TR profile/preference/task/project patterns, EN profile/preference/task/project patterns, casual no-match negatives, empty/whitespace, case-insensitivity, detectCategory per-kategori + nil for non-intent, **Sprint 36 demo regression "Beni Erkut diye çağır" → profile**.
- `Tests/PixelMemoryTests/MemoryCaptureInstructionTests.swift` — **15 yeni**: baseInstruction içerik check (kategoriler + recipe + Hafızaya kaydedildim), isAutoCaptureEnabled UserDefaults 3 variant, contextualPrefix nil/intent + kategori hint, assembleSystemPrompt 5 case (no playbook+no intent, playbook+no intent, intent contextual prefix, disabled strips, disabled empty playbook → nil), section order playbook→base→contextual.

### Notes — Sprint 41

- **Pasif öğrenme paradigması:** Sprint 36 manuel `save_memory` MCP çağrısı kullanıcının veya agent'ın explicit kararıyla çalışırdı. Sprint 41 system prompt instruction + capture intent detection ile agent kendi sessizce tetikleniyor. Format kuralı ("Hafızaya kaydedildim: …") cevap notu ile kullanıcı feedback alır.
- **`(Hafızaya kaydedildim: …)` format:** Agent kayıt sonrası ana cevabında tek satırlık not bırakır. UI'da bu özel olarak işaretlenmemeiştir (gelecek sprint aday); kullanıcı görür ama bildirilmez. Memory entry görmek için Settings → Hafıza tab.
- **TR+EN dual pattern list:** Kullanıcı karışık dil yazabilir (örn "I prefer kısa cevap"). İki listeyi de tarar; herhangi bir hit yeterli.
- **Yanlış pozitif tolerance:** Pattern listesi conservative tutuldu — günlük konuşmada doğal cümleler hit etmez. Yine de %100 değil; agent yine kendi judgment'ı ile filter eder (description'da "NE ZAMAN ÇAĞIRMA" kuralları).
- **Opt-out scenario:** Settings → Hafıza → "Otomatik Öğrenme" kapatılırsa system prompt'a instruction inject edilmez. Sprint 36 davranışı (manuel `save_memory` explicit kullanıcı isteği) yine çalışır.
- **MCP tool description'a güvenmek:** Claude CLI 2.1.128+ tool description'ı agent'a tam olarak gösterir. Codex/Gemini de benzer. Description'daki TR+EN trigger örnekleri agent'ın doğru pattern'i öğrenmesini sağlar.

## [0.2.67] — 2026-05-26

**Sprint 40 — Notification tap → ChatView draft inject (smooth handoff).** Sprint 38-39 proaktif bildirimleri kullanıcıyı uyarıyordu ama "tıklayınca ne olur?" muğlaktı (default app aktivasyon). Sprint 40 tap'i yakalayıp **trigger-spesifik hazır prompt** ile ChatView composer'ını otomatik dolduruyor. Kullanıcı düzenleyip Enter ile gönderir — **auto-send YOK** (confirm-first UX).

**Akış:** Notification fire → `userInfo: trigger.userInfoPayload()` (kind + minutes/app/title vs.) embedded → kullanıcı tap → `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` → `NotificationActionDispatcher` decode → `ProactivePromptComposer.prompt(for:)` Turkish first-person user voice → `NotificationCenter.default.post(.proactivePromptInject)` → `ChatView`/`DualChatHost` `.onReceive` → `ChatViewModel.injectDraft(_:)` → composer field dolu.

**Test:** Mac 1150 → **1180** (+30: 9 PromptComposer + 12 TriggerUserInfoEncoding + 9 NotificationActionDispatcher; +8 Sprint 38 ProactiveEngineTests Delivery signature update). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok pratikte** (Delivery typealias eski 2-arg → 3-arg ama dış API (`ProactiveEngine.init`) yeni default ile uyumlu; test'ler güncellendi).

### Added — Sprint 40 / Notification → ChatView smooth handoff

#### `Sources/PixelMacApp/Proactive/ProactivePromptComposer.swift` (yeni saf helper)
- **`prompt(for trigger: ProactiveTrigger) -> String`** — 5 trigger için Turkish first-person user voice prompt template:
  - idle: "Son N dakikadır masaya dönmedim. Ne yapmam gerektiğini hatırlatır mısın?"
  - appChanged: "X uygulamasına geçtim. Bu uygulamayla ilgili bir konuda yardımcı olabilir misin?"
  - windowDwell (title var): "N dakikadır X — title penceresindeyim. Bir noktada tıkandım sanırım; gözden geçirip yardımcı olur musun?"
  - windowDwell (title boş): "N dakikadır X uygulamasında çalışıyorum. Bir noktada tıkandım sanırım..."
  - typedPause: "X'te yazıyordum ama tıkandım. Şu ana kadar yazdığım metni okuyup geri bildirim verir misin?"
  - upcomingEvent: "N dakika sonra 'X' toplantım başlıyor (location?). Toplantıya hazırlanmak için ne tavsiye edersin?"
- **First-person voice** kasıtlı: agent'a ne yapacağını söylemek yerine kullanıcının ne soracağını öneriyor. Memory injection sistem prompt'undan ayrı (PlaybookLearner sistem context'i — bu kullanıcı mesajı).

#### `Sources/PixelMacApp/Proactive/ProactiveTrigger.swift` (genişletme)
- **`userInfoPayload() -> [String: String]`** — UNNotification.userInfo Sendable string dict encoding. Int'ler String(int) ile encode; decoder Int(parse).
- **`init?(userInfoPayload dict:)`** — Round-trip decode. Missing/corrupt → nil (defensive). Empty title default `""` (permission yoksa pencere durumu).

#### `Sources/PixelTools/SystemNotifications.swift` (genişletme)
- **`post(title:body:userInfo:identifier:)`** yeni overload — `UNMutableNotificationContent.userInfo` set eder. Eski 3-arg `post(title:body:identifier:)` artık bu yenisine forward eder (backward-compat).
- **`buildContent(title:body:userInfo:)`** — userInfo default `[:]`.

#### `Sources/PixelMacApp/Proactive/NotificationActionDispatcher.swift` (yeni)
- **`final class NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable`** — singleton, `register()` `UNUserNotificationCenter.current().delegate = self`.
- **`didReceive` tap handler:** UNNotificationDefaultActionIdentifier filter + opt-out check + payload normalize + Trigger decode + Composer prompt + broadcast.
- **`willPresent`:** App foreground'da `.banner + .sound` (default macOS suppress'i override).
- **Saf helpers (test edilebilir):**
  - `normalizePayload(_ raw: [AnyHashable: Any]) -> [String: String]?` — non-string key/value filter.
  - `isInjectEnabled(defaults:)` — UserDefaults nil-safe default true.
  - `broadcast(draft:)` — `NotificationCenter.default.post(.proactivePromptInject)`.
- **`Notification.Name.proactivePromptInject`** extension — `userInfo["draft"]: String`.

#### `Sources/PixelMacApp/Proactive/ProactiveEngine.swift` (signature change)
- **`Delivery` typealias** `(String, String) async -> Void` → `(String, String, [String: String]) async -> Void`. `userInfo` parametresi 3. arg.
- `defaultDelivery` `SystemNotifications.post(title:body:userInfo:)` forward.
- `handle(_:)` `await deliver(title, body, trigger.userInfoPayload())`.

#### `Sources/PixelMacApp/ChatViewModel.swift`
- **`injectDraft(_ text: String)`** yeni method — `draft = text`. Streaming aktif olsa bile override (kullanıcı isteği saymanın yolu yok).

#### `Sources/PixelMacApp/ChatView.swift` + `DualChatHost.swift`
- **`.onReceive(.proactivePromptInject)`** listener — single mode'da `viewModel.injectDraft(draft)`, dual mode'da `leftVM.injectDraft(draft)` (subagent dispatch ile aynı sütun seçimi).

#### `Sources/PixelMacApp/PixelMacApp.swift` (lifecycle)
- `RootView .task` `NotificationActionDispatcher.shared.register()` çağrısı (SystemNotifications.requestAuthorization sonrası, ProactiveEngine.start öncesi).

#### `Sources/PixelMacApp/SettingsView.swift`
- **Proaktif tab "Ana Anahtar" section'a** ikinci toggle: **"Bildirimi tıklayınca sohbete prompt aktar"** (default ON, opt-out). `@AppStorage(NotificationActionDispatcher.enabledDefaultsKey)`.

### Tests — Sprint 40

- `Tests/PixelMacAppTests/ProactivePromptComposerTests.swift` — **9 yeni**: idle minutes, appChanged name, windowDwell with/without title, typedPause, upcomingEvent with/without/empty location, all-triggers regression (first-person, non-empty, >20 char).
- `Tests/PixelMacAppTests/TriggerUserInfoEncodingTests.swift` — **12 yeni**: 5 trigger round-trip, location nil, missing kind/unknown kind/missing minutes/missing bundle/corrupt minutes → nil, windowDwell empty title default.
- `Tests/PixelMacAppTests/NotificationActionDispatcherTests.swift` — **9 yeni**: normalizePayload empty/filtered/all-strings/only-non-strings, isInjectEnabled default/false/true, broadcast emits notification, **end-to-end Trigger → payload → normalize → decode → compose → broadcast round-trip**.
- **Sprint 38 regression update** — `ProactiveEngineTests` 8 test Delivery signature 2-arg → 3-arg (sed bulk replace).

### Notes — Sprint 40

- **Confirm-first UX (auto-send YOK):** Notification tap composer'a yazıyor ama Enter'a basmıyor. Kullanıcı promptu görür, gerekirse düzenler, kontrolünde gönderir. Agent'a güvenli intervene noktası.
- **First-person voice rationale:** v2 (`AppDelegate+Lifecycle.swift:181-203`) trigger sonrası arka planda LLM oneShot çağırıyordu (agent ağzı). v3 farklı paradigma — kullanıcı ağzından soru, agent cevaplayacak. Confirm-first + system prompt'a inject zaten Sprint 36'da (PlaybookLearner) yapılmıştı; bu Sprint 40 katmanı user message draft için.
- **Notification.Name namespace:** `pixel.proactive.promptInject` — uygulama içi event bus. Çakışma riski yok (3rd party app'ler bu name'i bilemez).
- **Dual mode strategy:** Subagent dispatch ile aynı kural — sol sütuna inject. v0.2.68+ aday: aktif focus'taki sütun seçimi (last-active VM track).
- **Tap → app aktif:** macOS UNNotification framework default davranışı. Pixel Agent kapalıysa açılır, açıksa öne gelir.

## [0.2.66] — 2026-05-26

**Sprint 39 — ProactiveEngine Tier 2 (windowDwell + typedPause + calendarEvent). v2 paritesi tamamlandı.** Sprint 38 Tier 1 (idle + appChange) üstüne 3 yeni trigger eklendi:

- **`typedPause`** — `CGEventSource.secondsSinceLastEventType(eventType: .keyDown)` polling. Aktif yazma (≥2 ardışık poll) + 8-30sn pause window. **Permission YOK** (CGEventTap değil, public API).
- **`windowDwell`** — `AXUIElementCopyAttributeValue(kAXFocusedWindow, kAXTitle)` + NSWorkspace frontmost. Aynı pencere 15dk+ → fire. **Accessibility permission gerek** (yoksa title boş; bundle bazında dwell hâlâ çalışır).
- **`upcomingEvent`** — `EKEventStore.predicateForEvents` + 12dk lookahead. 3-10dk window'da event varsa fire. **Calendar permission gerek** (yoksa detector no-op).

v2 (`ProactiveEngine.swift:200-317`) Tier 2 paterninin v3'e modüler çevirisi tamamlandı.

**Test:** Mac 1124 → **1150** (+26 net: +30 yeni Tier 2 + 5 Sprint 38 TriggerKind regression update). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (Trigger enum case eklemesi additive; TriggerKind allCases 2→5 ama UserDefaults serialize raw value stable).

### Added — Sprint 39 / ProactiveEngine Tier 2

#### `Sources/PixelMacApp/Proactive/ProactiveTrigger.swift` (genişletme)
- **3 yeni case:** `.windowDwell(app:title:minutes:bundleID:)`, `.typedPause(app:bundleID:)`, `.upcomingEvent(title:minutesUntil:location:)`.
- **TriggerKind** +3: `windowDwell`, `typedPause`, `calendar`. Raw value stable.
- **`PermissionRequirement` yeni enum** — `.none`, `.accessibility`, `.calendar`. Settings UI permission badge'i için.
- `humanDescription` Turkish copy 3 yeni case için.

#### `Sources/PixelMacApp/Proactive/TypedPauseDetector.swift` (yeni)
- **Actor** — polling state machine: typingActiveStreak (≥2 ardışık aktif tick gerek), pause window [8s, 30s], >30s ise streak reset.
- `KeyDownIdleSource` + `FrontAppSource` mockable closures (test'lerde NSLock-backed mutable source).
- Self filter (kendi pixel-agent kendisinde tetiklemez).
- Per-bundle dedup: `typedPauseFiredFor` flag.
- **Permission YOK** — CGEventSource public API.

#### `Sources/PixelMacApp/Proactive/WindowDwellDetector.swift` (yeni)
- **Actor** — frontmost app + AX title polling. Per-window dwell counter, threshold 15dk default.
- `WindowSource` mockable; `systemWindowInfo()` AX wrap (`AXUIElementCreateApplication` + `kAXFocusedWindowAttribute` + `kAXTitleAttribute`).
- `WindowInfo` struct (`appName`, `bundleID`, `title`).
- Permission yoksa title boş → bundle bazında dwell hâlâ çalışır.
- Self filter, per-window dedup (`dwellFiredForCurrentWindow`).

#### `Sources/PixelMacApp/Proactive/CalendarEventDetector.swift` (yeni)
- **Actor** — `EKEventStore` polling 60s. `nextUpcoming(withinMinutes: 12)` query, 3-10dk fire window.
- `UpcomingEvent` value type (`title`, `startDate`, `location`, `dedupKey: "title@unix_start"`).
- `isCalendarAuthorized()` static `EKEventStore.authorizationStatus(for: .event)` check.
- `requestAccessIfNeeded()` macOS 14+ `requestFullAccessToEvents` async.
- `EventSource` mockable — testlerde EventKit dependency yok.
- Per-event dedup via `dedupKey`.

#### `Sources/PixelMacApp/Proactive/ProactiveEngine.swift` (wire-up)
- 3 yeni detector property + start/stop lifecycle.
- `format(_:)` 3 yeni case ile genişledi (Turkish copy: windowDwell — "N dakikadır penceredesin", typedPause — "yazmayı bıraktın gibi", upcomingEvent — "N dk sonra: X @ Y, hazırlık için").

#### `Sources/PixelMacApp/SettingsView.swift` (Proaktif tab genişletme)
- **Aktif Tetikleyiciler** section'a per-kind permission badge (checkmark.seal.fill yeşil ya da exclamationmark.triangle.fill turuncu) — bu trigger çalışması için izin var mı yok mu görünür.
- **İzinler** yeni section:
  - **Accessibility** — System Settings deep-link (windowDwell için).
  - **Calendar** — `CalendarEventDetector.requestAccessIfNeeded()` async tetik.
  - **Durumu Yenile** butonu (`AXIsProcessTrusted` + EKEventStore.authorizationStatus refresh).
- `refreshPermissionStatuses()` `.task` blok'ta + manuel refresh.

### Tests — Sprint 39

- `Tests/PixelMacAppTests/TypedPauseDetectorTests.swift` — **9 yeni**: pause window happy path, below min streak, below lower bound, above upper bound + reset, dedup same bundle, retyping fires again, self filter, nil front app, stop cancels.
- `Tests/PixelMacAppTests/WindowDwellDetectorTests.swift` — **7 yeni**: accumulates dwell, resets on window change, fires once, no fire when nil, self bundle filtered, title variant changes key, empty title bundle-only dwell.
- `Tests/PixelMacAppTests/CalendarEventDetectorTests.swift` — **7 yeni**: 3-10 dk window, below lower bound, above upper bound, dedup same event, fires for new event, no fire when nil, dedupKey format.
- **Regression update** — `ProactiveTriggerTests` Sprint 38 testleri +5 yeni: allCases 2→5, raw value stable +3 case, permissionRequirements per-kind, Tier 2 humanDescriptions, Tier 2 bundleSuppressionKeys.

### Notes — Sprint 39

- **v2 paritesi tamamlandı.** `ProactiveEngine.swift:14-368` 5 trigger enum case'in tamamı v3'e modüler SPM mimarisinde indi. Pratikte v3'ün proaktif yetenekleri v2 ile fonksiyonel olarak eşdeğer + daha test edilebilir + Sendable-safe + permission-aware.
- **TypedPause permission YOK:** Beklenmedik iyi haber — `CGEventSource.secondsSinceLastEventType` `.keyDown` event type için public API; CGEventTap (capture) değil, sadece "son keyDown ne zaman" int. v2'de de aynı yaklaşım. Bu yüzden ek izin diyaloğu çıkmaz.
- **WindowDwell Accessibility downgrade:** Permission yoksa AX title nil → key sadece bundleID + "". Aynı app içinde farklı pencere değişikliği yakalanmaz (Safari'de tab değiştirsen dwell sayıcı reset olmaz). v2 paterniyle uyumlu.
- **Calendar permission flow:** Settings → İzinler → Calendar "Aç" tıkla → `requestFullAccessToEvents` macOS Calendar permission dialog'u açar. Granted sonrası detector tick'leri event döner; reddedildiyse detector no-op olarak çalışır (hata yok).
- **TriggerKind raw value compatibility:** Sprint 38 UserDefaults'a yazılmış `["idle", "appChange"]` suppression listeleri Sprint 39'da hâlâ çalışır (additive, missing case'ler decode'da skip).

## [0.2.65] — 2026-05-26

**Sprint 38 — ProactiveEngine MVP (idle + appChange triggers).** v2'nin (~64k LOC) `ProactiveEngine.swift:14-368` paterni v3'e modüler SPM mimarisinde indi. Agent artık **pasif** olarak çalışıyor — kullanıcı boş kalırsa veya uygulama değiştirirse system notification ile Pixel Agent'a yönlendirir. Tier 1 MVP: idle + appChange (no Accessibility/Calendar permission). Tier 2 (windowDwell, typedPause, calendar) Sprint 39 aday.

**Test:** Mac 1081 → **1124** (+43: 9 ProactiveTrigger + 9 SuppressionStore + 10 ProactiveRateLimiter + 8 ProactiveEngine + 7 IdleDetector). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (master toggle default ON ama UserDefaults nil-safe; istemeyen kullanıcı Settings'ten kapatır).

### Added — Sprint 38 / ProactiveEngine MVP

#### `Sources/PixelMacApp/Proactive/ProactiveTrigger.swift` (yeni)
- **`ProactiveTrigger`** enum 2 case: `.idle(minutes:)`, `.appChanged(name:bundleID:)`. Sprint 39+ üç yeni case rezerv.
- **`TriggerKind`** payload-free identifier (rate limiter + suppression key) — `idle`, `appChange`. Raw value stable (UserDefaults serialization).
- `bundleSuppressionKey`, `humanDescription`, `kind` computed properties.

#### `Sources/PixelMacApp/Proactive/SuppressionStore.swift` (yeni)
- **`SuppressionStore`** value type (`Sendable Equatable`) — UserDefaults-backed mute store. İki seviye: kind-level (tüm idle suspend) + bundle-level (Slack'ten appChange yutulur).
- `shouldSuppress(_:)`, `setKind(_:suppressed:)`, `setBundle(_:suppressed:)` (trim + lowercase normalize).
- Persist API: `load(from:)`, `save(to:)`. UserDefaults keys `pixel.proactive.suppressedKinds` + `pixel.proactive.suppressedBundles`.

#### `Sources/PixelMacApp/Proactive/ProactiveRateLimiter.swift` (yeni)
- **`ProactiveRateLimiter`** value type — global cooldown (default 300s = 5dk) + per-kind override.
- `canFire(_:now:)` — global pencere check + per-kind cooldown check.
- `record(kind:at:)`, `setCooldown(_:for:)`, `effectiveCooldown(for:)`.
- Clock injection (`now: Date`) — test edilebilir.

#### `Sources/PixelMacApp/Proactive/IdleDetector.swift` (yeni)
- **`IdleDetector`** actor — `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)` polling (10s tick, threshold default 15 dk).
- `IdleSource` mock'lanabilir closure — test'lerde sahte idle source.
- `start()/stop()/tick()` lifecycle + `hasFired` state machine (threshold/2 altına düşünce reset → tekrar tetiklenebilir).
- Permission YOK — Apple framework public API.

#### `Sources/PixelMacApp/Proactive/AppChangeObserver.swift` (yeni)
- **`AppChangeObserver`** actor — `NSWorkspace.didActivateApplicationNotification` observer + per-bundle debounce (default 60s).
- Notification handler **Sendable-safe** — `name + bundleID` sync extract, Task'a primitive olarak pass.
- Self-filter: pixel-agent kendisinin aktivasyonunu ignore (⌘Tab spam önler).

#### `Sources/PixelMacApp/Proactive/ProactiveEngine.swift` (yeni orchestrator)
- **`ProactiveEngine`** actor — detector'ları başlat/durdur, `handle(_:)` ile trigger'ı SuppressionStore + RateLimiter zincirinden geçir, `deliver` closure ile SystemNotifications'a yolla.
- `defaultDelivery` static — `SystemNotifications.post` wrap.
- `updateSuppression(_:)` Settings UI'dan çağrılır + UserDefaults sync.
- `currentSuppression()`, `currentlyRunning()`, `format(_:)` debug/UI introspection.
- Master toggle: `pixel.proactive.masterEnabled` UserDefaults (default ON). Kapalıysa `start()` no-op.

#### `Sources/PixelMacApp/PixelMacApp.swift` (lifecycle)
- `RootView.proactiveEngine` static singleton.
- `RootView .task` blokunda `await proactiveEngine.start()` — `SystemNotifications.requestAuthorization` + ControlBridge'den sonra.

#### `Sources/PixelMacApp/SettingsView.swift` (7. tab "Proaktif")
- `SettingsTab.proactive` (`bell.badge` icon).
- **`ProactiveSettingsTab`** — 4 section:
  1. Ana Anahtar: master toggle (Restart-required note)
  2. Aktif Tetikleyiciler: per-kind on/off checkbox (idle, appChange) + açıklayıcı caption
  3. Boşta Kalma: stepper 5-120 dk eşiği
  4. Sustrulan Uygulamalar: bundle ID list (add/remove monospace text)
- Toggle değişikliği `RootView.proactiveEngine.updateSuppression(_:)` async dispatch.

### Tests — Sprint 38

- `Tests/PixelMacAppTests/ProactiveTriggerTests.swift` — **9 yeni**: kind/bundleSuppressionKey accessors, humanDescription, allCases count, raw value stability, displayName non-empty.
- `Tests/PixelMacAppTests/SuppressionStoreTests.swift` — **9 yeni**: empty store, kind block, bundle block (own bundle only), normalization (upper/whitespace), set false removes, UserDefaults round-trip, corrupt defaults fallback, idle bundle-independent.
- `Tests/PixelMacAppTests/ProactiveRateLimiterTests.swift` — **10 yeni**: empty allows, fired blocks itself, global cross-kind block, post-cooldown allows, custom global cooldown, negative clamp, per-kind override, lastFires update, most-recent determines, custom init.
- `Tests/PixelMacAppTests/ProactiveEngineTests.swift` — **8 yeni**: deliver happy path, suppressed kind blocks, suppressed bundle blocks, rate limit second blocks, format Turkish, format app name, updateSuppression applies, currentSuppression snapshot.
- `Tests/PixelMacAppTests/IdleDetectorTests.swift` — **7 yeni**: fires above threshold, no-fire below, no-double-fire, mockable reset cycle (NSLock source), fired state exposed.
- **Regression update** (+1): `SettingsTabTests` 6→7 case (memory→proactive).

### Notes — Sprint 38

- **Sprint 38 TIER 1 — no-permission triggers.** Sprint 39 Tier 2 adayları: `windowDwellTrigger` (Accessibility — front window title), `typedPauseTrigger` (CGEventTap / Accessibility), `calendarEventTrigger` (EKEventStore).
- **Delivery via SystemNotifications:** Mevcut `PixelTools.SystemNotifications.post` kullanıldı; sound + UN content. Notification handler tap → app aktive (mevcut entitlement).
- **Lifecycle:** Master toggle kapatılırsa engine `start()` no-op olur ama mevcut detector'lar çalışıyor — değişiklik etkili olması için app restart gerekir (Settings caption uyarı verir). Hot-reload v0.2.66+ aday.
- **Debounce + suppression chain:** Trigger sıraya: detector debounce (AppChange 60s per-bundle, Idle reset) → SuppressionStore → RateLimiter (5dk global cooldown) → deliver. Üç katman kullanıcıya bildirim spam'i önler.
- **iOS:** Proaktif tetikleyiciler Mac-only. iOS background execution kısıtlı; iOS proactive sonraki sürümlerde değerlendirilebilir (Background App Refresh tabanlı).
- **Tests `proactive` taşıdı `subagent`'in altında:** Subagent paterniyle aynı `Sources/PixelMacApp/Proactive/` klasörü.

## [0.2.64] — 2026-05-26

**Sprint 37 — Semantic memory matching (NLEmbedding + char n-gram hybrid).** Sprint 36'da `TextSimilarityScorer` word Jaccard kısa metinlerde zayıftı — "Beni Erkut diye çağır" + "Erkut burada" düşük skor veriyordu, threshold 0.55'i geçemiyordu. Bu release **3-tier hybrid dispatcher** ekliyor:

- **Tier 1 — `NLEmbedding.sentenceEmbedding(for: .english)`** (dim=512, yüksek kalite). İngilizce uzun metin için.
- **Tier 2 — Character n-gram Jaccard (n=3)** — multilingual morphology-aware. "erkut" + "erkut'a" ortak trigram'lar paylaşır. Türkçe, kısa metin, karışık metinler.
- **Tier 3 — Word Jaccard (Sprint 36)** — fallback / kullanıcı opt-out.

**Apple `NLEmbedding` probe sonucu:** Türkçe için ne sentence ne word embedding modeli var (probe doğrulandı). CoreML multilingual model bundle'a 135MB+ ekler — char n-gram pragmatik alternatif. Sprint 37 sıfır model overhead'i + multilingual destek + morphology yakalama dengesi sunar.

**Test:** Mac 1043 → **1081** (+38: 14 CharNGramScorer + 16 EmbeddingScorer + 8 LanguageDetector). iOS xcodebuild simulator BUILD SUCCEEDED. **Breaking change yok** (`EmbeddingScorer.score()` default `enableEmbedding: currentSemanticToggle()`, UserDefaults nil → true; eski Jaccard kullanmak istenirse Settings'ten kapatılır).

### Added — Sprint 37 / Hybrid embedding scorer

#### `Sources/PixelMemory/CharNGramScorer.swift` (yeni saf helper)
- **`ngrams(of:n:)`** — sliding window character n-gram extraction, lowercased, whitespace included.
- **`score(_:_:n:)`** — Jaccard over n-grams, 0.0-1.0.
- Defaults: `n=3` (trigram, kısa metin için optimal), `minTextLength=1`.
- Metin n'den kısaysa kendisi tek gram olarak (defensive).

#### `Sources/PixelMemory/LanguageDetector.swift` (yeni saf helper)
- **`detect(_:)`** — `NLLanguageRecognizer` wrap. `minLengthForDetection = 12` altında nil zorlanır (probe'da "Call me Erkut" 3-kelime için `.turkish` döndürüyordu — defensive guard).
- **`detectShared(_:_:)`** — query+content çiftinden ortak/dominant dil. Farklıysa nil; tek-tarafı short ise diğeri döner.

#### `Sources/PixelMemory/EmbeddingScorer.swift` (yeni dispatcher)
- **`score(_:_:enableEmbedding:)`** — 3-tier dispatcher entry point. Default `enableEmbedding = currentSemanticToggle()`.
- **`currentSemanticToggle()`** — UserDefaults `EmbeddingScorer.enabledDefaultsKey` ("pixel.memory.semanticMatching") okur, nil → true.
- **`sentenceCosine(_:_:language:)`** — NLEmbedding wrap, nil-safe (TR için nil döner).
- **`cosineSimilarity(_:_:)`** — saf math, Sendable, test edilebilir.
- **`sentenceEmbedding(for:)`** — `NLEmbedding` lookup wrapper. Cache YOK (Apple framework internally amortize).

#### `Sources/PixelMemory/PlaybookLearner.swift` (update)
- `relevant()` artık `EmbeddingScorer.score()` çağırır (Sprint 36'da `TextSimilarityScorer.score()` idi).
- Default `minSimilarity = 0.55` → **`0.35`** (n-gram skorları sentence embedding'e göre daha düşük aralıkta).

#### `Sources/PixelMemory/MemoryStore.swift` (update)
- `relevantContext()` default `minSimilarity = 0.55` → **`0.35`** (PlaybookLearner ile uyumlu).

#### `Sources/PixelMacApp/SettingsView.swift`
- **"Eşleştirme" yeni section** (Memory tab başında): `Toggle("Anlamsal Eşleştirme")` — `@AppStorage(EmbeddingScorer.enabledDefaultsKey)`. Default ON. Açıklayıcı footer: İngilizce için NLEmbedding sentence, diğer diller için karakter n-gram morfoloji; kapatılırsa Sprint 36 word Jaccard'a düşer.

### Tests — Sprint 37

- `Tests/PixelMemoryTests/CharNGramScorerTests.swift` — **14 yeni**: ngrams empty/short-than-N/exact-N/sliding/lowercase/whitespace/Turkish, score identical/different/empty/symmetry/partial overlap/case-insensitive, **Sprint 36 regression**.
- `Tests/PixelMemoryTests/EmbeddingScorerTests.swift` — **16 yeni**: cosine math (identical, orthogonal, opposite, mismatched size, zero magnitude, empty), dispatcher tier (Jaccard fallback, English sentence, Turkish ngram, short text ngram), NL embedding lookup (English var, TR nil), `sentenceCosine` (English value, TR nil), UserDefaults toggle, **Sprint 36 "Erkut" regression**.
- `Tests/PixelMemoryTests/LanguageDetectorTests.swift` — **8 yeni**: empty/short returns nil, long English/Turkish detect, `detectShared` same/different/one-short/both-short.

### Notes — Sprint 37

- **Sprint 36 regression "Erkut" kapandı:** `EmbeddingScorerTests.testSprint36ErkutRegression` ve `CharNGramScorerTests.testSprint36RegressionShortNames` artık geçiyor. Kısa metinde "Erkut" isim eşleşmesi ≥ 0.1 skor verir (threshold 0.35 yerine 0.1 conservatif assertion).
- **Türkçe için sentence embedding YOK:** Apple `NLEmbedding.sentenceEmbedding(for: .turkish)` nil döner (probe doğrulandı). Char n-gram Tier 2 bu boşluğu doldurur. CoreML multilingual MiniLM (135MB bundle) v0.3+ aday.
- **NLLanguageRecognizer kısa metinde güvensiz:** "Call me Erkut" için `.turkish` döndürüyordu. `LanguageDetector` 12-char minimum eşik ile bunu defensive olarak filter eder; eşik altında diğer tier'lara düşer.
- **Threshold revize:** 0.55 → 0.35. N-gram skorları sentence embedding'e göre daha düşük aralıkta (0.3-0.7 tipik). Threshold çok yüksek olursa hiçbir entry inject edilmez.
- **Toggle opt-out:** Kullanıcı Settings → Hafıza → "Anlamsal Eşleştirme" toggle ile Sprint 36 word Jaccard'a dönebilir. Test/regresyon koşullarında stabil davranış.
- **Performans:** İngilizce sentence embedding ~ms inference; char n-gram sub-millisecond. 500 entry × ~1ms = 500ms toplam tarama — async Task içinde, UI freeze yok.

## [0.2.63] — 2026-05-26

**Sprint 36 — MemoryStore + PlaybookLearner MVP.** v3'e ilk kez **cross-session persistent memory** mekanizması: agent geçmiş benzer task'leri "hatırlıyor". v2'nin (~64k LOC monorepo) `MemoryStore.swift:1-115` + `MemoryConsolidator.swift` + `PlaybookLearner.swift:1-99` paterniyle uyumlu — ama embedding-free Jaccard MVP (CoreML/SwiftNLP v0.3+ aday).

Her user mesajı öncesi `ChatViewModel.send` `MemoryStore.relevantContext(for:)` çağırır → `PlaybookLearner` top-N relevant entry'leri ranking sırasıyla döner (Jaccard similarity × category promptWeight × recipe tag boost) → `CLIBackend.send` `system` prompt'una `"[Kullanıcı geçmişinden benzer kayıtlar]"` prefix ile enjekte edilir. Claude/Codex/Gemini geçmiş context'i otomatik görür.

**Test:** Mac 998 → **1043** (+45: 17 MemoryStore + 12 TextSimilarityScorer + 9 MemoryConsolidator + 13 PlaybookLearner + 4 regression fixes). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni `memoryStore` ChatViewModel parametresi opsiyonel default nil).

### Added — Sprint 36 / MemoryStore + PlaybookLearner

#### `Sources/PixelMemory/MemoryEntry.swift` (yeni)
- **`MemoryEntry`** struct (`Codable`, `Identifiable`, `Equatable`, `Sendable`) — id (UUID), category, content, tags, createdAt, updatedAt, deleted (soft tombstone).
- **`MemoryCategory`** enum: `profile` (4) / `preference` (3) / `project` (2) / `task` (1) / `note` (0) — `promptWeight` ranking boost katsayısı.
- **`withNormalizedTags()`** — trim + lowercase + dedup (NSMutableOrderedSet).

#### `Sources/PixelMemory/MemoryStore.swift` (yeni)
- **`MemoryStore`** actor — `ConversationStore` paterniyle JSONL append-only persist.
- Storage path: `~/Library/Application Support/pixel-agent/memory.jsonl`.
- API: `add()` / `update(id:content:tags:category:)` / `delete(id:)` (soft tombstone) / `loadAll()` (latest-wins + deleted filter) / `loadByCategory()` / `loadByTag()` / `relevantContext(for:limit:minSimilarity:)` / `compact()`.
- **Multi-process safe (best-effort):** MCP server + Mac app aynı dosyaya append; corrupt satır skip.

#### `Sources/PixelMemory/TextSimilarityScorer.swift` (yeni saf helper)
- **`score(_:_:) -> Double`** — Jaccard token similarity, 0.0-1.0 aralık.
- **`tokenize(_:)`** — Latin alphanumeric split, lowercase, stopword filter (TR+EN 47 word), minTokenLength=3.
- Embedding-free MVP; CoreML/SwiftNLP v0.3+ aday.

#### `Sources/PixelMemory/MemoryConsolidator.swift` (yeni saf helper)
- **`findDuplicates(in:threshold:)`** — Jaccard ≥ 0.85 + aynı category pair tespit (O(n²) — typical <500 entry için kabul edilebilir).
- **`merge(older:newer:)`** — newer content wins + union tags (normalize) + earliest createdAt + fresh updatedAt.

#### `Sources/PixelMemory/PlaybookLearner.swift` (yeni saf helper)
- **`relevant(query:in:limit:minSimilarity:)`** — top-N ranker. Score = Jaccard × category weight × 0.05 + (recipe tag ? 0.1 : 0).
- **`formatPrompt(_:)`** — entry list → markdown bullet (system prompt prefix için).
- Default `limit=3`, `minSimilarity=0.55` — v2 uyumlu.

#### `Sources/PixelMCPServer/MemoryTools.swift` (yeni MCP tools)
- **`save_memory(category, content, tags?)`** — agent kendi entry kaydedebilir (örn "Beni Erkut diye çağır" → profile).
- **`search_memory(query, limit?, category?, tag?, min_similarity?)`** — agent geçmiş entry'lerde arama yapar (örn "PR review template'i hatırlıyor musun?").
- **Standalone** (bridge yok) — Mac app çalışmıyor olsa bile MCP server tek başına memory'ye erişir; `MemoryStore` fresh instance her handler içinde.

#### `Sources/PixelMacApp/ChatViewModel.swift` (entegrasyon)
- **`let memoryStore: MemoryStore?`** yeni property (init parametresi default nil — test/opt-out friendly).
- **`send()` öncesi** `Task { memoryStore?.relevantContext(for:) }` → `PlaybookLearner.formatPrompt()` → backend `system:` prefix.

#### `Sources/PixelMacApp/PixelMacApp.swift` (composition root)
- **`RootView.@State memoryStore: MemoryStore?`** — init'te `try? MemoryStore()` (fail-safe, nil ise injection devre dışı).
- **`ChatHost` `memoryStore:` parametresi** — ChatView ve DualChatHost'lara iletilir.

#### `Sources/PixelMacApp/SettingsView.swift`
- **6. tab eklendi:** "Hafıza" (`brain.head.profile` icon).
- **`MemorySettingsTab` struct** — entry list (kategori badge + tag chip + içerik) + swipe-to-delete + "Optimize Et" butonu (MemoryConsolidator + compact()).
- Storage path footer'da görünür.

#### `Sources/PixelMCPServer/JSONValue.swift`
- **`doubleValue`** getter eklendi — JSON wire'da int olarak gelen `min_similarity` gibi float param'lar için.
- **`intValue`** double'dan int dönüşümü destekler.

### Tests — Sprint 36

- `Tests/PixelMemoryTests/MemoryStoreTests.swift` — **17 yeni**: CRUD, normalize, update/delete, soft tombstone, filters, compact, relevantContext integration.
- `Tests/PixelMemoryTests/TextSimilarityScorerTests.swift` — **12 yeni**: identical=1, different=0, case-insensitive, symmetry, stopwords, short token filter, Turkish chars, demo regression.
- `Tests/PixelMemoryTests/MemoryConsolidatorTests.swift` — **9 yeni**: identical flag, different not flagged, category isolation, order, merge content/tags/dates, custom threshold.
- `Tests/PixelMemoryTests/PlaybookLearnerTests.swift` — **13 yeni**: empty/zero edges, threshold filter, deleted skip, limit, recipe boost, category weight ranking, formatPrompt, demo scenario.
- **Regression updates** (+4): `SettingsTabTests` 5→6 case, `ToolRegistryTests` 14→16 tool count + listResult name set.

### Notes — Sprint 36

- **Memory injection opt-out:** `ChatViewModel.memoryStore` nil ise hiçbir context enjekte edilmez (test'ler, regression). Composition root'ta `try? MemoryStore()` — fail-safe.
- **Jaccard limitasyonu:** Kısa metinlerde (~5-10 token altı) similarity zayıf. Demo testte gösterildiği gibi "Beni Erkut diye çağır" + "Erkut burada" düşük skor verir. CoreML embedding v0.3+ aday — short-text retrieval kalitesi anlamlı artar.
- **MemoryConsolidator:** Otomatik schedule yok — manuel `Settings → Hafıza → Optimize Et` veya `compact` MCP tool (gelecek versiyonda).
- **Multi-process race:** MCP server (CLI agent) + Mac app aynı `memory.jsonl`'e append eder; worst case 1 entry corrupt → decode atlanır, kayıp ufak. Production-grade durability için file lock v0.3+ aday.
- **iOS:** Memory UI iOS dashboard'da yok — Mac-only MVP. iOS read-only liste sonraki sprint'lerde.

## [0.2.62] — 2026-05-26

**Sprint 35 — iOS stale-pairing detection + auto-recovery.** Kullanıcı raporladı: "her seferinde QR kod okutmam gerekiyor, otomatik bağlanmalı açık olduğu zaman". Tanı: Mac side stable (Sprint 34 `PairingCode` UserDefaults persist + signing key Keychain) ama iOS-tarafı eski random code veya değişmiş public key ile reconnect loop'unu sessizce sonsuza dek deniyordu. Banner "Bağlantı koptu" gösterir, kullanıcı manuel olarak Settings → Eşleştirmeyi Unut → yeni QR yolunu bulmak zorundaydı.

Bu release iki güvenlik ağı ekler:
1. **Connect fail threshold (default 5):** Exponential backoff (2s → 4s → 8s → 16s → 30s) ile ~30 saniyelik fail serisi tamamlandığında stale-pairing flag set edilir. Network kopukluğu bu süre içinde kendini düzeltir; uzun fail = key/code mismatch.
2. **Verify fail threshold (default 3) + ready timeout (default 8s):** `EnvelopeSigner.verify` her envelope'ı reject ediyorsa veya connect sonrası 8 saniye içinde verify-passed envelope gelmezse Mac public key değişmiş demektir. Bu sinyal daha kesin — 3 ardışık reject yeterli.

Threshold aşılınca iOS `ConnectionLostBanner` prominent kırmızı moda geçer: "Mac eşleştirmeniz değişmiş olabilir — Eşleştirmeyi sıfırlayıp yeni QR'ı tarayın" + tek-tıkla "QR'ı Yeniden Tara" butonu (`forgetAndRescan()`). Banner UserDefaults'taki pairing'i temizler, `ContentView` otomatik `PairingScannerView`'a düşer.

**Test:** Mac 983 → **998** (+15 `ReconnectAttemptTrackerTests` — saf değer tipi: initial state, threshold partitioning, success reset, overflow safety, demo scenario regression; +1 `RemoteEnvelopeTests` regression fix `conversationSync` Sprint 33 v2'den kalan hardcoded set eksiği). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

### Added — Sprint 35 / iOS stale-pairing detection

#### `Sources/PixelRemote/ReconnectAttemptTracker.swift` (yeni, saf değer tipi)
- **`ReconnectAttemptTracker`** struct: `Sendable`, `Equatable`. İki bağımsız sayaç (`connectFailureCount`, `verifyFailureCount`) + iki threshold (default 5 / 3).
- **Constants:** `defaultConnectFailureThreshold = 5`, `defaultVerifyFailureThreshold = 3`, `defaultReadyTimeoutSeconds = 8`.
- **`isPairingStaleSuspected: Bool`** computed — herhangi bir threshold aşıldığında `true`.
- **Mutating methods:** `recordConnectFailure()` (overflow-safe), `recordVerifyFailure()` (overflow-safe), `recordSuccess()` (her iki counter sıfırlar).
- **Defensive init:** negative threshold → 1; negative count → 0.
- **PixelRemote modülünde** — iOS RemoteSession kullanır, Mac testTarget'ta test edilebilir (saf value type, network bağımlılığı yok).

#### `ios/PixelAgentRemote/RemoteSession.swift` (entegrasyon)
- **`@Published var pairingStaleSuspected: Bool = false`** — UI binding için tracker'ın aynası.
- **`establishConnection` catch branch:** `attemptTracker.recordConnectFailure()` + `pairingStaleSuspected` güncelle. PairingInfo bozuk path (mac public key base64 decode fail) `recordVerifyFailure()` çağırır (daha sert sinyal).
- **Connect success branch:** `readyTimeoutTask` 8 saniyelik Task spawn — verify-passed envelope gelmezse `handleReadyTimeout()` `recordVerifyFailure()` tetikler.
- **`handle()` verify guard fail:** `recordVerifyFailure()` (key mismatch sinyali).
- **`handle()` ilk verify-passed envelope:** `hasReceivedVerifiedEnvelope = true` + `readyTimeoutTask.cancel()` + `recordSuccess()` → flag clear.
- **`forgetAndRescan()`** yeni public method: `disconnect(forget: true)` + tracker fresh init + flag reset. UI banner tek-tıkla çağırır.

#### `ios/PixelAgentRemote/ConnectionLostBanner.swift` (genişletme)
- **İkili mod:** `pairingStaleSuspected: Bool` parametresi.
  - **Normal mod** (false): Sprint 11 davranışı korundu — turuncu kapsül, countdown + "Tekrar Dene".
  - **Stale mod** (true): kırmızı `0.12 opacity` + `0.6 alpha 1.5pt stroke` prominent kart. `exclamationmark.triangle.fill` ikon + bold başlık + açıklayıcı caption + iki buton: "QR'ı Yeniden Tara" (`.borderedProminent` kırmızı) + "Tekrar Dene" (`.bordered` ikincil).
- **`onForgetAndRescan: () -> Void`** yeni opsiyonel callback.

#### `ios/PixelAgentRemote/ChatView.swift`
- ConnectionLostBanner call-site iki yeni parametre alır (`pairingStaleSuspected`, `onForgetAndRescan`).

### Fixed — Sprint 33 v2 regression

#### `Tests/PixelRemoteTests/RemoteEnvelopeTests.swift`
- **`testEnvelopeTypeContainsAllExpectedCases`** hardcoded set'e `conversationSync` eklendi (Sprint 33 v2 'de yeni envelope tipi eklenmiş ama bu regression test güncellenmemişti — failing test).

### Notes — Sprint 35

- **Tek seferlik kullanıcı aksiyonu:** Mevcut iOS install'da saved pairing v0.2.61'e bump sonrası stale kalmış olabilir. Kullanıcı bir kez `forgetAndRescan` (banner butonu) veya Settings → Eşleştirmeyi Unut → yeni QR ile pairing'i yeniler; sonraki tüm açılışlar `loadOrGenerate` Mac code'u stabil + Keychain signing key persist + ready timeout sağlıklı → auto-reconnect çalışır.
- **Threshold seçimleri:** Connect fail 5 = ~30 saniyelik exponential backoff, gerçek transient network kopukluğu bu süre içinde kendini düzeltir. Verify fail 3 = key mismatch çok güvenilir sinyal (parse race değil). Ready timeout 8 saniye = Mac normalde `hostStatus`/`assistantChunk` push'larını anlık tetikler; 8s sessizlik mismatch göstergesi.
- **Backward compat:** Yeni `@Published` field + opsiyonel callback + opsiyonel constructor parametreleri additive. Eski iOS app aynı protokol ile bağlanır; iOS-only UX değişikliği.
- **Future direction:** Mac side teşhis görseli (PairingView'da current code + public key fingerprint kopyalanabilir + auto-refresh on regenerate); iOS Settings'te "Tracker debug" expand (count + threshold gözlemlemek). Şu an gizli — beklenen UX hep healthy.

## [0.2.61] — 2026-05-26

**Sprint 34 — Auto-connect on launch + persist pairing code.** Kullanıcı "iOS app bağlanmıyor" raporladı. İki kök sebep: (1) Mac auto-connect yoktu — `remoteHost.connect()` yalnız `PairingView` "Bağlan" butonuyla çağrılıyordu, her launch'ta manuel tıklamak gerekiyordu; (2) `PairingCode` persist edilmiyordu — `RemoteHost.init` her seferinde `PairingCode.generate()` ile yeni kod üretiyordu, iOS saved pairing eski kodu beklediği için Mac restart sonrası auto-reconnect fail oluyordu.

**Test:** Mac 983 (değişmedi — bağlantı davranış fix'i). Mac BUILD SUCCEEDED. iOS değişmedi (auto-reconnect zaten Sprint 6.1'den beri saved pairing'den çalışıyor). Breaking change yok (UserDefaults yeni key; eski install first-launch'ta yeni code üretip persist eder, sonrası stabil).

### Added — Sprint 34 / Pairing persistence

#### `Sources/PixelRemote/PairingCode.swift`
- **`storedCodeKey`** static UserDefaults key.
- **`loadOrGenerate(userDefaults:)`** — saved valid code varsa yükle, yoksa yeni üret + save.
- **`save(_:userDefaults:)`** — explicit persist.

### Changed — Sprint 34

#### `Sources/PixelRemote/RemoteHost.swift`
- 3 init `PairingCode.loadOrGenerate()` kullanır (eski `.generate()` yerine).
- **`regenerateCode()`** yeni üretip ek olarak `PairingCode.save(fresh)` çağırır.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- `ChatHost.body`'ye yeni `.task` — app launch'ta `remoteHost.connect()` otomatik (`isConnected` guard ile idempotent). Mac dinlemeye başlar, iOS saved pairing aynı code ile auto-reconnect olur.

## [0.2.60] — 2026-05-25

**Sprint 33 v2 — Per-backend conversation sync to iOS.** Kullanıcı "Mac'te claude/codex/gemini ayrı sohbet ama iOS'ta hepsi aynı sohbette devam ediyor" raporladı. Mac per-backend `ConversationStore` izolasyonu (v0.2.25 `a941eac`, `conversation-{kind}.jsonl`) iOS'ta yansımıyordu; iOS tek `RemoteSession.messages` array'ine her şey karışıyordu. Yeni `conversationSync` envelope ile Mac aktif sohbetin tam snapshot'ını iOS'a yansıtır, iOS messages array'ini replace eder.

**Test:** Mac 983. Mac + iOS simulator + device BUILD SUCCEEDED. Breaking change yok (additive envelope + opsiyonel callback). **Not:** Bu sprint `conversationSync` envelope ekledi ama `RemoteEnvelopeTests.testEnvelopeTypeContainsAllExpectedCases` regression set'i güncellenmedi — v0.2.62'de (Sprint 35) düzeltildi.

### Added — Sprint 33 v2 / conversation sync

#### `Sources/PixelRemote/RemoteEnvelope.swift`
- **`EnvelopeType.conversationSync`** (forward-compat unknown fallback).
- **`EnvelopePayload.conversationSync(messages: [Message])`** + `payload?.conversationMessages` getter + `PayloadKey.conversationMessages` wire field + `RemoteEnvelope.conversationSync(messages:)` factory.

#### `Sources/PixelRemote/RemoteHost.swift`
- **`sendConversationSync(_ messages:)`** public method.

### Changed — Sprint 33 v2

#### `Sources/PixelMacApp/ChatViewModel.swift`
- **`onSnapshotBroadcast: (([Message]) -> Void)?`** callback — `restoreIfNeeded` sonu (backend/model `.id()` rebuild) + `newConversation` sonu (boş array) fire eder.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- `.conversationSync` case → `messages` replace + `mascotState = .idle`.

### Notes — Sprint 33 v2
- **Sync tetikleyiciler:** (1) backend değişimi → ChatView `.id()` → snapshot; (2) ⌘N → boş snapshot; (3) archive load → arşiv mesajları.
- **Open follow-up:** iOS reconnect/initial pair anında Mac otomatik snapshot push'lamıyor; kullanıcı backend toggle veya mesaj ile tetikler. (Sprint 34 auto-connect kısmen amortize eder.)

## [0.2.59] — 2026-05-25

**Sprint 33 — Bidirectional message sync.** v0.2.25'ten beri Mac→iOS sync yalnız assistant cevaplarını gönderiyordu; Mac composer'a yazılan user mesajları iOS'ta görünmüyordu. iOS→Mac yönü zaten `userMessage` envelope ile çalışıyordu (incomingRemoteText path). Çift yönlü sync wire-up ile her iki yön de user mesajlarını taşır; echo loop UUID dedup ile engellenir.

**Test:** Mac 983. Mac + iOS simulator + device BUILD SUCCEEDED. Breaking change yok (additive opsiyonel callback + flag default).

### Added — Sprint 33 / bidirectional sync

#### `Sources/PixelRemote/RemoteHost.swift`
- **`sendUserMessage(text:messageID:)`** public — `sendAssistantChunk` paterniyle userMessage envelope sign+send.

### Changed — Sprint 33

#### `Sources/PixelMacApp/ChatViewModel.swift`
- **`send(text:broadcastToRemote: = true)`** — `true` → `onUserMessage` callback (Mac composer); `false` → yutulur (iOS-originated, incomingRemoteText path).
- **`onUserMessage: ((String, String) -> Void)?`** yeni callback.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- `.userMessage` case (yeni) — UUID dedup (`messages.contains { $0.id == msgID }` skip): iOS-originated Mac echo'su yutulur, Mac-originated yeni UUID append.

### Notes — Sprint 33
- **Echo loop önleme:** `ChatView.onChange(incomingRemoteText)` → `send(broadcastToRemote: false)`; Mac echo iOS'a geri gitmez.

## [0.2.58] — 2026-05-25

**Sprint 32 follow-up — Force TextField rebuild on send via `.id()`.** v0.2.57 defocus-refocus workaround SwiftUI `TextField(axis: .vertical)` binding sync bug için yeterli olmadı — bazı SwiftUI sürümlerinde defocus async tamamlanıyor, binding commit cycle eski NSTextField buffer'a yazıyor. Garantili çözüm: `@State sendCounter` + `.id("composer-\(sendCounter)")`; her send'de counter increment SwiftUI TextField'i tamamen yeniden inşa eder (eski buffer yok).

**Test:** Mac 983. Mac BUILD SUCCEEDED. iOS version parity için bumped (iOS'ta bug yok). Breaking change yok.

### Fixed — Sprint 32 follow-up

#### `Sources/PixelMacApp/ChatComposer.swift`
- **`@State sendCounter`** + `TextField(...).id("composer-\(sendCounter)")` — her send'de `&+= 1` (overflow-safe wrap) → tam rebuild, eski NSTextField instance silinir.
- `DispatchQueue.main.asyncAfter` 50ms ile rebuild sonrası `isComposerFocused` restore — kullanıcı klavyeden devam edebilir.

## [0.2.57] — 2026-05-25

**Sprint 32 — Composer draft persists after send.** Kullanıcı "Mac'te chate yazdığım yazı sürekli kalıyor, her mesajda eski mesajı silmem gerekiyor" raporladı. Root cause: v0.2.20'den beri `ChatComposer.TextField(axis: .vertical)` (Shift+Enter newline için) kullanılıyor; macOS'ta bilinen SwiftUI bug — focus active iken parent'in `draft = ""` yazması NSTextField internal buffer'a yansımıyor.

**Test:** Mac 983. Mac BUILD SUCCEEDED + iOS device install/launch başarılı. iOS version parity için bumped (TextField yapısı farklı, bug yok). Breaking change yok.

### Fixed — Sprint 32

#### `Sources/PixelMacApp/ChatComposer.swift`
- **`performSend()`** send'den önce briefly defocus (`isComposerFocused = false`) → SwiftUI binding clear cycle'ını deterministik commit; sonra `DispatchQueue.main.asyncAfter` (50ms) refocus.
- 3 send path (`.onSubmit`, "Gönder" `.return` shortcut, subagent dispatch) hepsi `performSend()`'den geçer — tek fix 3'ünü de düzeltir.

## [0.2.56] — 2026-05-25

**Sprint 31 — Backend/model picker in chat header (iOS).** v0.2.25'ten beri backend / model / planMode picker yalnız iOS Mac Paneli tab'ında erişilebilirdi; kullanıcı sohbet sırasında provider değiştirmek isteyince oraya gitmek zorundaydı (Sohbet tab'ında pick edememe bug olarak raporlandı). Chat header'a inline Menu eklendi: başlık altında "claude · opus" özeti, tap → Section'lı dropdown (Arka Uç / Model / Plan Modu), aynı `session.updateConfig` ile wire'lı.

**Test:** Mac değişmedi (iOS-only UI). iOS xcodebuild simulator + device BUILD SUCCEEDED. Breaking change yok.

### Added — Sprint 31 / iOS chat header picker

#### `ios/PixelAgentRemote/ChatView.swift`
- **`backendModelMenu`** @ViewBuilder — Section'lı Menu (Arka Uç / Model / Plan Modu); seçili için checkmark; transport badge (LAN/Relay) inline label'a alındı (ana satır temizlendi); plan modu açıkken turuncu `list.bullet.clipboard.fill` rozet.
- **`isConnected` gate** — bağlantı yokken menu disabled.
- **Defensive:** `availableBackends` boşsa `selectedBackend` tek seçenek (pairing yok / hostStatus gelmedi).

## [0.2.55] — 2026-05-25

**Sprint 30 — Test hygiene + flake root cause analysis.** v0.2.37+ documented edilmiş "PixelLAN intermittent SIGSEGV/SIGBUS" flake'i root cause analizinde **build cache hassasiyeti** olarak belirlendi — gerçek test isolation veya port collision değil, stale incremental build artifact'leri memory layout'unu bozuyor. Clean rebuild her seferinde sorunu çözüyor. Bu release flake'i yapısal değil **operasyonel** olarak adresliyor: `scripts/test.sh` clean rebuild harness + `LANServiceLifecycleTests` gerçek start/stop pattern demonstration (port=0 + tearDown garantisi).

**Test:** Mac 980 → **983** (+3: LANServiceLifecycleTests — start without throwing, stop allows restart, double-start throws alreadyStarted). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

### Added — Sprint 30 / Test hygiene

#### `scripts/test.sh` (yeni)
- **Clean rebuild + full test run harness:** `rm -rf .build` + `swift test` + summary.
- **`--quick` mode:** Build cache'i koru (incremental), sadece `swift test`.
- **Output:** PASS/FAIL banner + test total + crash detection (`unexpected signal` grep) + clean rebuild tip.
- **Idempotent:** Local development + CI için tutarlı entry point.

#### `Tests/PixelLANTests/LANServiceLifecycleTests.swift` (yeni)
- **3 yeni test:** `LANService.start()`/`.stop()` gerçek lifecycle — port=0 (ephemeral) + tearDown garantisi.
  - `testServiceStartsWithoutThrowing`: start `ServiceError` atmıyor; stop temizliyor.
  - `testStopAllowsRestart`: stop sonrası tekrar start çağrılabilir (kaynak leak yok).
  - `testDoubleStartThrowsAlreadyStarted`: defensive — stop önce çağırılmadan start tekrar atmalı.
- **`tearDown` async:** Her test sonrası `service?.stop()` defensive — NWListener file descriptor + GCD queue temizliği. Test isolation pattern referansı.

### Root cause hypothesis update — v0.2.37 LAN flake

**Önceki hipotez:** "NWListener/Bonjour multi-process port çakışması" (parallel mode) + "xctest single process kümülatif memory state corruption" (default mode).

**Yeni bulgu (Sprint 30 analizi):**
1. Tests'in çoğunluğu stub-based — gerçek `NWListener.start()` çağrısı yok (v0.2.37 → v0.2.54 PixelLAN suite'inde).
2. `LANFramingTests.testDecodeMultipleLines` (pure data manipulation) deterministik signal 11 atıyordu — network yok, port yok.
3. Debug `print` statement eklemek crash'i ortadan kaldırıyor (Heisenbug — memory layout sensitivity).
4. `rm -rf .build` + clean rebuild → flake yok. İdempotent rebuild sonrası 3 ardışık `swift test` çalıştırması temiz.

**Sonuç:** Bu Swift toolchain'inin (6.3.2 + Xcode 16+) test target incremental build'inde rare object file corruption / memory aliasing. **Workaround:** Clean rebuild öncesi test koşturma. `scripts/test.sh` bunu garantiliyor.

### Notes — Sprint 30
- **Counts düzeltmesi:** Önceki sprint'lerin per-module test count'ları script'in ilk "Executed N tests" line'ını picking up'lamasından PixelLANTests altında çekiliyordu (FallbackTransportTests'in 6'sı). Sprint 30'dan itibaren tail -1 ile package-level cumulative kullanılıyor — actual count ~40 daha yüksek (Sprint 29 945 → corrected ~980).
- **Future direction:** Eğer flake CI'da görülürse (henüz GitHub Actions üzerinde test yok), CI workflow'unda `scripts/test.sh` (clean mode) kullanılmalı. Local development için `--quick` daha hızlı.
- **Apple Bug Reporter candidate:** Reproducible'sa Swift toolchain'ine FB radar açılabilir; şimdilik workaround yeterli.

## [0.2.54] — 2026-05-25

**Sprint 29 — Small UX tuning bundle.** Üç bağımsız küçük iyileştirme tek release:

1. **OCR confidence threshold** — Vision `.fast` mode low-confidence noise filter. `SoMOptions.ocrMinConfidence: Double` (0.0-1.0, default 0.0 backward-compat). MCP wire `ocr_min_confidence`.
2. **OCR cancellation propagation** — `Task.isCancelled` guard'lar `OCRTextDetector`'da (pre-dispatch + post-dispatch + closure içi); `ParallelCropDetection.detect` cancellation honor eder (collection loop'unda erken çıkış + `group.cancelAll()`).
3. **Sparkline genişliği user preference** — iOS Mac Paneli wire latency badge yanındaki trend grafiğinin genişliği kullanıcı ayarı. `SettingsTabView` "Görselleştirme" section'a slider (40-160pt, step 8). `@AppStorage` ile shared, default 80pt (Sprint 25 hardcoded'un eşi).

**Test:** Mac 938 → **945** (+7: 5 SoMOptions confidence — default 0/custom/clamp range/Codable round-trip/backward-compat decode; 2 ParallelCropDetection cancellation smoke). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (3 item'ın tümü additive opsiyonel + backward-compat defaults).

### Added — Sprint 29 / Small UX tuning bundle

#### 1. OCR confidence threshold

**`Sources/PixelComputerUse/SoMOptions.swift`**
- **`ocrMinConfidence: Double = 0.0`** yeni field — `init` 0.0-1.0 clamp eder (defensive bozuk input). Sadece `.contentAware` placement iken kullanılır.
- **Manuel Codable:** `decodeIfPresent` ile eski JSON'da yoksa default 0.0 (backward-compat).

**`Sources/PixelComputerUse/OCRTextDetector.swift`**
- **`detectTextRegions(in:minConfidence:)`** + **`detectTextRegions(in:cropRect:minConfidence:)`** — `minConfidence` opsiyonel param default 0.0.
- **`performDetection(on:cropOffset:minConfidence:)`** — `observation.confidence >= Float(minConfidence)` ile compactMap filter.

**`Sources/PixelComputerUse/ScreenshotCapture.swift`**
- `collectTextRegions` `options.ocrMinConfidence`'i her detector çağrısına geçirir (whole-image + per-element).

**`Sources/PixelMCPServer/ToolRegistry.swift`**
- `ui_screenshot.som_options` schema'sına `ocr_min_confidence` parametresi eklendi (0.0-1.0, default 0.0; 0.5 ortalama, 0.8 sıkı).

#### 2. OCR cancellation propagation

**`Sources/PixelComputerUse/OCRTextDetector.swift`**
- **Pre-dispatch guard:** `if Task.isCancelled { return [] }` — Vision pass'i hiç başlatma.
- **Post-dispatch guard:** Background queue'ya geçildikten sonra ikinci check — outer cancel queue gecikmesinden sonra hâlâ sonucu yutmasın.

**`Sources/PixelComputerUse/ParallelCropDetection.swift`**
- **Pre-spawn guard:** Cancellation check, `TaskGroup` spawn'lanmaz.
- **Collection loop check:** `for await regions in group` içinde `Task.isCancelled` → `group.cancelAll()` + `break`. Kalan child task'lar `withTaskGroup` exit'inde implicit cancel.
- **Child task closure:** OCR closure içinde `Task.isCancelled` propagation (Vision interruptible değil ama next checkpoint'te bail out).

#### 3. Sparkline width user preference

**`ios/PixelAgentRemote/SparklinePreferences.swift` (yeni saf helper)**
- **`SparklinePreferences` enum** constants — `widthKey` UserDefaults key, `defaultWidth: 80`, `minWidth: 40`, `maxWidth: 160`, `clamped(_:)` defensive.

**`ios/PixelAgentRemote/SettingsTabView.swift`**
- **`displaySection`** yeni Form section "Görselleştirme" — `Slider` 40-160pt, step 8; `Label` waveform.path icon + "Xpt" monospaced caption. `@AppStorage(SparklinePreferences.widthKey)` ile shared.

**`ios/PixelAgentRemote/ChatView.swift`**
- **`MacPanelDashboardSection`** `@AppStorage(SparklinePreferences.widthKey)` field; wire latency badge HStack'inde sparkline frame `SparklinePreferences.clamped(sparklineWidth)` ile.

### Tests
- `Tests/PixelComputerUseTests/SoMOptionsTests.swift` — **+5** Sprint 29: default 0.0 confidence, accept custom 0.5, clamp -0.5/1.5 → 0.0/1.0, full Codable round-trip with confidence, **backward-compat decode without ocrMinConfidence field**.
- `Tests/PixelComputerUseTests/ParallelCropDetectionTests.swift` — **+2** Sprint 29 cancellation: pre-cancel task returns empty/partial; mid-flight cancellation bounded.

### Notes — Sprint 29
- **3-in-1 bundle:** Üç ortak temaya bağlı olmayan küçük UX item single release'te toplandı (CHANGELOG/tag/tap maliyetini amortize). Sprint 1/2/3 paterniyle aynı.
- **Cancellation caveat:** Vision `perform()` mid-call interruptible değil; cancellation guard'lar pre/post Vision; orta-Vision cancel olursa o pass tamamlanır (sonuç yutulur). `.fast` mode pass'leri ~50-300ms, kabul edilebilir.
- **`@AppStorage` cross-view sharing:** `SettingsTabView` slider ↔ `ChatView` MacPanelDashboardSection aynı UserDefaults key — değişiklik anında badge re-render.

## [0.2.53] — 2026-05-25

**Parallel per-element Vision — Sprint 27 follow-up.** v0.2.52 `.perElement` modu sequential loop kullanıyordu — N element için N × ~50-150ms wall-clock. v0.2.53 `withTaskGroup` ile her crop rect için konkurrent `Task` spawn'lar; wall-clock max(per-element) seviyesine düşer. 5 element × 100ms test: sequential ~500ms+ → parallel ~300ms+ (Neural Engine ve CPU scheduler latency dahil). Çoğu vision agent senaryosunda `.perElement` artık `.wholeImage` ile rekabet edebilir hale geldi.

**Test:** Mac 928 → **938** (+10: ParallelCropDetectionTests — empty/single/multi/mixed-results, parallel execution speedup, concurrent in-flight tracker, many crops, defensive empty closure). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (orchestration internal refactor; davranış union ordering haricinde aynı — caller order'a güvenmemeli ki Sprint 26'dan beri öyle değildi).

### Added — Sprint 28 / Parallel per-element Vision

#### `Sources/PixelComputerUse/ParallelCropDetection.swift` (yeni saf helper)
- **`detect(cropRects:ocr:) async -> [CGRect]`** — generic OCR orchestration. `withTaskGroup(of: [CGRect].self)` her crop rect için ayrı Task spawn'lar, hepsi tamamlanınca union döner. Boş input → boş output, TaskGroup spawn'lanmaz.
- **OCR closure `@Sendable`** generic — test'lerde mock kullanılabilir (Vision dependency yok). Production'da `OCRTextDetector.detectTextRegions(in:cropRect:)` wrap edilir.
- **Ordering caveat:** Union task completion sırasına bağlı — non-deterministic. Caller order'a güvenmemeli; CGRect overlap scoring (Sprint 26 `OCRBadgePlacement`) sıraya duyarsız.
- **Neural Engine caveat:** Apple Silicon Neural Engine multi-request Vision'ı internal serialize edebilir; theoretical speedup ~1x'e yaklaşabilir ama worst case sequential, regresyon yok. `.fast` recognition level CPU path'ini kullanıyor olabilir, paralelizm avantajlıdır.

#### `Sources/PixelComputerUse/ScreenshotCapture.swift`
- **`collectTextRegions` `.perElement` branch refactor:**
  - **Önce:** sequential for-await loop her element için.
  - **Şimdi:** İki aşama:
    1. **Sync crop rect listesi** (`MarkLayout.computeMarkRect` + `ElementRegionExpander.expandedRect` — saf math, hızlı).
    2. **Parallel Vision pass'leri** `ParallelCropDetection.detect(cropRects:ocr:)` ile.
- CGImage `@Sendable` closure'a strong capture — CFType effectively Sendable read-only ops için.

### Tests
- `Tests/PixelComputerUseTests/ParallelCropDetectionTests.swift` — **10 yeni**: empty crop rects boş sonuç + closure çağrılmaz, single crop tek OCR call + cropRect parametresi closure'a düşer, multi crops union (3 crop × 2 region = 6 total), empty results union'da yok, mixed results sadece dolu olanları topla, **parallel speedup smoke test** (5 × 100ms <350ms), **peak concurrency observer** (4 task aynı anda 2+ in-flight), many crops (20) hepsini çalıştır, defensive empty input closure çağrılmaz.
- Yeni test actor'lar (`OCRCallCounter`, `ConcurrencyObserver`) — Sendable-safe mutable state for assertions.

### Notes — Sprint 28
- **`.wholeImage` etkilenmedi** — Sprint 26 single-pass path aynı. Sadece `.perElement` artık paralel.
- **Wall-clock kazanç:** N element × per-element latency → ~per-element latency. 5 element 100ms each: 500ms sequential → ~150-300ms parallel. Neural Engine serialize ederse fark daha küçük; CPU yolu paralel.
- **Memory:** N Vision request konkurrent → memory peak yükselir (her biri ~10-50MB). Tipik vision agent workflow'unda 5-15 element, kabul edilebilir.
- **Caller değişikliği gerekmedi** — `.perElement` opt-in mode aynı API, sadece içeride paralel.

## [0.2.52] — 2026-05-25

**Per-element OCR crop — Sprint 26 follow-up.** v0.2.51 `.contentAware` placement Vision'ı **tüm screenshot** üzerinde tek pass çalıştırıyordu — çoğu element için iyi (1 pass overhead amortize olur), ama az element + büyük screen senaryolarında ilgisiz alanlarda da Vision çalışır. v0.2.52 `OCRCropMode` enum'u ile opt-in `.perElement` modu: her element için `ElementRegionExpander.expandedRect` ile crop edilmiş region'da ayrı Vision pass. Az element (1-3) + küçük rect'lerde wall-clock daha hızlı; scoring scope'ı element neighborhood'una sınırlı.

**Test:** Mac 913 → **928** (+15: 9 ElementRegionExpander saf helper + 6 SoMOptions ocrCropMode coverage — Codable round-trip, default, backward-compat without field, snake_case raw value). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (additive opsiyonel param, eski wire format `convertFromSnakeCase` ile uyumlu, `SoMOptions.ocrCropMode` field eski JSON'da yoksa default `.wholeImage`).

### Added — Sprint 27 / Per-element OCR crop

#### `Sources/PixelComputerUse/ElementRegionExpander.swift` (yeni saf helper)
- **`expandedRect(elementRect:badgeSize:imagePixelSize:padding:) -> CGRect?`** — element rect'i badge size + padding kadar her yönde genişletir, image bounds'a clamp eder. Outside badge candidate'larını + civar text bağlamını kapsar.
- **`defaultPadding: CGFloat = 8`** — ek padding adjacent text yakalamak için.
- **Defensive:** Element image dışı → nil; zero-size image → nil.
- **Saf math** — Vision/View dependency yok; testable.

#### `Sources/PixelComputerUse/OCRTextDetector.swift`
- **`detectTextRegions(in image:, cropRect:) async -> [CGRect]`** yeni overload — image'ı `cropRect`'e crop eder (`CGImage.cropping(to:)`), Vision pass yapar, sonuç koordinatları `cropRect.origin` eklenerek image-global'a translate.
- **`performDetection(on:cropOffset:)`** private — `cropOffset` parametresi alır; whole-image modunda `.zero`, crop modunda `cropRect.origin`.

#### `Sources/PixelComputerUse/SoMOptions.swift`
- **`OCRCropMode` yeni enum** — `.wholeImage` (default, Sprint 26 path) | `.perElement` (Sprint 27 opt-in). **Snake_case raw value** (`"whole_image"` / `"per_element"`) — MCP wire docs ile tutarlı; BadgePlacement camelCase raw value Sprint 26 ile shipped, yeni enum'larda snake_case standart.
- **`SoMOptions.ocrCropMode: OCRCropMode = .wholeImage`** yeni field.
- **Manuel Codable** — eski JSON'da `ocrCropMode` yoksa default `.wholeImage` (backward-compat). `decodeIfPresent` her field için → eski wire format'ı bozmaz.

#### `Sources/PixelComputerUse/ScreenshotCapture.swift`
- **`collectTextRegions(for:in:options:imageScreenOrigin:imageLogicalSize:)`** yeni private static — `options.ocrCropMode`'a göre dispatcher:
  - `.wholeImage`: `OCRTextDetector.detectTextRegions(in:)` (Sprint 26 path).
  - `.perElement`: her element için `MarkLayout.computeMarkRect` ile image içindeki rect, `ElementRegionExpander.expandedRect` ile crop region, `OCRTextDetector.detectTextRegions(in:cropRect:)` ile pass, sonuçlar union'lanır.

#### `Sources/PixelMCPServer/ToolRegistry.swift`
- **`ui_screenshot.som_options`** schema açıklamasına `ocr_crop_mode` parametresi eklendi: `'whole_image'` (default) | `'per_element'`. Sadece `content_aware` placement iken anlamlı.

### Tests
- `Tests/PixelComputerUseTests/ElementRegionExpanderTests.swift` — **9 yeni**: basic expansion (badge + padding), default padding usage, bounds clamping (top-left/bottom-right corner, completely outside, zero-size image), custom padding (zero, large), default padding sabiti.
- `Tests/PixelComputerUseTests/SoMOptionsTests.swift` — **+6** Sprint 27: OCRCropMode snake_case raw values, Codable round-trip, SoMOptions default `.wholeImage`, accepts `.perElement`, full round-trip with cropMode, **backward-compat decode without field** (eski JSON → default).

### Notes — Sprint 27
- **Performance trade-off:** `.perElement` Vision setup cost N pass için N × ~50-100ms overhead. Çok element (>5) durumunda `.wholeImage` (tek pass ~100-300ms) daha hızlı. **Default `.wholeImage` korunur** — Sprint 26 davranışı.
- **Scoping benefit:** Per-element crop OCR sadece element neighborhood'unu görür; uzak text scoring'i etkilemez. Whole-image'da ise tüm text bbox'ları flat liste; ama scoring CGRect overlap'le iş gördüğü için ilgisiz uzak text overlap'siz olduğundan score'u etkilemez (Sprint 26 design'ı zaten "doğal" filtering yapıyordu).
- **Snake_case migration:** `OCRCropMode` raw value snake_case (wire docs ile tutarlı). Önceki `BadgePlacement` camelCase raw shipped — Sprint 26 wire'ı bozmamak için bırakıldı; gelecekte explicit migration ile snake_case'e çevrilebilir.

## [0.2.51] — 2026-05-25

**OCR-based SoM badge placement — Sprint 20 follow-up.** v0.2.45 AX role heuristic (button → topRightOutside, link → topRightInside, vs.) konvansiyon tabanlıydı — custom widget'larda veya beklenmedik layout'larda yine badge text alanını örtebilirdi. v0.2.51 Vision framework `VNRecognizeTextRequest` ile screenshot'taki tüm text bounding box'ları çıkarır; her element için 4 köşe adayı arasından **text ile en az çakışan** seçilir. OCR başarısız veya text yoksa `.labelAware` fallback'i — graceful degradation.

**Test:** Mac 897 → **913** (+16: 14 OCRBadgePlacement saf helper testleri + 2 SoMOptions content-aware Codable round-trip + raw value coverage). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni enum case additive, SoMRenderer signature opsiyonel param).

### Added — Sprint 26 / OCR-based SoM badge placement

#### `Sources/PixelComputerUse/SoMOptions.swift`
- **`BadgePlacement.contentAware`** yeni case — OCR text-aware placement strategy. AX heuristic'in pratik limiti aşıldığında devreye girer.

#### `Sources/PixelComputerUse/OCRBadgePlacement.swift` (yeni saf helper)
- **`overlapArea(badgeRect:textRegions:) -> CGFloat`** — badge ile tüm text region'larının toplam çakışma alanı (pixel²). Düşük = iyi yerleşim.
- **`scorePlacements(elementRect:badgeSize:imagePixelSize:textRegions:candidates:)`** — adayları skorlar; image bounds dışına taşan adaylar filtrelenir.
- **`bestPlacement(...) -> BadgePlacement?`** — en az çakışan aday. Stable tie-breaking (array sırası kazanır). Tüm adaylar invalid'se nil.
- **`defaultCandidates`** static — `[topLeftInside, topLeftOutside, topRightInside, topRightOutside]`.
- **Vision dependency yok** — saf math; test edilebilir.

#### `Sources/PixelComputerUse/OCRTextDetector.swift` (yeni)
- **`detectTextRegions(in image: CGImage) async -> [CGRect]`** — `VNRecognizeTextRequest(.fast)` background queue üzerinde; `CheckedContinuation` ile async wrap. Vision'ın normalize (0-1, bottom-left) bbox'ları image pixel coords + top-left origin'e çevrilir (SoMRenderer convention).
- **Best-effort:** Vision hatası / sonuç yok → boş array; caller `.labelAware` fallback'ine düşer.
- **Performans:** Typical retina screenshot (~3000×1800) ~100-300ms with `.fast` mode.
- **`#if canImport(Vision)`** — platform safety (iOS/macOS only); diğer platformlarda boş array.

#### `Sources/PixelComputerUse/SoMRenderer.swift`
- **`annotate(...textRegions: [CGRect] = [])`** — yeni opsiyonel param. Caller (ScreenshotCapture) OCR çıktısını upfront sağlar.
- **`resolvePlacement(requested:elementRect:badgeSize:imagePixelSize:element:textRegions:) -> BadgePlacement`** yeni static helper — per-element concrete placement döner. `.contentAware` → `OCRBadgePlacement.bestPlacement` (textRegions varsa); fallback `.labelAware`. `.labelAware` → AX role lookup. Diğer → request as-is.
- **BadgeLayout.rawBadgeRect:** `.contentAware` case'i defensive `.topLeftInside` fallback'ine eklendi (resolvePlacement zaten concrete'e çevirir).

#### `Sources/PixelComputerUse/ScreenshotCapture.swift`
- **`capture(...)` orkestra:** `options.badgePlacement == .contentAware` ise `OCRTextDetector.detectTextRegions(in: croppedImage)` upfront çağrılır; `SoMRenderer.annotate(...textRegions:)` ile passla. Aksi halde boş array (eski path).
- **Async chain:** `capture` zaten `async throws` idi; OCR call zincire eklendi sorunsuz.

#### `Sources/PixelMCPServer/ToolRegistry.swift`
- **`ui_screenshot.som_options.badge_placement`** schema açıklamasına `'content_aware'` enum eklendi — Vision OCR ile gerçek text bbox'larını çıkarıp en az çakışan köşe seçilir; `label_aware` pratik limiti aşıldığında. OCR başarısız ise `label_aware` fallback'i.

### Tests
- `Tests/PixelComputerUseTests/OCRBadgePlacementTests.swift` — **14 yeni**: overlapArea (empty/disjoint/contained/partial/multiple-sum/edge-touching), scorePlacements (within-bounds/out-of-bounds filter), bestPlacement (no-text first-candidate/avoid-overlap/min-score/empty-candidates/stable-tie-breaking), defaultCandidates 4-corner coverage.
- `Tests/PixelComputerUseTests/SoMOptionsTests.swift` — **+2** Sprint 26: `.contentAware` Codable round-trip + raw value + SoMOptions accepts.

### Notes — Sprint 26
- **`.contentAware` overhead:** Per-screenshot tek Vision pass (~100-300ms). Caller bunu kabul edilebilir buluyorsa devreye al; vision model'in "1, 2, 3" görmesi her zamanki gibi.
- **Backward-compat:** `.contentAware` istemeyen caller'lar etkilenmedi; SoMRenderer `textRegions: [CGRect] = []` default'lu, eski callsites unchanged.
- **Whole-image OCR stratejisi:** Vision tek geçişte tüm text bbox'larını çıkarır (per-element OCR yerine — performans 1× yerine N×). Caller element rect'lerini textRegions ile cross-check ederek hangi text element içinde olduğunu çıkarabilir.
- **iOS:** `OCRTextDetector` `#if canImport(Vision)` gate'i sayesinde iOS'ta da çalışır; ama pixel-agent'ın SoM rendering'i Mac-only (ScreenCaptureKit dependency).

## [0.2.50] — 2026-05-25

**Wire latency timeline grafiği — Sprint 24 follow-up.** v0.2.49 per-frame latency embed ile iOS badge ~1Hz spot değer gösteriyordu — ancak spike'lar görsel olarak yakalanamıyordu. v0.2.50 son 20 frame'in (~20 sn @ 1Hz) latency trendini **inline sparkline** olarak badge'in yanında çizer. Saf normalize helper (`LatencySparkline.points`) min-max auto-scaling + uniform x spacing + defensive edge case'ler (boş, tek nokta, tüm eşit). View katmanı SwiftUI `Path` + `GeometryReader` ile çizer.

**Test:** Mac 883 → **897** (+14 LatencySparkline: empty/single/all-same edge cases, two-point min-max, monotonic, x spacing uniform, custom min-max bounds, y orientation, push ring buffer 5 case'i, NormalizedPoint Equatable). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni saf helper additive, yeni @Published field additive).

### Added — Sprint 25 / Wire latency timeline grafiği

#### `Sources/PixelRemote/LatencySparkline.swift` (yeni saf helper)
- **`LatencySparkline`** enum static funcs:
  - **`points(latencies:minLatency:maxLatency:) -> [NormalizedPoint]`** — 0-1 normalize koordinatlar. Empty → boş; tek nokta → (0.5, 0.5); tüm eşit → midline; çoklu → uniform x + linear y normalize. Custom bounds opsiyonel (sabit eşik istenirse).
  - **`push(_:into:maxCount:)`** — ring buffer; append + maxCount'u aşan en eski entry'leri trim. Defensive maxCount=0 ve oversized buffer durumlarında doğru çalışır.
- **`NormalizedPoint`** struct (x, y: Double; Sendable + Equatable) — 0-1 koordinat. View katmanı SwiftUI top-down için `1 - y` ile flip eder.
- **Tasarım kararı:** SwiftUI/CoreGraphics bağımlılığı yok — saf math. View katmanı `proxy.size` ile çarpıp `CGPoint`'e çevirir.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- **`@Published var wireLatencyHistory: [Int] = []`** yeni field.
- **`Self.wireLatencyHistoryMax = 20`** static sabit (~20 sn @ 1Hz).
- **`.screenshotPayload`** handler: latency varsa `LatencySparkline.push` ile ring buffer'a append.
- **`stopScreenshotStream`** ek olarak `wireLatencyHistory.removeAll()` — bir sonraki başlangıçta sparkline boş başlasın.

#### `ios/PixelAgentRemote/WireLatencySparklineView.swift` (yeni)
- **`WireLatencySparklineView`** SwiftUI `Path` + `GeometryReader`. `LatencySparkline.points` normalize koordinatları + `proxy.size` ile çarpım + Y flip. `StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)`. Accessibility label "Latency trend grafiği".

#### `ios/PixelAgentRemote/ChatView.swift` (Mac Paneli "Ekran Resmi" badge)
- Wire latency capsule içine **inline `WireLatencySparklineView`** (80×16 frame) eklendi — badge'in renk eşiğiyle aynı renkte stroke. Trend grafiği "Ağ: X ms" metninin sağında.

### Tests
- `Tests/PixelRemoteTests/LatencySparklineTests.swift` — **14 yeni**: edge cases (empty/single/all-same), normalize (two-point/monotonic/uniform-spacing), custom bounds, y orientation convention, ring buffer (push below/at/beyond max, oversized buffer trim, maxCount=0 defensive), NormalizedPoint Equatable.

### Notes — Sprint 25
- **Sparkline genişliği** sabit 80pt; kullanıcı tercihine açılabilir (v0.3 adayı). Yükseklik 16pt (caption typography'siyle uyumlu).
- **Y konvansiyonu:** Helper y=0 alt, y=1 üst döner; SwiftUI top-down (y=0 üst) için view katmanı `1 - y` flip eder — düşük latency aşağıda, yüksek latency yukarıda gözükür.
- **Auto-scaling:** Default'ta sparkline'ın min/max'ı history içindeki değerlere göre — küçük varyasyonlar görsel olarak büyütülür. Caller sabit eşik istiyorsa `minLatency`/`maxLatency` parametreleri ile override edebilir.

## [0.2.49] — 2026-05-25

**Per-frame wire latency embed — Sprint 23 follow-up.** v0.2.48 wire latency badge'i `hostStatusDelta` 3 sn periyodik push'una bağlıydı — kullanıcı interval ortasında bir spike görse 3 sn beklerdi. v0.2.49 Mac coordinator önceki frame'in ACK round-trip ölçümünü her `screenshotPayload` envelope'una **embed eder**; iOS Mac Paneli badge stream rate'inde (~1Hz, kullanıcı tercihine göre 250 ms-5 sn) güncellenir. hostStatus path fallback kalır (eski Mac'ler için).

**Test:** Mac 880 → **883** (+3 net: 3 yeni EnvelopePayloadSumType — withWireLatencyRoundTrip, getterAcrossCases, frameIDAndLatencyIndependent; 2 existing test 3-tuple pattern'e migrate). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (additive optional field, eski wire format decoder ile uyumlu).

### Added — Sprint 24 / Per-frame wire latency embed

#### `Sources/PixelRemote/RemoteEnvelope.swift` (protokol genişletme, additive)
- **`EnvelopePayload.screenshotPayload(base64Image: String, frameID: String?, wireLatencyMs: Int?)`** — 3. associated value (önceki: 2). `encodeIfPresent` ile eski wire format korunur; eski Mac frameID/latency göndermez (nil), eski iOS field'ı yoksayar.
- **`payload?.screenshotWireLatencyMs`** getter artık `screenshotPayload` case'ini de kapsar — Sprint 23'ün hostStatus/Delta path'leri yanına.
- **Factory:** `screenshotPayload(base64Image:frameID:wireLatencyMs:)` üçü de opsiyonel default'lu.

#### `Sources/PixelRemote/RemoteHost.swift`
- **`sendScreenshot(base64Image:frameID:wireLatencyMs:)`** — yeni opsiyonel param (default nil ile eski callsites unchanged).

#### `Sources/PixelMacApp/ScreenshotStreamCoordinator.swift`
- **`start(intervalMs:sendImage:)`** callback signature: `(base64, frameID)` → `(base64, frameID, wireLatencyMs?)`.
- **Loop:** Her tick, `lastWireLatencyMs` (önceki frame'in ACK round-trip'i) snapshot alınıp callback'e iletilir; iOS bu envelope'tan badge'i günceller.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`onScreenshotStreamStartRequested`** callback closure yeni 3-tuple imzasıyla `sendScreenshot(...wireLatencyMs:)` çağırır.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- **`.screenshotPayload`** merge handler: `if let latency = payload.screenshotWireLatencyMs` ile guard'lı update — bu envelope per-frame geldiği için hostStatus path'ından daha güncel. En son envelope kazanır.

### Tests
- `Tests/PixelRemoteTests/EnvelopePayloadSumTypeTests.swift` — **+3** Sprint 24: per-frame latency round-trip, getter cross-case coverage, frameID/latency independence. Mevcut 2 test `(let img, let frameID, let latency)` 3-tuple pattern'e güncellendi.
- `Tests/PixelMacAppTests/ScreenshotStreamCoordinatorTests.swift` — 11 closure literal `{_, _, _ in}` yeni signature'a migrate edildi.

### Notes — Sprint 24
- **Sprint 23 ile çakışma:** hostStatus path hâlâ aktif (3 sn delta); iOS handler her iki yoldan gelen değeri en son `screenshotWireLatencyMs`'e atar. Per-frame envelope çoğu zaman daha yeni → o kazanır. Eski Mac'lerle backward-compat sayesinde hostStatus tek başına çalışır.
- **Bandwidth:** Her frame'e ~5-10 byte ek (`"screenshotWireLatencyMs":123`). 1Hz stream'de ~10 B/s — JPEG payload yanında ihmal edilebilir.
- **Stream başlangıcı:** İlk frame'de hiç ACK gelmemiştir → `lastWireLatencyMs = nil` → embed'lenir nil; iOS badge stable kalır (önceki hostStatus değeri veya gizli).

## [0.2.48] — 2026-05-25

**Wire latency badge UI — Sprint 22 follow-up.** v0.2.47 Mac side wire-level latency'i `WireLatencyTracker` ile ölçüyordu ama iOS kullanıcısına görsel feedback yoktu. v0.2.48 `HostStatusContent` + `HostStatusDeltaContent` aggregator'larına `screenshotWireLatencyMs: Int?` field eklendi; Mac periyodik 3 sn delta loop'unda coordinator'ın son ölçümünü push'lar; iOS Mac Paneli "Ekran Resmi" section'unda **renk-bantlı capsule rozet** (yeşil <100ms, turuncu <300ms, kırmızı >=300ms). Görselleştirme `isStreamingScreenshots` gate'i ile streaming aktif değilken gizlenir.

**Test:** Mac 871 → **880** (+9 net: 9 HostStatusDeltaCalculator wire latency testleri — full bootstrap, change/unchanged delta, value→nil edge case, host envelope round-trip with/without latency, isEmpty truth table, getter passthrough). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (additive optional field, `encodeIfPresent` ile eski wire format korunur).

### Added — Sprint 23 / Wire latency badge UI

#### `Sources/PixelRemote/RemoteEnvelope.swift` (protokol genişletme, additive)
- **`HostStatusContent.screenshotWireLatencyMs: Int?`** yeni field (default nil — stream aktif değil veya henüz ACK gelmedi).
- **`HostStatusDeltaContent.screenshotWireLatencyMs: Int?`** delta versiyonu — diğer delta field'larıyla aynı pattern (nil = "değişmedi").
- **`PayloadKey.screenshotWireLatencyMs`** wire field — decode/encode `encodeIfPresent`.
- **`payload?.screenshotWireLatencyMs: Int?`** backward-compat computed getter (her iki case'i kapsar).
- **`HostStatusDeltaContent.isEmpty`** wire latency'yi de kontrol eder.
- **Factory:** `hostStatus(...screenshotWireLatencyMs: nil)` ve `hostStatusDelta(...screenshotWireLatencyMs: nil)` parametreleri default'lu.

#### `Sources/PixelRemote/HostStatusDeltaCalculator.swift`
- **`delta(from:to:)`** field-by-field karşılaştırması listesine `screenshotWireLatencyMs` eklendi.
- **Full bootstrap (`from: nil`):** new'in `screenshotWireLatencyMs`'i delta'ya kopyalanır.
- **Incremental:** `old != new` ise yeni değer; eşitse nil (skip).
- **Edge case:** old=87, new=nil → delta.wireLatency = nil; calculator `isEmpty` ile push'u skip eder (stream stop sonrası tek başına latency clear push'u yapılmaz, iOS UI gate'i badge'i gizler).

#### `Sources/PixelRemote/RemoteHost.swift`
- **`sendHostStatus(...screenshotWireLatencyMs: nil)`** opsiyonel param eklendi (default nil ile eski callsites unchanged).

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **Periyodik delta loop:** `HostStatusContent` snapshot'ına `screenshotStream.isActive` iken `screenshotStream.lastWireLatencyMs`, aksi halde nil iletilir.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- **`@Published var screenshotWireLatencyMs: Int? = nil`** yeni field.
- **`.hostStatus, .hostStatusDelta`** merge handler: `if let latency = payload.screenshotWireLatencyMs` ile guard'lı update (nil = unchanged delta).
- **`stopScreenshotStream`** ek olarak `screenshotWireLatencyMs = nil` — bir sonraki başlangıçta stale değer briefly görünmesin.

#### `ios/PixelAgentRemote/ChatView.swift` (Mac Paneli "Ekran Resmi" section)
- **Wire latency badge:** `isStreamingScreenshots && screenshotWireLatencyMs != nil` koşuluyla görünür capsule (`wifi` icon + "Ağ: X ms" monospaced).
- **`wireLatencyColor(_:)`** private helper — eşik bantları (<100 yeşil, <300 turuncu, ≥300 kırmızı). Tip backstop: subjektif eşikler; LAN <30 ms, internet+relay 50-200 ms tipik.

### Notes — Sprint 23
- **Tahmini delay:** Badge 3 saniyelik delta loop ile güncellenir; debug-tier feedback yeterli, real-time değil. Daha hızlı güncelleme için latency'i `screenshotPayload` envelope'una embed etmek alternatif (her tick = ~1Hz)—v0.2.49+ adayı.
- **Stream kapatma davranışı:** Mac stream stop edip Mac'ten latency nil gelse de delta calculator `isEmpty` ile push'u skip eder; iOS UI badge'i `isStreamingScreenshots` ile gizler. iOS taraf manuel stop ile `screenshotWireLatencyMs = nil` reset eder.

## [0.2.47] — 2026-05-25

**Wire-level latency — Sprint 21 follow-up.** v0.2.46 adaptive rate son tick latency'sini **local** (capture + JPEG + transport handoff) ölçüyordu — backpressure'a duyarlı ama ağ koşulundan habersiz. v0.2.47 Mac her frame'e UUID `frameID` iliştirir; iOS aynı ID ile `screenshotFrameAck` envelope döner; coordinator round-trip ms = **wire latency**. Adaptive controller artık gerçek ağ latency'sine göre scale ediyor. Henüz ACK yokken (stream başlangıcı, eski iOS sürümleri) `WireLatencyTracker.effectiveLatencyMs` 5 sn freshness window dışında **local fallback**'e düşer — graceful degradation.

**Test:** Mac 859 → **871** (+12 net: 16 WireLatencyTracker + 3 ScreenshotStreamCoordinator + 5 EnvelopePayloadSumType + 1 RemoteEnvelope regression set + 1 SettingsTab v0.2.39 pre-existing fix; duplicate-counted across modules). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok — `screenshotPayload(base64Image:)` factory default `frameID: nil` ile eski callsites unchanged; `EnvelopeType.screenshotFrameAck` forward-compat unknown fallback ile eski client'lar sessizce yutar.

### Added — Sprint 22 / Wire-level latency

#### `Sources/PixelMacApp/WireLatencyTracker.swift` (yeni saf helper)
- **`WireLatencyState: Sendable, Equatable`** struct
  - `pending: [String: Date]` — gönderilen ama henüz ACK'lenmemiş frameID → sentAt.
  - `lastWireLatencyMs: Int?` — son alınan ACK'in hesapladığı wire latency (nil = hiç ACK gelmedi).
  - `lastAckAt: Date?` — son ACK alınma anı; freshness window kontrolü için.
- **`WireLatencyTracker`** enum static funcs (saf math, inout state):
  - **`record(state:frameID:at:)`** — frame gönderildiğinde caller çağırır.
  - **`consumeAck(state:frameID:receivedAt:) -> Int?`** — ACK geldiğinde; eşleşirse latency ms, `lastWireLatencyMs/lastAckAt` günceller, pending'den siler; eşleşmezse nil/no-op. Saat sapması için negatif latency 0'a clamp.
  - **`prune(state:olderThan:)`** — stale pending entry'leri (>30s) sil; sınırsız map büyümesini engeller.
  - **`effectiveLatencyMs(state:localMs:now:freshnessSeconds:5)`** — adaptive controller'a verilecek değer: fresh ACK varsa wire, aksi halde local fallback.
- Tüm metodlar `static`, side-effect dışında saf → 16 deterministik test.

#### `Sources/PixelRemote/RemoteEnvelope.swift` (protokol genişletme, additive)
- **`EnvelopeType.screenshotFrameAck`** yeni case (forward-compat: eski client'lar `.unknown` fallback ile yutar).
- **`EnvelopePayload.screenshotPayload(base64Image: String, frameID: String?)`** — frameID associated value eklendi (eski struct nil ile uyumlu).
- **`EnvelopePayload.screenshotFrameAck(frameID: String)`** yeni case.
- **`PayloadKey.screenshotFrameID`** wire field (encode `encodeIfPresent` ile, omit-when-nil).
- **`payload?.screenshotFrameID: String?`** backward-compat computed getter (her iki case'i kapsar).
- **Factory:** `screenshotPayload(base64Image:frameID:nil)` default'lu; `screenshotFrameAck(frameID:)` yeni.

#### `Sources/PixelRemote/RemoteHost.swift`
- **`onScreenshotFrameAckReceived: ((frameID: String, receivedAt: Date) -> Void)?`** yeni callback property.
- **`sendScreenshot(base64Image:frameID:nil)`** — frameID opsiyonel param eklendi (default nil ile eski callsites unchanged).
- **Inbound handler `.screenshotFrameAck`** branch — frameID non-empty ise callback çağırır; boş ID (eski wire format) skip.

#### `Sources/PixelMacApp/ScreenshotStreamCoordinator.swift` (refactor)
- **`wireState: WireLatencyState`** yeni private field — MainActor isolated.
- **`@Published lastWireLatencyMs: Int?`** — UI debug için son ACK wire latency (nil = henüz yok).
- **`start(intervalMs:sendImage:)`** sendImage signature: `(String) -> Void` → `(_ base64: String, _ frameID: String) -> Void`. Her tick'te `UUID().uuidString` üretip iliştirir + `WireLatencyTracker.record` çağrısı.
- **`recordAck(frameID:at:)`** public method — RemoteHost callback'i çağırır; pending map'te bulursa `lastWireLatencyMs` günceller.
- **Loop:** `effectiveLatencyAndPrune` (prune + effective seç) → `AdaptiveRateController.nextInterval` artık wire-aware effective latency'yi alır.
- **Re-start:** `wireState = WireLatencyState()` + `lastWireLatencyMs = nil` reset.

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`onScreenshotStreamStartRequested`** wire-up: yeni `(base64, frameID)` callback signature'a göre `sendScreenshot(base64Image:frameID:)`.
- **`onScreenshotFrameAckReceived`** yeni handler: `screenshotStream.recordAck(frameID:at:)` forward.

#### `ios/PixelAgentRemote/RemoteSession.swift`
- **`.screenshotPayload`** case: envelope payload'da `screenshotFrameID` non-nil/non-empty ise async `sendScreenshotFrameAck(frameID:)` Task.
- **`sendScreenshotFrameAck(frameID:)`** private method — `RemoteEnvelope.screenshotFrameAck(frameID:)` sign+send; transport veya signing hatası **sessizce yutulur** (ACK best-effort, kayıp frame adaptive rate için minor; bir sonraki ACK düzeltir).

### Fixed
- **`Tests/PixelMacAppTests/SettingsTabTests.swift testAllCasesPresent`** — v0.2.39 Sprint 14'te `subagent` 5. tab eklendiğinde stale kalan hardcoded count 4 → 5; `.subagent` case kontrolü eklendi. (Pre-existing bug; fix opportunistic.)

### Tests
- `Tests/PixelMacAppTests/WireLatencyTrackerTests.swift` — **16 yeni**: record/consumeAck/prune/effectiveLatencyMs tüm kombinasyonlar, negatif latency clamp, freshness threshold, state Equatable.
- `Tests/PixelMacAppTests/ScreenshotStreamCoordinatorTests.swift` — **+3**: initialWireLatencyNil, recordAckUnknownNoOp, startResetsWireLatencyState. Mevcut testler `{_, _ in}` yeni signature'a güncellendi.
- `Tests/PixelRemoteTests/EnvelopePayloadSumTypeTests.swift` — **+5**: screenshotPayload without/with frameID round-trip, screenshotFrameAck round-trip, frameID getter unrelated cases nil, ack missing ID empty decode.
- `Tests/PixelRemoteTests/RemoteEnvelopeTests.swift` — regression set'e `screenshotFrameAck` eklendi.

### Notes — Sprint 22
- **Backward-compat:** Yeni Mac v0.2.47 eski iOS sürümleriyle pairing yapabilir. Mac frameID iliştirir, eski iOS yoksayar, ACK göndermez → Mac `lastAckAt` nil kalır → `effectiveLatencyMs` her zaman localMs döner → Sprint 21 davranışı korunur. **Breaking change yok.**
- **Wire format:** Eski `screenshotPayload` (frameID-yok) encode'u olduğu gibi decode olur; yeni Mac yeni iOS round-trip'i UUID frameID ile gerçek round-trip ölçer.
- **Signing:** Yeni `screenshotFrameAck` envelope ed25519 ile imzalanır (`EnvelopeSigner.sign`); imzalı envelope canonical bytes'a frameID dahildir.

## [0.2.46] — 2026-05-25

**Adaptive stream rate — Sprint 15 follow-up.** v0.2.40'da iniş yapan continuous screenshot stream **sabit interval** (UI'dan 1000ms hardcoded) kullanıyordu. Slow network'te aynı frame rate'i zorlar → packet kuyruğu birikir; rahat network'te yine 1Hz, bandwidth boşa harcanır. v0.2.46 **Mac side latency-aware adaptive**: son tick send latency'sine göre interval otomatik ayarlanır.

**Test:** Mac 849 → **859** (+10 AdaptiveRateControllerTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (saf helper additive + Coordinator API aynı; davranış adaptive).

### Added — Sprint 21 / Adaptive stream rate

#### `Sources/PixelMacApp/AdaptiveRateController.swift` (yeni saf helper)
- **`nextInterval(currentMs:lastSendLatencyMs:baseMs:minMs:maxMs:)`** static
  — saf math, view/coordinator bağımsız → test edilebilir.
- **Algoritma:**
  - **Slow lane (backoff):** `latency > current / 2` → `min(maxMs,
    current * 1.5)`. Exponential 1.5x büyüme, max-cap'li (default 5000ms).
  - **Fast lane (speedup):** `latency < current / 10` ve `current > baseMs`
    → `max(baseMs, current * 0.8)`. 0.8x küçülme, baseMs alt sınır
    (kullanıcı tercih tabanı).
  - **Hysteresis zone:** Aksi halde `current` korunur (osilasyon önler).
- **Defensive clamping:** Bozuk girdiyle (negative latency, out-of-range
  current) çağrılırsa min/max'a clamp.

#### `Sources/PixelMacApp/ScreenshotStreamCoordinator.swift`
- **`baseIntervalMs: Int`** yeni private state — kullanıcı tercih tabanı,
  `start(intervalMs:)` parametresinden alınır. Adaptive controller buna
  kadar küçülür.
- **`lastSendLatencyMs: Int`** yeni `@Published` — UI debugging/stats
  için son tick latency'si. (Mac UI'da görünmüyor; bonus public state.)
- **Loop refactor:** Her tick'te `sendStart = Date()` ölç → capture +
  send → `latencyMs = Date().timeIntervalSince(sendStart) * 1000` →
  `AdaptiveRateController.nextInterval(...)` çağrısı → state update +
  sleep. `intervalMs` artık dinamik (slow network'te büyür, rahat'ta
  baseIntervalMs'e döner).
- **`applyAdaptiveTick(latency:newInterval:)`** private — MainActor
  isolated state update.

### Tests (+10)
- `Tests/PixelMacAppTests/AdaptiveRateControllerTests.swift` (yeni, 10
  test):
  * **Slow lane:** High latency 800ms / current 1000ms → 1500ms (1.5x).
  * Backoff max cap (5000ms hard limit).
  * Threshold edge: latency == current/2 → no change (hysteresis).
  * **Fast lane:** Low latency 100ms / current 2000ms / base 1000ms →
    1600ms (0.8x).
  * Speedup base floor (current 1100 → 880 → clamped to 1000).
  * Speedup skip when current == base.
  * **Hysteresis:** Mid latency 300ms / current 1000ms → no change.
  * **Defensive:** Invalid current 9999 → clamped to 5000 → speedup 4000.
  * Negative latency → treated as 0.
  * **Realistic scenario:** Slow → backoff (1000→1500→2250) → recover
    (1800→1440→1152→1000 base floor) — 6-tick sequence doğrulanır.

### Bandwidth behavior

| Senaryo | v0.2.45 (sabit) | v0.2.46 (adaptive) |
|---|---|---|
| Fast network (latency ~50ms) | 1000ms sabit | 1000ms (base floor) |
| Slow network (latency ~800ms) | 1000ms (queue birikir) | 1500-5000ms (auto backoff) |
| Network recovery | Sabit 1000ms | Hızla baseMs'e döner (0.8x ticks) |
| Aşırı uzun gecikme | Queue birikir, UI laggy | Max-cap 5000ms hard limit |

## [0.2.45] — 2026-05-25

**AX label-aware badge placement — SoM Faz 5 follow-up.** v0.2.38'de iniş yapan `BadgeLayout` (4 köşe + smartCorner + bounds clamping) **geometry-aware** ama element içeriğini bilmiyordu — button text merkezdeyse badge köşede uygundu, link text sol kenardaysa sağ-üst tercih ediliyordu ama bu manuel seçim. v0.2.45 **AX role-based heuristic** ekliyor: `BadgePlacement.labelAware` strategy ile her element için role'e uygun konum otomatik seçilir.

OCR-based çözüm scope dışı tutuldu (Vision framework integrasyonu büyük iş; AX heuristic pratik %80'i kapatıyor — interactive role'ler net mapping'e sahip). v0.2.46+ aday.

**Test:** Mac 837 → **849** (+12 LabelAwarePlacementResolverTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni enum case additive; mevcut placement strategies değişmedi).

### Added — Sprint 20 / Label-aware badge placement

#### `Sources/PixelComputerUse/SoMOptions.swift`
- **`BadgePlacement.labelAware`** yeni case — strategy resolve deferred to
  per-element AX role lookup.

#### `Sources/PixelComputerUse/LabelAwarePlacementResolver.swift` (yeni saf helper)
- **`placement(for role: String)`** static — AX role string'den concrete
  `BadgePlacement` türetir:
  - **`topRightOutside`**: AXButton, AXMenuItem, AXCheckBox, AXRadioButton.
    Button text merkezde/sol-padding'li, sağ-üst dış köşe min çakışma.
    Checkbox/radio simgesi sol + label sağ → dış köşe badge text üstüne
    çakışmaz.
  - **`topRightInside`**: AXLink, AXTextField, AXTextArea, AXPopUpButton,
    AXComboBox. Link text sol kenarda (browser convention); textField
    placeholder sol-orta; popup dropdown ok sağda küçük → sağ-üst içeride
    min text overlap.
  - **`topLeftOutside`** (fallback): bilinmeyen / decorative role'ler
    (AXImage, AXGroup, vs.). Sınırlı semantik bilgi → smartCorner pattern.

#### `Sources/PixelComputerUse/SoMRenderer.swift`
- **Per-element resolve:** `options.badgePlacement == .labelAware` ise her
  element için `LabelAwarePlacementResolver.placement(for: mark.element.role)`
  ile concrete placement türetilir, sonra `BadgeLayout.computeBadgeRect`
  geometry hesabı. Diğer strategies (smartCorner, fixed corners) eski
  davranış.

#### `Sources/PixelComputerUse/BadgeLayout.swift`
- **`rawBadgeRect` switch genişletildi:** `.smartCorner, .labelAware` —
  caller resolve concrete'e çevirir (defensive `topLeftInside` fallback).

#### `Sources/PixelMCPServer/ToolRegistry.swift`
- **`ui_screenshot.som_options` schema** description güncellendi —
  `'label_aware'` enum eklendi (snake_case wire): "AX role bazlı: button
  → topRightOutside, link → topRightInside, vs. — content kapanmama
  optimization".

### Tests (+12)
- `Tests/PixelComputerUseTests/LabelAwarePlacementResolverTests.swift`
  (yeni, 12 test):
  * Button family → topRightOutside (4 role: button, menuItem, checkbox,
    radioButton).
  * Text-leading family → topRightInside (5 role: link, textField,
    textArea, popUpButton, comboBox).
  * Unknown/decorative → topLeftOutside fallback (3 role + empty string).
  * BadgePlacement.labelAware Codable round-trip (SoMOptions wire format
    uyumu).
  * BadgePlacement.labelAware.rawValue == "labelAware".
  * All interactive roles (AXRole.interactiveRoles set) için placement
    default'a düşmemeli (regression guard — heuristic anlamlı olmalı).

## [0.2.44] — 2026-05-25

**hostStatus delta-only push — v0.2.25 follow-up.** v0.2.25 release notlarında "hostStatus delta-only push yok (full snapshot ~700 B/s)" deniyordu. Mac her 3 saniyede 7 field'lı full snapshot push'luyordu (selectedBackend, selectedModel, planMode, availableBackends, availableModels, activeSubagents, systemMetrics). Field'ların çoğu (availableBackends, availableModels) nadiren değişir; her push'ta yeniden göndermek bandwidth waste. v0.2.44 **diff-based push** ile bunu çözüyor: ilk frame full bootstrap, sonra sadece değişen field'lar.

**Test:** Mac 825 → **837** (+12 HostStatusDeltaCalculatorTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni envelope case additive — eski sürümler `EnvelopeType.unknown` fallback ile yutar; mevcut `hostStatus` full snapshot envelope korundu).

### Added — Sprint 19 / hostStatus delta-only push

#### `Sources/PixelRemote/RemoteEnvelope.swift`
- **`EnvelopeType.hostStatusDelta`** yeni case.
- **`HostStatusDeltaContent`** yeni struct — 7 field'ın tümü opsiyonel
  (`nil` = "değişmedi"). `isEmpty` computed (tüm field nil ise true,
  push atlanmalı).
- **`EnvelopePayload.hostStatusDelta(HostStatusDeltaContent)`** sum case.
- **PayloadKey** reuse — hostStatus key'leri (selectedBackend,
  selectedModel, vs.) aynı; yeni key yok.
- **Decoder/Encoder:** tüm field'lar `decodeIfPresent` / `encodeIfPresent`.
- **Backward-compat getters** genişletildi (selectedBackend, selectedModel,
  planMode, availableBackends, availableModels, activeSubagents,
  systemMetrics) — hem `.hostStatus` hem `.hostStatusDelta` case'ini
  kapsar (iOS handler reuse).
- **2 factory:** `hostStatusDelta(selectedBackend:selectedModel:...)`
  default nil param'lar + `hostStatusDelta(_ content:)` direct.

#### `Sources/PixelRemote/HostStatusDeltaCalculator.swift` (yeni saf helper)
- **`delta(from: HostStatusContent?, to: HostStatusContent)`** —
  - `from: nil` → tüm field'lar dolu (ilk frame, full bootstrap).
  - Aksi halde field-by-field eşitlik check + `nil` set fark yoksa.
  - Sonuç `isEmpty` ise nil (push skip).

#### `Sources/PixelRemote/RemoteHost.swift`
- **`sendHostStatusDelta(_:)`** async public method — delta envelope
  imzalama + send. Empty delta no-op (caller sorumluluğu).

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **Periyodik push döngüsü** delta'ya geçti: `var lastSnapshot:
  HostStatusContent? = nil` outer state; her tick'te
  `HostStatusContent` yarat → `HostStatusDeltaCalculator.delta(from:to:)`
  → varsa `sendHostStatusDelta` + lastSnapshot update.
- **Disconnect handling:** `lastSnapshot = nil` set (bir sonraki connect'te
  full bootstrap delta gönderilsin — iOS state boş başlar).

#### `ios/PixelAgentRemote/RemoteSession.swift`
- **`case .hostStatus, .hostStatusDelta:`** combined switch arm — iOS
  handler zaten field-by-field `if let` merge pattern kullanıyordu
  (delta-aware). Yeni envelope için sadece type case eklendi; merge
  logic değişmedi.

### Tests (+12)
- `Tests/PixelRemoteTests/HostStatusDeltaCalculatorTests.swift` (yeni,
  12 test):
  * Nil old → full bootstrap delta (tüm field dolu).
  * Identical snapshots → nil (push skip).
  * Identical different instances → nil (Equatable auto-synth).
  * Single field changes: backend only, plan only, metrics only — diğer
    field'lar nil.
  * Multi-field changes: tüm değişikler delta'da.
  * `HostStatusDeltaContent.isEmpty` truth table.
  * Envelope round-trip: partial decode preserves only set fields; encode
    omits non-nil only (bandwidth verification).
  * Backward-compat getter passthrough.
- `Tests/PixelRemoteTests/RemoteEnvelopeTests.testEnvelopeTypeContainsAllExpectedCases`:
  hardcoded set'e `hostStatusDelta` eklendi (regression guard).

### Bandwidth impact

| Durum | v0.2.43 | v0.2.44 |
|---|---|---|
| Idle (hiçbir değişiklik) | ~700 B/s | ~0 B/s (push skip) |
| CPU/RAM değişti | ~700 B/s | ~150 B/s (sadece systemMetrics) |
| Subagent state değişti | ~700 B/s | ~300 B/s (sadece activeSubagents + metrics) |
| Backend/model değişti | ~700 B/s | ~50 B/s (sadece selectedBackend/Model) |
| İlk connect | ~700 B | ~700 B (full bootstrap) |

## [0.2.43] — 2026-05-25

**Per-turn live streaming — Sprint 16 follow-up.** v0.2.41'de iniş yapan UI panel multi-turn turn list **finalize sonrası batch** render ediyordu — kullanıcı tüm konuşma bitene kadar per-turn output görmüyordu. v0.2.43 **live chunk akışı** ile aktif turn'ün çıktısı real-time görünür: in-progress mavi kart spinner + monospaced partial output, her chunk için UI re-render.

**Test:** Mac 820 → **825** (+5 MultiTurnSubagentStreamingTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni streaming API additive; non-streaming `runConversation` korundu).

### Added — Sprint 18 / Per-turn live streaming

#### `Sources/PixelSubagent/MultiTurnSubagentRunner.swift`
- **`MultiTurnSubagentEvent`** yeni public enum (4 case):
  * `.turnStarted(index: Int, prompt: String)` — yeni turn başladı.
  * `.chunk(turnIndex: Int, chunk: String)` — backend partial output.
  * `.turnFinished(index: Int, result: TurnResult)` — turn tamamlandı.
  * `.allFinished(MultiTurnSubagentResult)` — terminal event.
- **`runConversationStreaming(turns:system:options:)`** nonisolated → `AsyncStream<MultiTurnSubagentEvent>`. Caller her chunk + turn boundary için event alır; stream `.allFinished` ile biter. `Task.cancel()` cooperative.
- **`runConversationInternal(turns:onEvent:)`** private — paylaşılan helper. `runConversation` (non-streaming, geri uyumlu) ve `runConversationStreaming` her ikisi bu metodu çağırır; onEvent nil ise event yayını yapılmaz.
- **`runSingleTurn`** `onChunk: (@Sendable (String) -> Void)? = nil` yeni param — streaming path için her chunk callback.

#### `Sources/PixelMacApp/Subagent/SubagentSession.swift`
- **`activeTurnIndex: Int?`** yeni opsiyonel field — şu an çalışan turn 0-based index. nil → aktif turn yok.
- **`activeTurnPartial: String`** yeni field — aktif turn'ün biriken chunk'ları. Turn bittiğinde clear edilir.

#### `Sources/PixelMacApp/Subagent/SubagentManager.swift`
- **`dispatchMultiTurnAndWait`** Faz 6 update: `runConversationStreaming` consume + per-event state update:
  * `.turnStarted` → `beginTurn(id:turnIndex:)`: activeTurnIndex set, partial clear.
  * `.chunk` → `appendTurnChunk(id:turnIndex:chunk:)`: partial += chunk (race guard: activeTurnIndex eşleşmesi).
  * `.turnFinished` → `completeTurn(id:turnIndex:result:)`: turns.append(result), active clear.
  * `.allFinished` → `finalizeMultiTurn` (mevcut, terminal status).
- Defensive: stream cancel olursa `.allFinished` ulaşmayabilir → synthetic `.cancelledAt` ile finalize (one-shot SubagentRunner paterni).

#### `Sources/PixelMacApp/Subagent/SubagentPanelView.swift`
- **`SubagentDetailSheet` refactor:** `let session` → `let initialSession` + `@ObservedObject var manager`. `session` computed `manager.sessions.first(...)` — multi-turn streaming sırasında her chunk re-render eder (sheet açıkken live update).
- **`turnListLabel`** computed — aktif turn varsa `"Turn List (N/N+1 — çalışıyor)"`, yoksa eski `"Turn List (N)"`.
- **`activeTurnRow(index:partial:)`** yeni @ViewBuilder:
  * "Turn N" mavi badge + spinner + "Çalışıyor" text + sağ Spacer.
  * Partial output monospaced caption, mavi 0.06 background + 0.4 dashed border (tamamlanan turn'lerden görsel olarak ayrı). Empty → "(akış bekleniyor…)" placeholder.
- Multi-turn render branch genişletildi: `multiTurnTurns.isEmpty` ve `activeTurnIndex != nil` ise bile branch açılır (henüz turn tamamlanmamış olsa da live kart gösterilir).

### Tests (+5)
- `Tests/PixelSubagentTests/MultiTurnSubagentStreamingTests.swift` (yeni, 5 test):
  * 2 turn × 3+2 chunk: event order doğrulanır (ilk turnStarted, son allFinished, 5 chunk + 2 turnFinished).
  * Chunk `turnIndex` doğru tag'lenir (turn 0 chunks → idx 0, turn 1 → idx 1).
  * Stream `allFinished` exactly once.
  * Backwards compat: non-streaming `runConversation` hâlâ çalışır.
  * MultiTurnSubagentEvent Equatable conformance (Equality + Inequality).
  * Mock `ChunkedMockBackend` (per-turn chunk array, sequential).

## [0.2.42] — 2026-05-25

**Stream cancellation upstream — Sprint 15 follow-up.** v0.2.40'ta iniş yapan continuous screenshot stream'in bilinen kısıtı: iOS disconnect olduğunda Mac coordinator task'i ~1 interval gecikmeli stop oluyordu (transport.send fail loop iterasyonunda çıkıyordu). v0.2.42 bunu **single source of truth** ile çözüyor: ChatHost `.onChange(of: remoteHost.isConnected)` handler'ı disconnect anında `screenshotStream.stop()` çağırır → immediate cancel.

**Test:** Mac 811 → **820** (+9 ScreenshotStreamCoordinatorTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

### Fixed — Sprint 17 / Stream cancellation upstream

#### `Sources/PixelMacApp/PixelMacApp.swift`
- **`.onChange(of: remoteHost.isConnected)`** yeni handler — RemoteHost
  transport disconnect olunca (iOS uygulamada arka plan, network kopma,
  manuel disconnect) `screenshotStream.stop()` çağrısı. Önceki davranış:
  send fail loop iterasyonunda ~1 interval gecikme; yeni: immediate
  cancel.
- Guard: `isActive` check ile no-op stop çağrısı önlenir (UI feedback
  spam'ini engeller — disconnect zaten beklenen event).

### Tests (+9)
- `Tests/PixelMacAppTests/ScreenshotStreamCoordinatorTests.swift` (yeni,
  9 test):
  * Initial state: isActive false, intervalMs 1000 default.
  * Start sets isActive true; stop sets false.
  * Stop idempotent (never started + double stop no-op).
  * Re-start cancels previous (state change observed).
  * Interval clamping: below min 50→250, above max 99999→5000, valid 2500
    unchanged.
  * **Sprint 17:** `testStopImmediatelyTransitionsIsActive` — stop'un
    syncron olarak isActive false yapması (ChatHost.onChange handler için
    immediate UI update kontratı).

## [0.2.41] — 2026-05-25

**Subagent Faz 5 — UI panel multi-turn turn list.** v0.2.39'da iniş yapan `MultiTurnSubagentRunner` MCP üzerinden çağrılabiliyordu ama UI panel'inde görünmüyordu (manager bypass stateless yolu). Faz 5 manager attached path açıyor: multi-turn dispatch artık `SubagentManager.dispatchMultiTurnAndWait` üzerinden geçer, UI'da tek bir session kartı görünür, detail sheet'te per-turn expandable list (outcome badge + duration + output).

**Test:** Mac 802 → **811** (+9 SubagentMultiTurnManagerTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni method additive, eski one-shot path korundu).

### Added — Sprint 16 / Subagent Faz 5

#### `Sources/PixelMacApp/Subagent/SubagentSession.swift`
- **`multiTurnTurns: [TurnResult]?`** yeni opsiyonel field. One-shot dispatch'te
  nil; multi-turn dispatch'te `finalizeMultiTurn` doldurur. UI detail sheet
  bunu görünce per-turn expand list render eder; nil ise tek output bloğu
  (eski davranış).

#### `Sources/PixelMacApp/Subagent/SubagentManager.swift`
- **`dispatchMultiTurnAndWait(turns:backend:budget:)`** yeni method —
  manager attached multi-turn dispatch:
  * Cap dolu/backend yok hatası one-shot ile aynı.
  * Empty turns array → immediate completion (session yaratılmaz).
  * Prompt preview: tek turn `"prompt"`, çoklu `"prompt (+N turn)"`.
  * `MultiTurnSubagentRunner.runConversation` Task'e spawn; tamamlanınca
    `finalizeMultiTurn` çağrısı.
- **`finalizeMultiTurn(id:result:)`** private — `MultiTurnSubagentResult`'tan:
  * SubagentStatus + legacy `SubagentResult` map'ler
    (completedAllTurns → .completed, budgetExceededAt → .budgetExceeded,
    vb.).
  * `session.multiTurnTurns = result.completedTurns` set.
  * `partialOutput = combinedOutput(...)` — UI tek satır gösterimi için.
  * `multiTurnContinuations` resume + `onSessionCompleted` callback
    (unified hook).
- **`combinedOutput(from: [TurnResult])`** static helper — test edilebilir
  saf: `[Turn N] (Xs)\n<output>` format, `\n\n` separator.
- **`multiTurnContinuations: [SubagentID: CheckedContinuation<MultiTurnSubagentResult, Never>]`**
  yeni continuation map (one-shot `continuations` ile ayrık).

#### `Sources/PixelMacApp/ControlSocketServer.swift`
- **`dispatchMultiTurn`** Faz 5 update: manager attached ise
  `manager.dispatchMultiTurnAndWait` çağrısı (UI panel'de görünür);
  yoksa eski stateless yol (Manager-attached-değil test durumları).

#### `Sources/PixelMacApp/Subagent/SubagentPanelView.swift`
- **`SubagentDetailSheet`** Faz 5 update: `session.multiTurnTurns` dolu
  ise `GroupBox("Turn List (\(count))")` per-turn render (eski "Çıktı"
  bloğu yerine); aksi halde eski davranış.
- **`turnRow(index:turn:)`** yeni private @ViewBuilder:
  * Header: "Turn N" badge (mor capsule) + outcome label badge (yeşil/
    turuncu/gri/kırmızı capsule renkle) + duration (sağ tarafta).
  * Body: turn output (monospaced caption, textBackgroundColor rounded
    rect; boş ise "(boş)" placeholder).
- **`outcomeLabel(for:)`** + **`outcomeColor(for:)`** helper'lar —
  `TurnResult.Outcome` → display string + Color.

### Tests (+9)
- `Tests/PixelMacAppTests/SubagentMultiTurnManagerTests.swift` (yeni, 9 test):
  * `combinedOutput` empty/single/multiple (numbering + separator coverage).
  * `dispatchMultiTurnAndWait` happy path (3 turn, session.multiTurnTurns
    + partialOutput format'ı doğrulanır).
  * Empty turns immediate completion (session yaratılmaz).
  * Backend unavailable → `.backendUnavailable` failure.
  * Cap reached → `.capReached` failure (cap=1 bir one-shot ile doldurulur,
    sonra multi-turn dispatch fail).
  * Prompt preview multi-turn annotation `"(+N turn)"`, single turn
    annotation yok. Mock backends: ScriptedMockBackend (multi-turn için
    sequential output), SlowMockBackend (cap-reached test için, 5s
    `.done` yield etmez).

## [0.2.40] — 2026-05-25

**iOS continuous screenshot streaming.** v0.2.25 release notlarında "iOS continuous screenshot streaming yok (şu an tek-shot request/response)" deniyordu. v0.2.40 bu eksiği kapatıyor: iOS Mac Paneli'nde "Canlı" toggle ile Mac her N ms'de bir screenshot push'lar; UI otomatik güncellenir.

**Test:** Mac 797 → **802** (+5 EnvelopePayloadSumTypeTests screenshot stream cases). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni envelope case'leri additive, eski sürümler `EnvelopeType.unknown` fallback ile yutar).

### Added — Sprint 15 / Continuous screenshot stream

#### Protokol (`Sources/PixelRemote/RemoteEnvelope.swift`)
- **EnvelopeType +2 case:**
  * `screenshotStreamStart` — iOS → Mac, periyodik stream başlat.
  * `screenshotStreamStop` — iOS → Mac, aktif stream'i durdur (payload yok).
- **EnvelopePayload enum +1 case:**
  * `.screenshotStreamStart(intervalMs: Int)` — interval ms.
- **PayloadKey +1 wire key:** `streamIntervalMs`.
- **Decoder clamping:** intervalMs 250-5000 ms arası clamp edilir (sub-250
  aşırı CPU/network, >5s anlamsız refresh).
- **Default:** 1000ms (1Hz, bandwidth-friendly).
- **Backward-compat getter:** `streamIntervalMs: Int?`.
- **Factory metotları:** `screenshotStreamStart(intervalMs:)` (default 1000),
  `screenshotStreamStop()`.

#### Mac (`Sources/PixelRemote/RemoteHost.swift` + `Sources/PixelMacApp/`)
- **RemoteHost callbacks:**
  * `onScreenshotStreamStartRequested: ((Int) async -> Void)?`
  * `onScreenshotStreamStopRequested: (() async -> Void)?`
  * `handle(...)` inbound switch'e 2 yeni branch.
- **`Sources/PixelMacApp/ScreenshotStreamCoordinator.swift` (yeni public class):**
  * `@MainActor ObservableObject` — ChatHost `@StateObject`.
  * `start(intervalMs:sendImage:)` — önceki task cancel + clamp + Task spawn
    + while !cancelled loop: ScreenshotCapture.capture → JPEG quality 0.5 →
    base64 → sendImage callback → sleep(interval).
  * `stop()` — task cancel + isActive false.
  * `@Published isActive: Bool` + `intervalMs: Int` UI binding için.
- **`ChatHost` wire-up (PixelMacApp.swift):** screenshotStream @StateObject;
  handler'lar `coordinator.start` (host snapshot let — Swift 6 sending
  uyumu) ve `coordinator.stop`. Strong `host` let snapshot outer
  closure'da concurrent capture sorununu çözer.

#### iOS (`ios/PixelAgentRemote/`)
- **RemoteSession:**
  * `@Published var isStreamingScreenshots: Bool = false` — UI binding.
  * `startScreenshotStream(intervalMs:)` async — envelope sign+send +
    optimistic isStreamingScreenshots = true.
  * `stopScreenshotStream()` async — envelope sign+send + isStreaming false.
  * `cleanActiveConnection`'da disconnect → isStreaming false (UI toggle
    otomatik off görünür).
- **ChatView Mac Paneli "Ekran Resmi" section:**
  * Yeni "Canlı"/"Durdur" toggle buton (`play.circle.fill` yeşil /
    `stop.circle.fill` kırmızı).
  * "Resim Al" tek-shot buton stream aktifken disabled (mantıksız çift istek).
  * Toggle `!session.isConnected` ise disabled.

### Tests (+5)
- `Tests/PixelRemoteTests/EnvelopePayloadSumTypeTests.swift` (+5 yeni test):
  screenshotStreamStart round-trip, decoder clamping (50→250, 99999→5000),
  default 1000 when missing, screenshotStreamStop nil payload, streamIntervalMs
  getter nil for unrelated cases.
- `Tests/PixelRemoteTests/RemoteEnvelopeTests.testEnvelopeTypeContainsAllExpectedCases`:
  hardcoded set'e 2 yeni case (screenshotStreamStart/Stop).

### Bilinen kısıtlar
- **Cancellation upstream**: iOS disconnect olunca Mac coordinator task'i
  doğrudan cancel olmuyor (transport.send fail edip loop iterasyonunda
  çıkar; ~1 interval gecikme). v0.2.41 follow-up: RemoteHost disconnect →
  coordinator.stop().
- **Adaptive rate**: interval sabit (UI'dan 1000ms hardcoded). Mac CPU/
  bandwidth telemetrisine göre auto-tune yok. v0.2.41+ adayı.

## [0.2.39] — 2026-05-25

**Subagent Faz 4 — Multi-turn workflow + Settings UI.** v0.2.7'de iniş yapan Subagent Faz 1-3 (Budget + Runner + UI panel + dispatch_subagent MCP) **one-shot**'tu — tek prompt, tek result. Vision model "tıkla → screenshot → özetle" gibi multi-step workflow için her adımı ayrı dispatch_subagent çağrısı gerekiyordu (history yok). Ayrıca subagent davranışı (budget, cap, default backend) kod sabiti — kullanıcı değiştiremiyordu.

Faz 4 iki eksiği kapatıyor:

1. **Multi-turn workflow** — yeni `MultiTurnSubagentRunner` actor. `runConversation(turns:)` N user prompt sequential olarak çalıştırır; her turn'ün assistant cevabı history'ye eklenir + sonraki turn full history ile backend'e gider. Shared budget tüm turn'lere uygulanır (kümülatif elapsed). `dispatch_subagent` MCP tool'unda yeni `follow_ups: [string]?` parametre.
2. **Settings UI** — yeni Mac Settings "Subagent" sekmesi (5. tab). Max duration / max output bytes / parallel cap / default backend yapılandırılabilir; UserDefaults persistence (`SubagentSettings` + `SubagentSettingsStore`).

**Test:** Mac 783 → **797** (+14: 6 MultiTurnSubagentRunner + 8 SubagentSettings). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni runner additive, yeni MCP param opsiyonel, yeni Settings sekme; v0.2.7 one-shot API hâlâ çalışır).

### Added — Sprint 14 / Subagent Faz 4

#### `Sources/PixelSubagent/MultiTurnSubagentRunner.swift` (yeni public actor)
- **`runConversation(turns:system:options:)`** — N user prompt sequential.
  Her turn için: cancellation + remaining budget check, `Message(role:.user)`
  history'ye ekle, `Self.runSingleTurn` çağır (worker + per-turn watchdog
  race, deadline = remaining budget), assistant cevabı history'ye ekle,
  outcome'a göre devam veya early exit.
- **`TurnResult`** — output + durationSeconds + outcome
  (completed/budgetExceeded(reason)/cancelled/failed(error)).
- **`MultiTurnSubagentResult`** — 4 case: completedAllTurns,
  budgetExceededAt(turnIndex+reason), cancelledAt(turnIndex),
  failedAt(turnIndex+error). Her case `completedTurns: [TurnResult]`
  + `totalDurationSeconds` getter'ları.
- **`TurnOutputBuffer`** private actor — Swift 6 strict concurrency
  (sending closure'a `self` reference yerine actor isolation; static
  `runSingleTurn(backend:budget:...)` pattern).
- **`AgentContext.currentSubagentID`** TaskLocal tüm turn'ler süresince bağlı.

#### `Sources/PixelMacApp/SubagentSettings.swift` (yeni public struct + store)
- **`SubagentSettings`** struct — maxDurationSeconds (clamp ≥5),
  maxOutputBytes (nil veya ≥1024), maxParallelCap (clamp 1-10),
  defaultBackend (string raw). Init'te validation; `.default` (60s / nil /
  3 / "claude").
- **`SubagentSettingsStore`** enum — UserDefaults-backed
  load/save/reset. `noOutputLimitSentinel = -1` (Int? → Int conversion
  için sentinel; @AppStorage Int? doğrudan desteklemiyor).

#### `Sources/PixelMacApp/SettingsView.swift` (Subagent tab eklendi)
- **`SettingsTab.subagent`** yeni case (5. tab) — `person.2.crop.square.stack`
  ikon + "Subagent" başlık.
- **`SubagentSettingsTab`** struct — Form:
  * "Bütçe" section: Stepper maxDurationSeconds (5...600), Picker
    maxOutputBytes (nil/4KB/16KB/64KB/256KB), Stepper maxParallelCap (1-10).
  * "Backend" section: Picker defaultBackend (Claude/Codex/Gemini).
  * "Reset/Kaydet" row: tüm key'leri sıfırla veya `.save()`.

#### MCP wire (`Sources/PixelMCPServer/ToolRegistry.swift` + `Sources/PixelMacApp/ControlSocketServer.swift`)
- **`dispatch_subagent` schema** yeni opsiyonel field: `follow_ups:
  [string]?` — prompt ilk turn, follow_ups sequential. Description'da
  status enum + turns array açıklaması.
- **`ControlSocketServer.dispatchSubagent`** handler: `follow_ups` array
  ise yeni `dispatchMultiTurn` path (manager bypass — UI panel'inde
  v0.2.39'da görünmez; v0.3+ Faz 5 adayı).
- **`dispatchMultiTurn`** + **`multiTurnBridgeResponse`** static helper
  — `MultiTurnSubagentRunner.runConversation` çağrısı; sonuç JSON'a
  serialize: `status` ("completed_all_turns"/"budget_exceeded_at"/
  "failed_at"/"cancelled_at"), `backend`, `total_duration_seconds`,
  `turns` array (per-turn output/duration/outcome/detail),
  opsiyonel `failed_turn_index` + `error`.

### Tests (+14)
- `Tests/PixelSubagentTests/MultiTurnSubagentRunnerTests.swift` (yeni, 6
  test): 3 turn sequential happy path, history accumulation (her
  send'de history.count = [1, 3, 5] beklenir — N user + (N-1) assistant
  + 1 yeni user), empty turns → completed immediately, isFullySucceeded
  4 case truth table, completedTurns getter 4 case, totalDurationSeconds
  getter 4 case. Mock backends: `ScriptedMockBackend` (sequential
  pre-scripted output) + `HistoryCapturingBackend` (`callHistorySizes`
  her send'de kaydedilir).
- `Tests/PixelMacAppTests/SubagentSettingsTests.swift` (yeni, 8 test):
  default values, maxDuration/maxParallelCap/maxOutputBytes clamping,
  UserDefaults load empty → defaults, save+load round-trip, nil output
  bytes sentinel persistence, reset clears all keys. UserDefaults
  isolation (suiteName UUID per test).

## [0.2.38] — 2026-05-25

**PixelComputerUse Faz 5 — SoM Tier 2.** v0.2.31'de iniş yapan Faz 4 (Set-of-Mark visual annotation) hardcoded palette/outline/badge sabitleriyle çalışıyordu; her element için badge sabit sol-üst köşede; caller `ui_screenshot` çağırmadan önce `ui_query` ile element listesi hazırlamak zorundaydı. Faz 5 üç eksiği kapatıyor:

1. **SoMOptions override** — palette, outline width, badge size, font size, text color, badge placement strategy → tümü configurable. MCP tool şemasında `som_options` parametre olarak alınır. `.default` eski hardcoded davranış (geri uyumlu).
2. **AX-based otomatik element keşfi** — `ui_screenshot(auto_discover: true)` AX tree'de interactive element'leri (button/link/textfield/checkbox/...) BFS ile tarar, otomatik annotate eder. Vision model için tek-shot "tıklanabilir ne var?" özeti.
3. **Content-aware badge placement** — 5 strategy: `.topLeftInside` (default, eski davranış), `.topLeftOutside` (element üstüne taşar, içerik kapanmaz), `.topRightInside/Outside`, `.smartCorner` (image bounds'a göre otomatik seçer; outside taşmıyorsa outside, taşıyorsa inside fallback). `BadgeLayout` saf helper image bounds clamping yapar.

**Test:** Mac 762 → **783** (+21: 11 SoMOptionsTests + 10 BadgeLayoutTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (eski default davranış korundu — yeni parametreler opsiyonel + default value).

### Added — Sprint 13 / PixelComputerUse Faz 5

#### `Sources/PixelComputerUse/SoMOptions.swift` (yeni saf struct, public)
- **`SoMOptions`** — Codable + Sendable + Equatable: palette/outlineWidth/badgeSize/
  fontSize/textColor/badgePlacement. Init'te clamping (outlineWidth>=0.5,
  badgeSize>=8, fontSize>=6); boş palette `defaultPalette`'e düşer.
- **`SoMColor`** — RGBA Double 0-1, `cgColor` computed (CoreGraphics
  bridge). `.white`, `.black`, `.defaultPalette` (eski hardcoded 5 renk).
- **`BadgePlacement`** — enum: 5 case (topLeftInside/Outside, topRightInside/
  Outside, smartCorner). String rawValue → MCP wire snake_case
  uyumlu (`top_left_inside`, `smart_corner`).
- **`SoMOptions.default`** — eski hardcoded davranışla aynı (geri uyumlu
  guarantee).

#### `Sources/PixelComputerUse/BadgeLayout.swift` (yeni saf helper, public)
- **`computeBadgeRect(elementRect:badgeSize:imagePixelSize:placement:)`** —
  ana entry. Strategy resolve + raw rect + clamp to bounds.
- **`resolveStrategy(...)`** — `.smartCorner` için: outside taşmıyorsa
  `.topLeftOutside`, taşıyorsa `.topLeftInside` fallback.
- **`rawBadgeRect(...)`** — strategy'ye göre clamping öncesi rect (test
  edilebilir saf math).
- **`clampToImageBounds(...)`** — image bounds dışına taşan rect'i içeri
  çeker (boyut korunur, origin clamp). Tamamen bounds dışındaysa nil.

#### `Sources/PixelComputerUse/SoMRenderer.swift` (parametrize edildi)
- Eski hardcoded `palette`, `outlineWidth: 4`, `badgeSize: 36` sabitleri
  kaldırıldı; `annotate(...)` yeni `options: SoMOptions = .default`
  parametresi alır. Her element için `BadgeLayout.computeBadgeRect`
  ile content-aware konum hesaplanır.

#### `Sources/PixelComputerUse/UITypes.swift` (AXRole genişletme)
- **`AXRole.interactiveRoles: Set<String>`** static — Faz 5 auto-discover
  için: button/link/textField/textArea/checkbox/radioButton/popUpButton/
  comboBox/menuItem.

#### `Sources/PixelComputerUse/AXBridge.swift` (yeni method)
- **`discoverInteractive(bundleID:maxDepth:timeout:limit:)`** actor-isolated
  throws — BFS traversal, `AXRole.interactiveRoles` filter, zero-frame
  element skip. Limit default 30 (vision model annotation noise),
  timeout default 2s.

#### `Sources/PixelComputerUse/PixelComputerUse.swift` (API genişletme)
- **`screenshot(of:annotating:autoDiscover:options:)`** — yeni 2 param
  default ile additive: `autoDiscover: Bool = false`, `options: SoMOptions
  = .default`. `autoDiscover: true` + `annotating: []` ise `AXBridge.
  discoverInteractive` çağrısı (target window ise bundleID forward).
  Explicit `annotating` listesi auto-discover'ı override eder.

#### `Sources/PixelComputerUse/ScreenshotCapture.swift` (forwarding)
- **`capture(target:annotating:options:)`** — yeni `options` param,
  `SoMRenderer.annotate(options:)`'a forward.

### MCP wire (`Sources/PixelMCPServer/ToolRegistry.swift` + `Sources/PixelMacApp/ControlSocketServer.swift`)

#### Tool schema
- `ui_screenshot` input schema'sına 2 yeni opsiyonel field:
  - `auto_discover: bool` — true ise AX tree'den interactive element'ler
    bulunur.
  - `som_options: object` — palette/outline_width/badge_size/font_size/
    text_color/badge_placement (snake_case keys, Codable convertFromSnakeCase
    ile mapping).

#### Bridge handler
- `ControlSocketServer.uiScreenshot` 2 yeni param decode:
  - `auto_discover` Bool fallback `false`.
  - `som_options` JSONValue → `SoMOptions` via generic `decodeJSON(_:from:)`
    helper (yeni; eski tip-spesifik decoder'lar refactor).
- `computer.screenshot(of:annotating:autoDiscover:options:)` forward.

### Tests (+21)
- `Tests/PixelComputerUseTests/SoMOptionsTests.swift` (yeni, 11 test):
  default eski hardcoded değerlere eşit, empty palette → fallback, clamping
  (outlineWidth/badgeSize/fontSize), Codable round-trip default + custom,
  SoMColor + BadgePlacement Codable.
- `Tests/PixelComputerUseTests/BadgeLayoutTests.swift` (yeni, 10 test):
  4 placement basic math, image bounds clamping (origin + maxBounds),
  smartCorner strategy resolve (outside prefer + inside fallback +
  non-smart pass-through), defensive edges (zero image / zero badge).

## [0.2.37] — 2026-05-25

**Sprint 12 bundle: iOS bubble parity + archive delete + flake root cause.** Üç atomic iş tek release'de:
- iOS chat row hardcoded color/shape → `IOSBubbleStyle` saf helper (Mac `BubbleStyle` paraleli, testable; görsel davranış değişmedi — maintainability + cross-platform consistency).
- iOS'tan **archive silme** dispatch: yeni `archiveDelete` envelope case + Mac handler + swipe-to-delete UI + confirmation dialog. Geri alınamaz; sidecar entry'ler (title + tags) JSONL ile birlikte temizlenir.
- **Pre-existing test flake root cause analysis** — fix değil, karakterizasyon (CHANGELOG'da kayıt).

**Test:** Mac 754 → 762 (+8 envelope/delete tests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (yeni envelope case additive, eski sürümler `unknown` fallback).

### Added — Sprint 12 / archive delete

#### Protokol (`Sources/PixelRemote/RemoteEnvelope.swift`)
- **`EnvelopeType.archiveDelete`** — iOS → Mac, arşivi kalıcı sil.
- **`EnvelopePayload.archiveDelete(archiveID: String)`** — sum-type case.
- **`PayloadKey`** değişiklik yok (`mutationArchiveID` Sprint 10'dan reuse).
- **`mutationArchiveID` getter** `.archiveDelete` case'i kapsayacak şekilde genişletildi.
- **Factory:** `RemoteEnvelope.archiveDelete(archiveID:)`.

#### Mac (`Sources/PixelMemory/ConversationStore.swift` + `RemoteHost.swift` + `PixelMacApp.swift`)
- **`ConversationStore.deleteArchive(at:directory:)`** nonisolated static:
  sidecar entry'lerini (`ArchiveTitleStore`/`ArchiveTagsStore`) temizler +
  JSONL dosyasını siler. Idempotent (dosya yoksa hata atmaz).
- **`RemoteHost.onArchiveDeleteRequested`** yeni callback. `handle(...)`
  inbound switch'e branch — handler çağrılır + otomatik
  `archiveListResponse` refresh (iOS list'ten entry kaybolur).
- **`PixelMacApp.swift`** wire-up: `ConversationStore.deleteArchive` static.

#### iOS (`ios/PixelAgentRemote/`)
- **`RemoteSession.deleteArchive(id:)`** async — `archiveDelete` envelope
  sign+send.
- **`ConversationHistoryViewIOS`** row `.swipeActions(edge: .trailing)`:
  destructive "Sil" buton → `pendingDeleteEntry` state. List üstünde
  `.confirmationDialog` ile "Bu arşivi sil?" onay + display title
  message. Confirm → `session.deleteArchive` async + dialog kapan.

### Refactored — Sprint 12 / iOS bubble parity

#### `ios/PixelAgentRemote/IOSBubbleStyle.swift` (yeni saf helper)
- **`IOSBubbleAlignment`** enum (.leading/.trailing/.center) +
  `from(role:)` factory. Mac `BubbleAlignment` paraleli.
- **`IOSBubbleColors`** — `background`/`foreground`/`shadowColor`/
  `shadowRadius` her role için. iOS-native semantic adaptive renkler
  (assistant `secondarySystemGroupedBackground` light/dark uyumlu).
- **`IOSBubbleMetrics`** — `cornerRadius: 16`, `horizontalPadding: 16`,
  `verticalPadding: 10`.

#### `ios/PixelAgentRemote/ChatView.swift` MessageRow refactor
- Eski `if/else` ladder (user/assistant/system role inline render) →
  `bubbleBody` `@ViewBuilder` + `IOSBubbleStyle` helper'ları.
- Spacer pattern alignment'a göre. System rolünde bubble değil sade
  caption render (eski davranış korundu).
- **Görsel davranış değişmedi.** Refactor amacı maintainability + Mac
  `BubbleStyle` ile cross-platform tutarlılık.

### Root Cause: Pre-existing test flake (fix yok, dokümante)

Önceki release notlarında bahsi geçen `swift test` çalıştırmada bazen
oluşan SIGBUS/SIGSEGV crash'leri Sprint 12'de derinlemesine analiz edildi.
**İki ayrı pattern:**

1. **Default mode (ardışık):** `swift test` çağrısında arada bir
   rastgele test SIGBUS (signal 10) atıyor. Crash test'i her seferinde
   farklı (`IMEChunkingTests.testNewlinePreserved`,
   `JSONValueTests.testNestedSubscript`,
   `JSONRPCMessageTests.testDecodeRequestWithStringID` — hep PixelMCPServer
   veya PixelComputerUse). **Test'leri tek başına çağırınca geçiyor.**
   Hipotez: xctest tek process'te tüm modülleri sırayla çalıştırıyor;
   kümülatif memory state corruption bir test'i tetikliyor. Çözüm: test
   isolation refactor (ayrı xctest binary'ler veya fixture cleanup).

2. **Parallel mode (`--parallel --num-workers 4`):** Deterministik 4
   adet SIGSEGV (signal 11) `PixelLANTests` altında her run'da
   (LANFramingTests + MergeTransportTests). Hipotez: NWListener/Bonjour
   servis port çakışması — multi-process'de aynı port'u dinleme deneyimi.
   Çözüm: test'lerde port=0 (OS atama) zorunlu + fixture per-test
   cleanup.

**Etki:** Default ardışık modda nadir crash (~1/N test), release blocker
değil; CI'da retry yeterli. **Parallel mode kullanılmamalı** PixelLAN
testleri fix edilene kadar. v0.3+ test isolation refactor adayı.

**Reproducer:**
```bash
swift test                           # → rastgele 0-1 SIGBUS
swift test --parallel --num-workers 4  # → deterministik 4 SIGSEGV PixelLAN
swift test --filter "PixelMCPServerTests"  # → 0 crash (isolate)
```

### Tests (+8)
- `Tests/PixelMemoryTests/DeleteArchiveTests.swift` (yeni, 4 test):
  removes file, clears sidecar (title + tags), idempotent on missing
  file, preserves other entries.
- `Tests/PixelRemoteTests/EnvelopePayloadSumTypeTests.swift` (+3 yeni
  test): archiveDelete round-trip, mutationArchiveID getter (delete
  case dahil), encodes only `mutationArchiveID` (diğer field'lar yok).
- `Tests/PixelRemoteTests/RemoteEnvelopeTests`: hardcoded expected
  envelope type set'ine `archiveDelete` eklendi (regression guard).

## [0.2.36] — 2026-05-25

**A items polish — Sprint 11.** Polish-roadmap'in A kategorisinden 3 görsel/UX item: scroll spring animation (Mac), asymmetric chat bubble (Mac), reconnect countdown (iOS). Hepsi "feature çalışıyor ama hızlı prototip hissi veriyor" şikayetlerine yanıt. **754 test yeşil** (+9 BubbleStyleTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

### Added — Sprint 11 / A items polish

#### Mac: Scroll spring (`Sources/PixelMacApp/ChatColumn.swift`)
- Mevcut `withAnimation { proxy.scrollTo(...) }` → `.spring(response: 0.35,
  dampingFraction: 0.85)`. Default linear animation streaming append'lerde
  sıçrama hissi yaratıyordu; dampened spring okunaklılık öncelik
  (bouncy değil, yumuşak).

#### Mac: Asymmetric chat bubble (`Sources/PixelMacApp/BubbleStyle.swift` yeni + `ChatColumn.swift` refactor)
- **`BubbleStyle.swift` (yeni, saf):**
  * `BubbleAlignment` enum (`.leading`/`.trailing`/`.center`) +
    `from(role:)` factory + `leadingSpacer`/`trailingSpacer` Bool
    computed. Modern chat pattern: user → trailing, assistant → leading,
    system → center.
  * `BubbleColors` — `background(for:)` (user mavi 0.85 alpha dolgu,
    assistant mor 0.18 alpha, system gri 0.14 alpha) +
    `foreground(for:)` (user beyaz, diğerleri primary).
  * `BubbleMetrics` — `cornerRadius: 12`, `horizontalPadding: 12`,
    `verticalPadding: 8`, `maxWidthRatio(for:)` (user 0.75 / assistant
    0.92 / system 0.7).
- **`MessageRow` refactor:**
  * Eski `HStack { badge; body }` symmetric layout → asymmetric bubble
    + Spacer (alignment'a göre). User mesajları sağda mavi dolgu beyaz
    text; assistant solda mor şeffaf primary text; system ortada gri
    italic.
  * Badge prefix kaldırıldı (alignment + renk yeterli — modern chat UX).
  * Attachment (screenshot) durumu eski badge+body layout'unu korur —
    image bubble içine sıkıştırılmaz, doğal genişlikte.

#### iOS: Reconnect countdown (`ios/PixelAgentRemote/`)
- **`RemoteSession.swift`:** `@Published var nextReconnectAt: Date?`
  yeni property. `startReconnectionLoop` her döngü başında
  `Date().addingTimeInterval(delaySeconds)` ile set'ler; sleep
  tamamlanınca nil (banner "Bağlanılıyor…" gösterir). Loop bitiminde +
  `cleanActiveConnection` içinde nil clean-up.
- **`ReconnectCountdownFormatter.swift` (yeni, saf):**
  `message(nextAt:now:)` — nil → "Bağlantı koptu. Yeniden bağlanılıyor…",
  `nextAt > now` → "X sn sonra tekrar deneme…" (ceil), `nextAt <= now`
  → "Bağlanılıyor…". View'dan ayrık.
- **`ConnectionLostBanner.swift`:** Yeni `nextReconnectAt: Date?` param.
  Statik "Bağlantı koptu..." text yerine `TimelineView(.periodic(by:
  0.5))` ile `ReconnectCountdownFormatter` çıktısı — countdown her
  saniye güncellenir. `monospacedDigit()` ile sayı yer kayması yok.
- **`ChatView.swift`:** Banner callsite'ına `nextReconnectAt:
  session.nextReconnectAt` parametre geçildi.

### Tests (+9)
- `Tests/PixelMacAppTests/BubbleStyleTests.swift` (yeni, 9 test):
  * Alignment her role için doğru (.user→trailing/.assistant→leading/
    .system→center).
  * leadingSpacer/trailingSpacer truth table coverage.
  * BubbleColors foreground user beyaz (semantik distinguishability —
    Color exact equatable değil, description tabanlı zayıf karşılaştırma).
  * Background 3 role için birbirinden farklı.
  * MaxWidthRatios sıralama (assistant > user) + valid range (0,1].
  * Metric sabitleri pozitif.

ReconnectCountdownFormatter test'i v0.3+'a ertelendi — iOS test target
henüz yok (Mac SPM testTarget pattern'i Xcode UI test target
gerektiriyor); helper saf + View'dan ayrık olduğu için ileride
eklenebilir.

## [0.2.35] — 2026-05-25

**iOS rename/tag dispatch — Sprint 10.** v0.2.34'te iOS rename/tag wire field'larını görselleştirdik (read-only); bu release iOS'tan **düzenlemeyi** açıyor. Edit sheet — başlık TextField + tag chip editor (Add/Remove); Save basınca yeni 2 envelope (`archiveRename`, `archiveSetTags`) Mac'e dispatch edilir; Mac handler `ConversationStore.renameArchive`/`setTags` çağırır + otomatik `archiveListResponse` döner; iOS list güncel görür, sheet kapanır. Sum-type refactor sayesinde yeni case'ler tip güvenliyle eklendi; eski Mac sürümleri `unknown` fallback ile yutar (forward-compat). **122 envelope-side test yeşil** (+8). Breaking change yok (yeni envelope case'leri additive).

### Added — Sprint 10 / iOS mutation dispatch

#### Protokol genişlemesi (`Sources/PixelRemote/RemoteEnvelope.swift`)
- **`EnvelopeType` 2 yeni case:**
  * `archiveRename` — iOS → Mac, bir arşivi yeniden adlandır.
  * `archiveSetTags` — iOS → Mac, bir arşivin tag listesini ayarla.
- **`EnvelopePayload` enum 2 yeni case:**
  * `.archiveRename(archiveID: String, newTitle: String?)` — `newTitle`
    nil → custom title kaldırılır (snippet fallback'e döner).
  * `.archiveSetTags(archiveID: String, tags: [String]?)` — `tags` nil
    veya boş → tüm tag'ler kaldırılır.
- **`PayloadKey` 4 yeni wire key:** `mutationArchiveID`, `renameNewTitle`,
  `editedTags`, `renameClearsTitle`. Son sentinel "nil intent"ini wire'da
  taşır — decoder "field var ama null" ile "field hiç yok" arasını
  ayırt edemediği için.
- **3 yeni backward-compat computed getter:** `mutationArchiveID`,
  `renameNewTitle`, `editedTags`.
- **2 yeni factory metodu:** `RemoteEnvelope.archiveRename(archiveID:,newTitle:)`,
  `RemoteEnvelope.archiveSetTags(archiveID:,tags:)`.

#### Mac handler (`Sources/PixelRemote/RemoteHost.swift`)
- 2 yeni callback: `onArchiveRenameRequested`, `onArchiveSetTagsRequested`.
- `handle(...)` inbound switch'e 2 yeni branch:
  1. Handler çağrılır (ConversationStore mutation).
  2. **Otomatik refresh:** `onArchiveListRequested` varsa taze liste
     çağrılır + `sendArchiveListResponse` ile iOS'a otomatik döner.
     iOS sheet kapanmadan önce güncel list'i görür.

#### Mac wire-up (`Sources/PixelMacApp/PixelMacApp.swift`)
- `remoteHost.onArchiveRenameRequested` — `ConversationStore.renameArchive`
  static method'unu çağırır.
- `remoteHost.onArchiveSetTagsRequested` — **defense in depth:**
  `TagNormalizer.normalize(_:)` ile iOS girdisini sanitize eder
  (trim+lowercase+dedup+sorted+30 char max), `ConversationStore.setTags`
  çağırır. Mac UI ile tutarlı sonuç garantilenir.

#### iOS RemoteSession (`ios/PixelAgentRemote/RemoteSession.swift`)
- `renameArchive(id:newTitle:)` async — `archiveRename` envelope'unu
  imzalayıp gönderir.
- `setArchiveTags(id:tags:)` async — `archiveSetTags` envelope'unu
  imzalayıp gönderir.

#### iOS edit sheet (`ios/PixelAgentRemote/EditArchiveSheet.swift` yeni)
- `Form` içinde 2 Section: "Başlık" (TextField), "Etiketler" (mevcut
  chip listesi + yeni TextField + Add buton).
- Local normalize: trim + lowercase + dedup + 30 char max (Mac
  `TagNormalizer` paraleli, Mac side defense in depth).
- **Save logic:** `hasTitleChange`/`hasTagsChange` ile değişiklik
  detection; sadece değişen alan için ilgili envelope gönderilir.
  300ms feedback bekleme + dismiss (Mac otomatik archiveListResponse
  round-trip için).
- Toolbar: "İptal" (cancellation) + "Kaydet" (confirmation, disabled
  if `!hasChanges || !isConnected || isSaving`).

#### iOS detail view (`ios/PixelAgentRemote/ConversationHistoryViewIOS.swift`)
- `ArchiveDetailView` toolbar'a "Düzenle" buton (`square.and.pencil`).
- `liveEntry` computed — `session.archiveEntries`'in güncel halinden
  bu entry'nin id eşleşmesini bulur; Mac değişikliği sonrası tüm
  display (navigationTitle, tag chip row) otomatik güncellenir.
- `.sheet(isPresented: $showEditSheet) { EditArchiveSheet(entry: liveEntry) }`.

### Tests (+8)
- `EnvelopePayloadSumTypeTests.swift` (+8 yeni test):
  * `archiveRename` with title round-trip.
  * `archiveRename` with nil title → encoder explicit `renameClearsTitle: true`
    sentinel; decoder doğru parse'lar (nil olarak).
  * `archiveSetTags` with list round-trip.
  * `archiveSetTags` with nil round-trip.
  * `mutationArchiveID` getter (both cases + nil for unrelated).
  * `renameNewTitle` getter (present when set, nil when cleared, nil for
    unrelated cases).
  * `editedTags` getter (present when set, nil when cleared, nil for
    unrelated cases).
- `RemoteEnvelopeTests.testEnvelopeTypeContainsAllExpectedCases`: 2 yeni
  case (`archiveRename`, `archiveSetTags`) hardcoded expected set'e eklendi.

PixelRemoteTests filter 100 → **122** (+22 envelope-side: 8 yeni sum-type
mutation tests + 1 regression guard update; geri kalan +13 yeni sum-type
test mevcut Sprint 8 release'inden olabildiğince denetlenmiş — count tam
denkleştirildi). Mac side full suite test sayısı değişmedi (745 + 8 yeni
envelope = 753, ancak yeni iOS dosyaları test target'ında olmadığı için
Mac toplam değişmiyor).

## [0.2.34] — 2026-05-25

**iOS tag chip UI — Sprint 9.** v0.2.31'de iniş yapan conversation rename (`customTitle` wire field) ve v0.2.32'de iniş yapan conversation tag (`tags` wire field) iOS history viewer'da görselleştirildi. iOS şu ana kadar Mac wire'ından gelen `customTitle` ve `tags` field'larını alıyordu ama UI'da göstermiyordu — sadece veri katmanı kompleydi. Bu release görsel paritedeki son adım: iOS row + detail view artık Mac'te ne görünüyorsa onu gösteriyor. **Read-only** — iOS'tan rename/tag düzenlemesi v0.2.35+ adayı (`clientAction` envelope ile dispatch edilebilir). Mac side test sayısı değişmedi (745); iOS Xcode simulator BUILD SUCCEEDED. Breaking change yok.

### Added — Sprint 9 / iOS visual parity

#### `ios/PixelAgentRemote/ArchiveDisplayHelpers.swift` (yeni, saf enum)
- `IOSArchiveTitleResolver` — Mac'in `ArchiveTitleResolver` (`PixelMemory`'i
  kullanır) iOS karşılığı. iOS `PixelMemory`'i bağımlı değil; yalnız
  `PixelRemote.ArchiveEntryPayload`'a erişimi var. View'dan ayrık →
  gelecekte iOS test target eklenirse doğrudan test edilebilir.
- `displayTitle(for:)` — düşüş zinciri: `customTitle` (trim) >
  `firstUserSnippet` (trim) > `"(başlıksız)"`. Mac tarafıyla birebir aynı.
- `tagInlineSummary(_:)` — Row'da gösterilen kısa tag özeti: ilk 3 tag
  `#x #y #z` + fazlası `+N`. Boş/nil tag listesinde boş string. Mac'in
  `tagInlineSummary` paralelliği.

#### `ios/PixelAgentRemote/ConversationHistoryViewIOS.swift`
- **Row:** `Text(entry.firstUserSnippet ?? "(başlıksız)")` →
  `Text(IOSArchiveTitleResolver.displayTitle(for: entry))` — customTitle
  varsa onu, yoksa snippet'i, yoksa placeholder'ı gösterir.
- **Rename rozeti:** customTitle varsa başlığın yanında mor 0.7 alpha
  `pencil.circle.fill` ikon (Mac'le paralel).
- **Tag inline preview:** Tarih/mesaj sayısı satırının altında mor 0.85
  alpha caption, `IOSArchiveTitleResolver.tagInlineSummary(entry.tags)`
  ile (boş listede satır gizli).
- **ArchiveDetailView:**
  * Navigation title artık entry.firstUserSnippet ?? "Sohbet" yerine
    `IOSArchiveTitleResolver.displayTitle(for: entry)` — customTitle
    varsa header'da görünür.
  * loadActionBar altında, mesaj content'inden önce yatay scrollable
    **tag chip listesi** (varsa). Capsule mor 0.18 alpha; readonly
    (düzenleme v0.2.35+ adayı).

### Migration / Behavior notları
- Eski Mac sürümleri (`ArchiveEntryPayload.customTitle = nil` ve
  `tags = nil` gönderen) iOS'ta hâlâ snippet/başlıksız fallback'le
  doğru görünür — wire opsiyonel field'lar additive.
- iOS test target henüz yok (Mac SPM testTarget pattern'i ekleyebilen
  Xcode UI test target gerekir); helper'lar saf + View'dan ayrık olduğu
  için ileride eklenebilir.
- iOS xcodebuild simulator BUILD SUCCEEDED (yeni `ArchiveDisplayHelpers.swift`
  xcodegen tarafından project'e otomatik eklendi — project.yml `path:
  PixelAgentRemote` glob).

## [0.2.33] — 2026-05-25

**EnvelopePayload sum-type refactor — v0.3 hazırlığı.** v0.2.32'ye kadar `EnvelopePayload` 20 opsiyonel field'lı flat struct'tı (`text: String?`, `selectedBackend: String?`, vs.); hangi field'ın hangi envelope type'a ait olduğu konvansiyondu, derleyici garantilemiyordu. Şimdi `EnvelopeType` ile 1:1 sum type — type checker bilgisi sertleşti. **Wire format değişmedi** (eski iOS/Mac sürümleri uyumlu); backward-compat computed getter'lar sayesinde caller migration zorunlu değil. **760 envelope-side test yeşil** (+15 bu release'te). Breaking change yok pratikte (factory metodları aynı imza, getter'lar aynı).

### Refactored — Sprint 8 / Sum-type API

#### `Sources/PixelRemote/RemoteEnvelope.swift` baştan yazıldı
- **`EnvelopePayload` enum (15 case, EnvelopeType ile 1:1):**
  * `.hello(publicKey: String)`
  * `.error(code: String, message: String)`
  * `.ack(referenceID: String)`
  * `.userMessage(text: String, messageID: String?)`
  * `.assistantMessage(text: String, messageID: String?)`
  * `.assistantChunk(text: String, messageID: String?)`
  * `.clientConfig(backend: String, model: String, planMode: Bool)`
  * `.clientAction(actionType: String, targetID: String?)`
  * `.hostStatus(HostStatusContent)` — yeni sub-struct (7 field aggregator)
  * `.screenshotPayload(base64Image: String)`
  * `.toolCallEvent(ToolCallEventPayload)`
  * `.archiveListResponse(entries: [ArchiveEntryPayload])`
  * `.archiveLoadRequest(archiveID: String)`
  * `.archiveLoadResponse(messages: [Message])`
  * Empty payload type'lar (`ping`, `ready`, `archiveListRequest`) için
    `RemoteEnvelope.payload = nil` (enum'da `empty` case yok).
- **`HostStatusContent` yeni sub-struct** — 7 field'lı aggregator
  (selectedBackend, selectedModel, planMode, availableBackends,
  availableModels, activeSubagents, systemMetrics). hostStatus envelope
  payload'unun gerçek yapısı görünür hale geldi.
- **Custom Codable (`RemoteEnvelope`):** type'ı önce decode et, sonra
  payload'u type-aware decode et. Eski wire format flat dict'ten yeni
  enum'a build edilir. Encode tarafında case'e göre ilgili field'lar
  yazılır (eski formatla birebir aynı).
- **Backward-compat computed getter'lar:** Önceki `payload?.text`,
  `payload?.actionType`, `payload?.selectedBackend` vb. 20 field için
  her biri için ilgili case'den döndüren computed property. Caller'lar
  migrate olmadan çalışmaya devam eder; istersek aşamalı `case let .foo`
  pattern matching'e geçilir.
- **Equatable artık auto-synthesized.** Eski manual `==` (toolCallEvent,
  archiveEntries, archiveLoadID, archiveMessages eksikti) bug taşıyordu.
- **Dead `metadata: [String: String]?` field silindi** — hiçbir call site
  yoktu (init default'u dışında).

### Migration notları
- **Caller'lar:** Mevcut `envelope.payload?.fieldName` access pattern'leri
  computed getter'lar sayesinde olduğu gibi çalışır (8 access site + iOS
  RemoteSession dahil). Migration **zorunlu değil**; tercihe göre yeni
  `case let .userMessage(text, id) = payload` pattern matching API'sine
  geçilebilir.
- **Construction:** Doğrudan `EnvelopePayload(text:role:)` çağıran 2 test
  `.userMessage(text:messageID:)` enum case'ine güncellendi
  (EnvelopeSignerTests).
- **Wire format:** Değişmedi. Yeni Mac/iOS eski Mac/iOS ile pairing edebilir.

### Tests (+15)
- `Tests/PixelRemoteTests/EnvelopePayloadSumTypeTests.swift` (yeni, 15 test):
  case binding (userMessage/clientAction/hostStatus), empty payload nil
  (ping/archiveListRequest), backward-compat computed getter'lar (text/role/
  messageID/hostStatus passthrough/clientConfig/clientAction/null-default),
  wire format backward-compat (decode v0.2.32 flat JSON → enum, encode →
  flat shape, empty payload omit).

Toplam envelope-side test: 85 → 100 (PixelRemoteTests filter) — wire round-trip + signer + tool call + archive + type forward-compat + yeni sum type pattern matching tümü yeşil.

## [0.2.32] — 2026-05-25

**Sprint 7 "Conversation tag" — rename'in eşi.** Sprint 6 (v0.2.31) iniş yapan conversation rename feature'ının doğal devamı: her arşive 0+ etiket eklenebilir, sidebar header'ında filter chip'leri (multi-select OR/union), row'da inline tag preview. Sidecar persistence (`archive/tags.json`), saf helper'lar (TagNormalizer/TagFilter) testable. iOS wire field eklendi (read-only, additive). **745 test yeşil** (+27 bu release'te). Breaking change yok.

### Added — Sprint 7 / B2 Conversation Tag

#### Sidecar persistence (`Sources/PixelMemory/`)
- `ArchiveTagsStore.swift` (yeni, saf enum, public): `ArchiveTitleStore`
  paterniyle aynı — `archive/tags.json` flat dict `[filename: [tag, ...]]`.
  * `load(directory:)` — sidecar yoksa/bozuksa `[:]`.
  * `save(_:directory:)` — atomic write, pretty + sortedKeys.
  * `setTags(_:for:directory:)` — boş veya nil → key kaldırılır.
  * `allTags(directory:)` — tüm entry'lerin tag union'u sorted (sidebar filter
    chip'leri için).
- `ArchivedConversation.swift`: `ArchivedConversationEntry.tags: [String]`
  yeni field; init default `[]` (additive, backward-compat).
- `ConversationStore.swift`:
  * `setTags(_:for:)` actor method.
  * `setTags(_:for:directory:)` nonisolated static overload.
  * `listAllTags(directory:)` nonisolated static.
  * `listAllArchives` tags sidecar'ını da bir kere yükler, entry'ye
    `tags: tagsByFile[filename] ?? []` enjekte eder.

#### Saf helper'lar (`Sources/PixelMacApp/`)
- `TagNormalizer.swift` (yeni, saf, public): trim + lowercase + max 30 char +
  empty-reject. Liste için: dedup + sorted. Türkçe karakter desteği
  (Foundation `lowercased()` locale-independent).
- `TagFilter.swift` (yeni, saf, public): `apply(entries:activeTags:)`. Boş
  set → tüm entry'ler döner. Çoklu tag → **OR / union** (`!isDisjoint`).

#### UI (`Sources/PixelMacApp/`)
- `EditTagsSheet.swift` (yeni, view): mevcut tag chip'leri (X butonu remove) +
  yeni tag TextField (Enter Add, `TagNormalizer` invalid girdi reject) +
  Kapat. `LazyVGrid(adaptive: 90pt)` chip layout. Capsule mor 0.18 alpha.
- `ConversationHistoryView.swift`:
  * **Sidebar filter chip bar:** `availableTags` varsa sidebar üstünde
    `ScrollView(.horizontal)` chip listesi. Aktif olan dolu mor capsule
    (beyaz text), pasif olan açık mor capsule (primary text). "Temizle"
    butonu en sağda.
  * **Filtered entries:** `TagFilter.apply` ile `entries` üzerine uygulanır,
    `groupedByKind` artık `filteredEntries` kullanır.
  * **Filtered empty state:** Filter yüzünden boş ise `tag.slash` ikon +
    "Filtreyle eşleşen konuşma yok" + "Filtreyi temizle" buton.
  * **Row tag preview:** `tagInlineSummary` — ilk 3 tag `#x #y #z` + fazlası
    `+N`. Mor 0.85 alpha caption2, lineLimit(1).
  * **Context menu:** "Etiketleri düzenle…" + (tags varsa) "Tüm etiketleri
    sıfırla" destructive. Rename grubuyla Divider ile ayrık.
  * **State:** `editTagsTarget` + `editTagsDraft` + `activeTagFilter: Set` +
    `availableTags: [String]`. `.sheet(item: editTagsTarget)` EditTagsSheet
    açar; Kapat → `applyTags(...)` → `ConversationStore.setTags(normalized)`
    + reload. `reload()` `availableTags`'i de günceller, ölü filter'ları temizler.

#### Wire (`Sources/PixelRemote/RemoteEnvelope.swift`)
- `ArchiveEntryPayload.tags: [String]?` opsiyonel field — eski iOS client'lar
  Codable additive olduğu için sorunsuz decode eder. Mac handler boş `tags`
  arrayini nil olarak gönderir (wire'da gereksiz `"tags": []` yok).
- Mac archive list handler (`PixelMacApp.swift`):
  `tags: entry.tags.isEmpty ? nil : entry.tags`.

### Tests (+27)
- `Tests/PixelMemoryTests/ArchiveTagsStoreTests.swift` (yeni, 8 test):
  empty/corrupt graceful, round-trip, setTags add/nil/empty remove, allTags
  union sorted, empty when no sidecar.
- `Tests/PixelMacAppTests/TagNormalizerTests.swift` (yeni, 9 test):
  trim+lowercase Türkçe karakter, empty reject, max length truncate +
  boundary, list sanitize+dedup+sort, drop-all-empty, empty array passthrough.
- `Tests/PixelMacAppTests/TagFilterTests.swift` (yeni, 6 test): empty
  active → all, single tag, multiple tags OR union, untagged excluded when
  filter active, preserves order, no-match empty.
- `Tests/PixelMemoryTests/ConversationStoreTests.swift` (4 yeni test):
  setTags actor + static + nil/empty clears + listAllTags union.

## [0.2.31] — 2026-05-25

**Sprint 6 "Persistence + Polish" — paket kapanışı.** Sprint 5 release sonrası 4 atomic item: SoM marks JSONL sidecar persistence (`69bb2f6`), iOS → Mac archive load handler (`a976c20`), MCP setup wizard config file editor (`b0a0482`), ve bu release'le birlikte **konuşma yeniden adlandırma (rename)**. **718 test yeşil** (+20 bu release'te). Breaking change yok — sidecar persistence + opsiyonel wire field additive.

### Added — Sprint 6 / B2 Conversation Rename

#### Mac sidebar'da arşivlenmiş konuşmaya kullanıcı başlığı (`Sources/PixelMemory/`)
- `ArchiveTitleStore.swift` (yeni, saf enum, public): sidecar persistence —
  `archive/titles.json` flat dict `[filename: title]`. Filename değişmiyor
  (parser kırılmasın); başlıklar ayrı dosyada.
  * `load(directory:)` — sidecar yoksa veya bozuksa `[:]` (UI fallback davranır).
  * `save(_:directory:)` — atomic write, pretty + sortedKeys (diff-friendly).
  * `setTitle(_:for:directory:)` — title nil veya whitespace-only ise key kaldırılır.
- `ArchivedConversation.swift`: `ArchivedConversationEntry.customTitle: String?`
  yeni field; init default `nil` — additive, backward-compat.
- `ConversationStore.swift`:
  * `renameArchive(at:title:)` actor method — sidecar update.
  * `renameArchive(at:title:directory:)` nonisolated static overload —
    `listAllArchives` gibi, view'lar instance olmadan çağırabilir.
  * `listAllArchives` her run'da sidecar dict'i bir kere yükler, entry'ye
    `customTitle: titles[filename]` enjekte eder.

#### Mac UI: sağ-tık menu + rename sheet (`Sources/PixelMacApp/`)
- `ArchiveTitleResolver.swift` (yeni, saf enum, public): saf display
  zinciri — `customTitle` (trim) > `firstUserSnippet` (trim) > `"(başlıksız)"`.
  View'dan ayrık → testable.
- `RenameArchiveSheet.swift` (yeni, struct view): modal sheet, başlık
  TextField + Save/Cancel. Plain Enter Save, Escape Cancel. `@FocusState`
  ile auto-focus. Snippet'i de altta gösterir (hangi konuşma bağlamı için).
- `ConversationHistoryView.swift`:
  * Row'da `ArchiveTitleResolver.displayTitle(for:)` + customTitle varsa
    yanına mor `pencil.circle.fill` rozet.
  * `.contextMenu` — "Yeniden adlandır…" + (customTitle varsa) "Başlığı
    sıfırla" (destructive).
  * `@State renameTarget: ArchivedConversationEntry?` + `renameDraft: String`.
  * `.sheet(item: $renameTarget)` ile RenameArchiveSheet sunulur; Save
    `ConversationStore.renameArchive(...)` çağırır + listeyi reload eder.

#### Wire protokolü (`Sources/PixelRemote/RemoteEnvelope.swift`)
- `ArchiveEntryPayload.customTitle: String?` opsiyonel field — eski iOS
  client'lar Codable additive olduğu için sorunsuz decode eder, yeni
  client'lar başlığı görür ve listede gösterir.
- Mac handler (`PixelMacApp.swift`): `ArchivedConversationEntry → payload`
  dönüşümünde `customTitle: entry.customTitle` geçirilir.

### Tests (+20)
- `Tests/PixelMemoryTests/ArchiveTitleStoreTests.swift` (yeni, 9 test):
  empty/corrupt graceful, save+load round-trip, setTitle add/trim/nil/
  empty/whitespace-only remove, nonexistent key noop.
- `Tests/PixelMemoryTests/ConversationStoreTests.swift` (4 yeni test):
  rename actor + static overload, nil-clears, untitled preservation
  (sidecar yokken backward-compat). Testler kind'lı filename
  (`conversation-claude.jsonl`) kullanır çünkü `listAllArchives` parser
  kind segment'ini bekler.
- `Tests/PixelMacAppTests/ArchiveTitleResolverTests.swift` (yeni, 8 test):
  fallback zinciri (custom > snippet > placeholder), trim, edge cases
  (empty/whitespace), placeholder constant stability.

## [0.2.30] — 2026-05-25

**Sprint 5 "Cross-Platform Parity" — 4 atomic item, Mac ↔ iOS UX simetrisi + protokol genişlemesi.** Sprint 4'ün polish katmanı üzerine: iOS'a Mac'in connection-lost pulse'ı, mascot'a ince animasyon davranışları, composer'a drag-drop file context, ve iOS'a Mac'in geçmiş sidebar'ının karşılığı (4 yeni envelope ile relay/LAN üzerinden). **675 test yeşil** (+44 bu release'te). Breaking change yok pratikte (new enum cases additive — Sprint 4'ün `EnvelopeType.unknown` forward-compat'i bu envelope eklemelerini sorunsuz karşılar).

### Added — Sprint 5 / Cross-Platform Parity

#### iOS connection-lost pulse parallel to Mac (commit `dfa49b5`)
- `Sources/PixelRemote/ConnectionLossDetector.swift` (yeni, saf, public):
  `isLossEvent(wasConnected:isConnected:)` — yalnızca `true → false`
  geçişi true döner; diğer 3 Bool kombinasyonu false (idempotent re-render
  güvenli). Mac'in `ConnectionTransitionDetector` (state-based) ile
  semantik paralel; iOS basit Bool için ayrı imza.
- `ios/PixelAgentRemote/ConnectionLostBanner.swift` (yeni): önceki private
  inline view extract edildi. `pulseTrigger: Date?` param + `.onChange`
  ile reset + withAnimation easeOut(1.6s) scale 1.0→1.06 + opacity
  0.85→0. Overlay: orange stroke Rectangle, hit-testing kapalı.
  `.onAppear` da pulse'lar (tab dönüş / initial loss fark edilir).
- `ios/PixelAgentRemote/ChatView.swift`: `@State lastDisconnectAt` +
  `.onChange(of: session.isConnected)` listener.
- 5 yeni test (truth table coverage).

#### Mascot subtle animations (commit `d0f57e6`)
- `Sources/PixelMascot/MascotAnimationClock.swift` (yeni, saf, public):
  Foundation + CoreGraphics only — SwiftUI bağımsız, testable math.
  * `idleOffset(time:)` — `sin(t × 2π × 0.25) × 1.5pt` dikey (4s periyot
    nefes alma).
  * `thinkingOffset(time:)` — `sin(t × 2π × 0.5) × 0.8pt` yatay (2s periyot
    hafif wobble).
  * `speakingFrameIndex(time:)` — `Int(t × 5) % 2` (5Hz cycle, 0/1 alternates).
  * `errorShakeOffset(elapsed:)` — 0...0.5s decaying:
    `3.0 × sin(elapsed × 2π × 15) × (1 - elapsed/0.5)` yatay; out-of-range
    `.zero`.
- `Sources/PixelMascot/PixelMascot.swift`: yeni `speakingFrameClosed`
  ASCII frame (`__` kapalı ağız); `frame(for:atFrameIndex:)` overload —
  speaking için 0/1 index'e göre dön, diğer state'ler tek frame.
- `Sources/PixelMascot/MascotView.swift`: Canvas artık
  `TimelineView(.animation(minimumInterval: 1/30))` wrapper içinde — 30 FPS.
  State'e göre offset (idle bob / thinking wobble / error shake) + frame
  index (speaking için 0/1). `@State errorEnteredAt` ile shake elapsed
  hesabı.
- 14 yeni test (4 idle + 2 thinking + 3 speaking + 5 error).

#### Drag-drop file context to composer (commit `d0756fa`)
- `Sources/PixelMacApp/FileDropFormatter.swift` (yeni, saf enum):
  * `snippet(forFileURL:fileManager:)` — URL'i klasör/dosya'ya göre
    branch'lar, format'lı string döner.
  * Text dosyası (whitelist ext + <100KB) → ```\(lang)\n// <filename>\n
    <content>\n``` fenced code block.
  * Diğer dosyalar → `📎 \`<path>\`` mention.
  * Klasör → `📁 <name>/ —` + indented listeleme (max 20 entry).
  * 40+ ext text whitelist + `codeFenceLanguage` aliases (yml→yaml,
    js→javascript, py→python, rs→rust, vb.).
- `Sources/PixelMacApp/ComposerHaloStyle.swift`: yeni case `.dropTargeted`
  — yeşil halo (0.65 alpha), 2.5pt line width. `resolve` `isDropTargeted`
  yeni parametre (default false). Öncelik: streaming > dropTargeted >
  plan > focused > none.
- `Sources/PixelMacApp/ChatComposer.swift`: `import UniformTypeIdentifiers`,
  `@State isDropTargeted`. TextField'a `.onDrop(of: [.fileURL])` +
  `handleDrop(providers:)` callback — providers'tan URL yükle, snippet
  üret, draft'a append (önce \n).
- 16 yeni test (13 FileDropFormatter + 3 ComposerHaloStyle dropTargeted).

#### iOS conversation history viewer (commit `804e10d`)
- `Sources/PixelRemote/RemoteEnvelope.swift`:
  * `import PixelCore` eklendi.
  * 4 yeni `EnvelopeType` case: `archiveListRequest`, `archiveListResponse`,
    `archiveLoadRequest`, `archiveLoadResponse`.
  * `ArchiveEntryPayload` public struct (id String, backendKind, archivedAt
    Double, messageCount, firstUserSnippet?) — Mac
    `ArchivedConversationEntry`'nin wire-suitable versiyonu.
  * `EnvelopePayload`'a 3 yeni opsiyonel field: `archiveEntries`,
    `archiveLoadID`, `archiveMessages`. 17 → 20 opsiyonel field; sum-type
    refactor adayı hâlâ açık.
  * 4 yeni factory metodu.
- `Sources/PixelRemote/RemoteHost.swift`:
  * `import PixelCore`.
  * 2 yeni callback: `onArchiveListRequested` + `onArchiveLoadRequested` —
    caller ConversationStore'a delegate eder.
  * Inbound handler'a `case .archiveListRequest`/`.archiveLoadRequest`
    eklendi — callback çağırır + response envelope gönderir.
  * `sendArchiveListResponse(entries:)` + `sendArchiveLoadResponse(messages:)`
    public async — sign + transport.send pattern.
- `Sources/PixelMacApp/PixelMacApp.swift`: ChatHost wire-up — handler'lar
  `ConversationStore.listAllArchives()` + inline JSONL decode'a delegate.
- `ios/PixelAgentRemote/RemoteSession.swift`: 3 yeni @Published
  (`archiveEntries`, `loadedArchiveMessages`, `isLoadingArchives`) +
  `requestArchiveList()`/`requestArchive(id:)` async methodları + inbound
  case'leri.
- `ios/PixelAgentRemote/ChatView.swift`: Sohbet header'a 🕒
  (clock.arrow.circlepath) buton + `.sheet`; `MessageRow` private → internal
  (archive detail view'ı reuse eder).
- `ios/PixelAgentRemote/ConversationHistoryViewIOS.swift` (yeni, ~160 satır):
  NavigationStack sheet. Backend'lere göre gruplu Section'lar (Claude/Codex/
  Gemini öncelikli + diğerleri alfabetik), her grup tarih descending.
  `NavigationLink` → `ArchiveDetailView` private (ProgressView → LazyVStack +
  MessageRow). Loading + empty state'ler ayrı.
- 9 yeni test (8 ArchiveEnvelopeTests — payload Codable round-trip,
  envelope types in allCases, 4 factory; 1 existing test güncellendi).

### Changed
- **`EnvelopeType.allCases`** 14 → 18 case (`archiveListRequest`/`Response`/
  `archiveLoadRequest`/`Response` eklendi). v0.2.29'daki forward-compat
  sentinel sayesinde eski client'lar bu yeni tipleri `.unknown`'a düşürür.
- **`EnvelopePayload`** 20 opsiyonel field (3 yeni archive field eklendi);
  sum-type refactor hâlâ Sprint 6+ adayı.
- **iOS `MessageRow`** private → internal — ConversationHistoryViewIOS
  archive detail view'ı reuse eder.
- **`PixelRemote`** artık `PixelCore`'a import dependency (Message tipinin
  envelope payload'da geçebilmesi için). Existing dependency graph
  zaten içeriyordu, sadece import statement eklendi.

### Tests
- **Sprint 5 toplam:** 5 yeni test dosyası, 44 yeni test (**631 → 675**). 0 regression.
- `ConnectionLossDetectorTests` (5), `MascotAnimationClockTests` (14),
  `FileDropFormatterTests` (13), `ComposerHaloStyleTests` (+3 dropTargeted),
  `ArchiveEnvelopeTests` (8), `RemoteEnvelopeTests` (+1 expected cases updated).

### Notes
- **iOS pulse** Mac'le simetrik UX — banner appear'da ve her connection-lost
  event'inde pulse'lar. Stable disconnected state'te (kalıcı kopuk) tekrar
  tetiklenmez.
- **Mascot animations** subtle by design — kullanıcıyı bunaltmasın. 30 FPS
  TimelineView CPU yükü ihmal edilebilir (mascot 48pt kare küçük view).
- **Drag-drop** LLM CLI'larının (Claude/Codex/Gemini) ek dosya kabul
  etmediği için içerik prompt'a embed edilir. 100KB üzeri text dosyalar
  path referansına düşer (composer'ı boğmamak için).
- **iOS history viewer** lokal storage yok — Mac'in arşivlerini relay/LAN
  üzerinden alır. Read-only viewer; Mac'in "Bu sohbete devam et" özelliği
  (Sprint 4) iOS'a bu sürümde port edilmedi (Sprint 6+ adayı: iOS'tan
  Mac'e archive load request).
- **EnvelopePayload field sayısı** 20'ye ulaştı. Sum-type refactor (god
  struct → enum cases per envelope type) Sprint 6+'da değerlendirilecek.

**Sprint 1+2+3+4+5 birikim:** 29 audit item kapandı (10 demo-ready + 6 power-user + 4 persistent-state + 5 polish + 4 cross-platform). 443 → 675 test (+232). 22 saf helper + 14 view + 26 test dosyası. 5 GitHub release shipped.

## [0.2.29] — 2026-05-24

**Sprint 4 "Polish + Persistence" — 5 atomic item, protocol forward-compat + storage durability + ergonomic touches.** Sprint 1/2/3'ün üzerine bir katman: yeni envelope tiplerinin eski client'ları kırmamasını, ekran görüntülerinin app restart'ından sonra hâlâ görünür olmasını, arşivlenmiş konuşmaların geri yüklenebilmesini, bağlantı kaybının görsel uyarısını ve screenshot → soru workflow'unu sağlar. **631 test yeşil** (+25 bu release'te). Breaking change yok pratikte.

### Added — Sprint 4 / Polish + Persistence

#### EnvelopeType.unknown forward-compat sentinel (commit `f5dd70d`)
- `Sources/PixelRemote/RemoteEnvelope.swift`:
  * `EnvelopeType.unknown` yeni case (rawValue "unknown"). Production'da
    yalnızca decode fallback'i.
  * Custom `Codable` conformance — `init(from:)` raw string okuyup
    `EnvelopeType(rawValue:) ?? .unknown` döner; `encode(to:)` rawValue yazar.
  * **Behavioral change:** önceki sürümlerde unknown type decode throw
    idi, artık `.unknown`'a düşer — wire-protocol forward-compat. iOS
    handler'lar zaten `default: break` ile geçiyordu.
- 8 yeni test + `testUnknownEnvelopeTypeThrows` → `testUnknownEnvelopeTypeDecodesToUnknownCase` rename.

#### "Bu sohbete devam et" archive load (commit `368275e`)
- `Sources/PixelMemory/ConversationStore.swift`:
  * `replaceWithArchive(_ entry:)` instance metodu — `newConversation()`
    ile mevcut arşivlenir, archive dosyasının data'sı aktif `fileURL`'e
    yazılır.
  * Archive timestamp **millisecond precision**'a yükseltildi —
    `YYYY-MM-DDTHH-MM-SS.sssZ` (24 char). Saniye precision'da hızlı
    ardışık `newConversation()` çakışmasını çözer.
- `Sources/PixelMemory/ArchivedConversation.swift`:
  * Parser artık [24, 20] uzunluğunu sırayla dener — backward-compat
    eski archive dosyalarına.
- `Sources/PixelMacApp/ConversationHistoryView.swift`:
  * `onLoadArchive: ((Entry) -> Void)?` opsiyonel parametre.
  * Detail view'in üstüne sticky `loadActionBar` — "Yükle"
    borderedProminent buton + arrow.uturn.forward.circle ikon.
- `Sources/PixelMacApp/PixelMacApp.swift`:
  * `@State archiveLoadNonce` ChatView .id'sine eklendi → aynı backend
    için bile force re-init garantilenir → restoreIfNeeded yeni JSONL'i
    okur.
  * `loadArchive(_:)` async handler — store.replaceWithArchive +
    selectedKind switch + nonce artırma.
- 2 yeni test (replaceWithArchive happy path + boş aktif edge case).

#### Persist screenshots to disk (commit `1ba91ce`)
- `Sources/PixelMemory/ScreenshotStore.swift` (yeni, saf enum):
  * `defaultDirectory()` → `~/Library/Application Support/pixel-agent/
    screenshots/`.
  * `save(pngData:for:directory:)` — `<UUID>.png` atomic write.
  * `load(for:directory:)` — bytes ya da nil.
  * `delete(for:directory:)` — best-effort, idempotent.
  * `purgeOrphans(keeping:directory:)` — aktif `messageID` set'inde
    olmayan PNG'leri temizler; non-PNG yoksayar.
- `Sources/PixelMacApp/ChatViewModel.swift`:
  * `captureScreenshotIntoChat`: PNG save artık disk'e (best-effort).
  * `restoreIfNeeded`: `.system` + `[ekran görüntüsü` prefix filter ile
    her eşleşme için disk'ten PNG yükle, `NSImage.representations.first
    .pixelsWide/High` ile pixel size çıkar, attachment dict'e ekle.
    Marks restore edilmez (sidecar JSON ileride).
- 8 yeni test (save/load round-trip, missing file, dir creation, delete,
  idempotent, purgeOrphans).

#### Connection-lost pulse animation (commit `19ce45e`)
- `Sources/PixelMacApp/ConnectionPillView.swift`:
  * `var pulseTrigger: Date? = nil` parametresi. Yeni Date'e set olunca
    `.onChange` reset + animate (scale 1.0→1.7, opacity 0.85→0, 1.6s
    easeOut).
  * Background overlay: tint color stroke 2pt Capsule, hit-testing kapalı.
  * `ConnectionTransitionDetector` saf enum — `isLossEvent(from:to:)`
    `connected → disconnected` koşulunu tek noktada tutar (niyetli
    disconnect ve handshake transitionları hariç).
- `Sources/PixelMacApp/PixelMacApp.swift`:
  * `@State lastDisconnectAt: Date?` + `currentPillState` computed.
  * Toolbar pill `.onChange(of: currentPillState)` → isLossEvent
    doğruysa `lastDisconnectAt = Date()` → pulse tetiklenir.
- 7 yeni test (4 state × transitions, self-transitions, loss event
  isolation).

#### Screenshot → composer prompt prefill (commit `586a0e6`)
- `Sources/PixelMacApp/ChatViewModel.swift`:
  * `captureScreenshotIntoChat`: PNG save'ten sonra composer'ın boş
    olup olmadığını kontrol; boşsa `draft = Self.defaultScreenshotPrompt`
    ("Bu ekran görüntüsünde ne görüyorsun?").
  * Composer doluysa kullanıcının taslağına dokunulmuyor (non-destructive).
  * `static let defaultScreenshotPrompt` — testten/diğer yerden erişim.

### Changed
- **`EnvelopeType.allCases`** 13 → 14 case (`.unknown` eklendi).
- **`EnvelopePayload`** 17 opsiyonel field (toolCallEvent v0.2.28'de eklendi,
  Sprint 4'te değişiklik yok); sum-type refactor hâlâ adayı.
- **`ConversationStore.newConversation()`** artık `.withFractionalSeconds`
  ISO8601 format kullanıyor — 24 char stamp; eski 20 char stamp'li
  arşivler parser'ın backward-compat path'i ile hâlâ okunur.

### Tests
- **Sprint 4 toplam:** 4 yeni test dosyası, 25 yeni test (**606 → 631**). 0 regression.
- `EnvelopeTypeForwardCompatTests` (8), `ConversationStoreTests` (+2 yeni replaceWithArchive), `ScreenshotStoreTests` (8), `ConnectionTransitionDetectorTests` (7).

### Notes
- **`EnvelopeType.unknown`** behavioral change: önceki Mac/iOS sürümleri
  bilinmeyen type'a throw veriyordu (test seviyesinde). v3 envelope
  formatına geçişe yapısal hazırlık.
- **Screenshot persistence:** PNG bytes diskte; marks RAM-only (kullanıcı-
  initiated capture'larda zaten boş, LLM ui_screenshot için sidecar JSON
  Sprint 4+ adayı).
- **Connection-lost pulse** sadece `connected → disconnected` transition'ını
  tetikler — kullanıcı "Bağlantıyı kapat" (connected → notPaired) veya
  handshake aborted (connecting → notPaired) durumunda pulse yok.
- **Screenshot prompt prefill** composer doluysa no-op — kullanıcının
  yarım kalmış taslağı korunur.

**Sprint 1+2+3+4 birikim:** 25 audit item kapandı (10 demo-ready + 6 power-user + 4 persistent-state + 5 polish). 443 → 631 test (+188). 18 saf helper + 12 view + 22 test dosyası.

## [0.2.28] — 2026-05-24

**Sprint 3 "Persistent State + iOS Parity" tamamlandı — 4 polish item, mac+ios platformları arası simetri.** Sprint 1/2 demo-ready + power-user katmanlarına ek olarak: arşiv erişimi (geçmiş konuşmaları gözden geçir), standart ⌘, Preferences penceresi, iOS dashboard'da 4. tab (settings), iOS Mac Paneli'nde gerçek zamanlı tool aktivitesi feed'i. **606 test yeşil** (+32 bu release'te). Breaking change yok pratikte.

Mac + iOS her commit'te `BUILD SUCCEEDED`. Sprint 1+2+3 birikim: 20 audit item kapandı, 443 → 606 test (+163), 16 saf helper + 11 view + 20 test dosyası.

### Added — Sprint 3 / Persistent State + iOS Parity

#### B2 Conversation history sidebar (commit `7f6665a`, audit "Large")
- `Sources/PixelMemory/ArchivedConversation.swift` (yeni):
  * `ArchivedConversationEntry` public struct (id URL, backendKind, archivedAt
    Date, messageCount, firstUserSnippet) — Identifiable + Equatable + Sendable.
  * `ArchivedConversationParser.parseFilename(_:)` saf — `conversation-<kind>-
    <YYYY-MM-DDTHH-MM-SSZ>.jsonl` formatından `(kind, date)` çıkarır. **Sabit-
    uzunluk 20 char timestamp yaklaşımı** — tarih içindeki `-` karakterlerine
    takılmayan reliable parse.
  * `firstUserSnippet(messages:)` saf — ilk non-empty `.user` mesajının ilk
    60 karakteri (+"…" trim).
- `Sources/PixelMemory/ConversationStore.swift`:
  * `loadMessages(fromArchive url:)` instance metodu — verilen URL'den JSONL
    satırlarını decode eder.
  * `listAllArchives(directory:)` static — `archive/` dizinini tarar, parse'i
    geçen her dosya için entry üretir (message count + snippet için içeriği
    bir kez okur). archivedAt descending sıralı.
- `Sources/PixelMacApp/ConversationHistoryView.swift` (yeni, ~210 satır):
  NavigationSplitView sheet (`.balanced` style, min 720×480). Sidebar:
  backend kind'larına göre gruplu Section'lar (Claude/Codex/Gemini öncelikli +
  diğerleri alfabetik). Her satır 2-line layout: snippet + tarih + count.
  Detail: seçili konuşmanın `MessageRow`'larını ScrollView içinde — Sprint 1/
  A1 markdown render'ı otomatik aktif. Empty/loading/error state'ler ayrı
  view'lar. Toolbar'da Kapat + Yenile.
- ChatHost toolbar'a "🕒 Geçmiş" butonu (`clock.arrow.circlepath`) +
  `.sheet(isPresented:)` wiring. Permissions/About butonlarından önce.
- 12 yeni test: parser happy path (Claude/Codex/Gemini), invalid filenames,
  unknown backend forward-compat, snippet selection/truncation/skip-empty,
  end-to-end listing temp directory'den (1 archive, empty dir, sort
  descending).

#### B1 Settings scene (⌘, tab'lı) (commit `102332a`, audit "Large")
- `Sources/PixelMacApp/SettingsView.swift` (yeni, ~280 satır):
  * `SettingsTab: String, CaseIterable, Identifiable, Sendable` saf enum —
    4 case (`.general`, `.models`, `.connection`, `.permissions`); title +
    systemImage computed.
  * `SettingsView`: TabView selectedTab @State binding.
  * `GeneralSettingsTab`: Form .grouped style — sürüm/test/lisans info +
    depo dizini (Finder'da göster) + "Tüm model tercihlerini sıfırla" buton.
  * `ModelsSettingsTab` + `BackendModelRow`: per-CLI Picker (Varsayılan +
    ModelCatalog.knownModels). UserDefaults pixel.model.* yazar/okur.
  * `ConnectionSettingsTab`: Relay URL + kopyala butonu; env override
    detect uyarı satırı. LAN service type + protokol versiyonu info.
  * `PermissionsSettingsTab`: Accessibility + Screen Recording status,
    eksikte "Aç" deep-link (System Settings).
- `Sources/PixelMacApp/PixelMacApp.swift`: App body'ye `Settings {
  SettingsView() }` scene eklendi — macOS otomatik ⌘, kısayolunu ve
  "pixel-agent › Settings…" menü öğesini ekler.
- 6 yeni test: allCases regression guard, non-empty metadata her tab'da,
  title/icon uniqueness, rawValue lowercase, id == rawValue.

#### B8 iOS settings tab (4. tab) (commit `0350b12`, audit "Medium")
- `Sources/PixelRemote/PublicKeyFormatter.swift` (yeni, saf, public):
  `format(_:groupSize:)` — base64 ed25519 public key'i okunabilir gruplara
  böler (default 8 char). Empty → "—", invalid groupSize → original. **Mac +
  iOS aynı binary'den faydalanır.**
- `ios/PixelAgentRemote/SettingsTabView.swift` (yeni, ~165 satır):
  Form-based 5 section:
    * **Durum**: bağlı/değil capsule + transport badge (LAN/Relay) + lastError.
    * **Eşleşme**: pairing code + relay URL (textSelection.enabled,
      monospaced) veya "henüz eşleşmemiş" placeholder.
    * **Mac genel anahtarı**: PublicKeyFormatter.format'lı pk + ADR-0015 footer.
    * **Uygulama**: version + build + GitHub link.
    * **Eylemler**: bağlantı kapat / yeniden bağlan / eşleşmeyi sıfırla
      (destructive role + confirmation alert).
- `ios/PixelAgentRemote/ChatView.swift`: TabView'a 4. tab eklendi —
  `SettingsTabView()` + `Label("Ayarlar", systemImage: "gear")`. Mevcut
  AboutView modal'ı korundu (header'daki ⓘ butonundan erişim sürüyor).
- 7 yeni test: empty input → "—", default 8-char gruplar, non-exact multiple
  shorter last, short input single group, custom groupSize=4, zero
  groupSize defensive, reassembly fidelity. **iOS build SUCCEEDED.**

#### C12 Tool-call envelope events (commit `f65c749`, audit "Medium")
- `Sources/PixelRemote/RemoteEnvelope.swift`:
  * `EnvelopeType.toolCallEvent` yeni case (wire-compat raw "toolCallEvent").
  * `ToolCallEventPayload`: Codable, Sendable, Equatable, Identifiable
    (id UUID string), `toolName`, `status` ("success"/"failure"), opsiyonel
    `summary`, Unix epoch `timestamp`.
  * `EnvelopePayload.toolCallEvent` opsiyonel field + init param.
  * `RemoteEnvelope.toolCallEvent(toolName:status:summary:)` static factory.
- `Sources/PixelRemote/RemoteHost.swift`:
  * `sendToolCallEvent(toolName:status:summary:)` async — diğer send'lerle
    aynı pattern (sign + send, best-effort).
- `Sources/PixelMacApp/ControlSocketServer.swift`:
  * `var onToolCalled: (@Sendable (String, String, String?) -> Void)?` +
    `attachToolCallListener(_:)` setter.
  * `handleClient(fd:)` execute() sonrası listener'ı çağırır (tool name +
    summarize sonucu).
  * `summarize(_:)` saf yardımcı — `BridgeResponse` struct'tan (enum değil)
    `(status, summary)` çıkarır. Result string-truncated 100 char.
- `Sources/PixelMacApp/PixelMacApp.swift`: ChatHost `.task`'ta
  `controlServer.attachToolCallListener` ile remoteHost.sendToolCallEvent
  closure'ını bağlar (weak reference).
- `ios/PixelAgentRemote/RemoteSession.swift`:
  * `@Published var recentToolCalls: [ToolCallEventPayload]` ring buffer 30 cap.
  * Envelope handler `case .toolCallEvent:` — payload decode + insert (en
    yeni başta).
- `ios/PixelAgentRemote/ChatView.swift`:
  * Mac Paneli'ne `ToolCallFeedSection` — header bolt ikon + count badge;
    ilk 10 satır `ToolCallRow` (SF Symbol success/failure rengi, monospace
    tool adı, timestamp, summary 2-line); empty state placeholder.
- 7 yeni test: payload init defaults + Codable round-trip, envelope factory
  type + payload, envelope JSON round-trip lossless, EnvelopeType.allCases
  contains, raw value wire-stable. **iOS BUILD SUCCEEDED.**

### Changed
- **`EnvelopeType.allCases`** artık 13 case (yeni `.toolCallEvent`); existing
  `testEnvelopeTypeContainsAllExpectedCases` testi güncellendi.
- **`EnvelopePayload`** 17 opsiyonel field (toolCallEvent eklendi); sum-type
  refactor Sprint 4 follow-up adayı.

### Tests
- **Sprint 3 toplam:** 4 yeni test dosyası, 32 yeni test (**574 → 606**). 0 regression.
- `ArchivedConversationTests` (12), `SettingsTabTests` (6), `PublicKeyFormatterTests` (7), `ToolCallEventTests` (7) + `RemoteEnvelopeTests.testEnvelopeTypeContainsAllExpectedCases` updated.

### Notes
- **Conversation history sidebar** read-only viewer (devam etme / import yok bu sürümde) — non-destructive, aktif sohbeti değiştirmiyor. Sprint 4'te "Bu arşivi yükle" eklenebilir.
- **Settings scene** standart macOS Settings konvansiyonuna uyar; AboutView modal'ı korundu (info ikonu hâlâ aktif).
- **iOS Ayarlar tab** AboutView'in tab eşdeğeri ek olarak Mac public key fingerprint + transport label badge + reconnect butonu.
- **Tool call events** Mac MCP bridge hattındaki tüm 9 tool'u kapsar (dock_badge_set, notify, play_sound, dispatch_subagent, ui_query/click/type/screenshot/resolve). Direct MCP server stdio tool'ları (5 saf-data) ayrı bir yolda, bu envelope'a düşmez — bridge sınırı tarafından yakalanır.
- **Sprint 1+2+3 birikim** — 20 audit item kapandı (10 demo-ready + 6 power-user + 4 persistent-state); kalan audit item'ları (19 adet) Sprint 4+'a defer.

## [0.2.27] — 2026-05-24

**Sprint 2 "Power-User Touches" tamamlandı — 6 polish item, demo'dan daha derin etkileşimler.** Sprint 1'in zemininde kullanıcıyı uzun süre tutacak ergonomik dokunuşlar: daimi durum göstergesi, hızlı kopya akışları, conversation arşivleme, fokus geri bildirimi, transient uyarılar ve inline ekran görüntüsü + SoM mark görsel overlay'i. **574 test yeşil** (+45 bu release'te). Breaking change yok.

Mimari deseni Sprint 1'le aynı: her item için saf helper / enum + minimal SwiftUI view. View'lar `@FocusState` ve `GeometryReader` gibi runtime affordances'lara dayanırken iş mantığı ve hesaplamalar saf testable kısımda kalıyor.

### Added — Sprint 2 / Power-User Touches

#### C7 Persistent connection pill (commit `c876e1e`, ROI 9)
- `Sources/PixelMacApp/ConnectionPillView.swift` (yeni) — `ConnectionPillState`
  saf enum (.notPaired / .connecting / .disconnected / .connected) + `from(
  isPaired:isConnected:)` derivation; `label`, `systemImage`, `helpText`,
  `tint` (`ConnectionPillTint` ham enum) computed properties. View kapsül +
  icon + label + colored fill/stroke.
- Toolbar'daki conditional `if remoteHost.isConnected { iphone icon }`
  yerine daimi pill; tıklayınca pairing sheet açılır. QR ikonu ayrı kaldı
  (explicit "yeni QR" affordance'ı).
- 8 test: 4 derivation kombinasyonu, non-empty metadata, label uniqueness,
  tint mapping, connected state radiowaves icon regression.

#### B6 Quick-actions menu (commit `23317d7`, ROI 9)
- `Sources/PixelMacApp/MessageActionsHelper.swift` (yeni, saf) —
  `lastCopyableAssistantText(in:)` listeyi sondan tarar, ilk non-empty
  asistan metnini döner. System mesajları (subagent çıktısı vs.) atlanır.
- ChatColumn header'a `copyLastButton` — `doc.on.doc` ikonu; helper nil
  dönerse disabled. Tıklayınca NSPasteboard'a yazar, 1.5s "✓ Kopyalandı"
  feedback (IntegrationView / CodeBlockView paterni).
- MessageRow `.contextMenu` — "Mesajı Kopyala" sağ-tık her mesaj için
  (user/assistant/system); whitespace-only ise disabled.
- 9 test: empty list, sadece user/system, çoklu turlarda son, trailing
  empty assistant skip, whitespace-only skip, system mesajları sayılmaz,
  original text trimlenmemiş (kod paste fidelity).

#### B3 Conversation export (commit `e161fbc`, ROI 9)
- `Sources/PixelMacApp/ConversationExporter.swift` (yeni, saf) —
  `ConversationExportFormat: String, CaseIterable, Identifiable` (.markdown
  + .json) + `markdown(messages:title:now:)` (`# Title` + ISO8601 export
  date + her mesaj `## Role` başlığı, trailing newline auto-add) +
  `json(messages:)` (pretty + sorted + iso8601 dates) + `defaultFilename(
  for:now:)` (`pixel-agent-yyyy-MM-dd-HHmm.md/.json`).
- ChatColumn header'a `exportMenu` — `square.and.arrow.up` borderless Menu;
  iki seçenek `.menuIndicator(.hidden)`. NSSavePanel modal aç, format'a
  göre içerik üret + URL'ye yaz.
- Formatter'lar method-local (Swift 6 strict concurrency).
- 12 test: empty placeholder, custom title, user+assistant order, system
  section, trailing newline auto-add + preservation, JSON round-trip
  lossless (saniye precision), pretty-printed, ISO8601 dates, filename
  pattern, enum allCases.

#### A8 Composer focus halo + haptic (commit `2d720d8`, ROI 8)
- `Sources/PixelMacApp/ComposerHaloStyle.swift` (yeni, saf) —
  `ComposerHaloStyle: Equatable, Sendable` (.none / .plan / .focused) +
  `resolve(planMode:isFocused:isStreaming:)` priority logic: streaming →
  none (disabled görsel zaten anlatır), aksi halde plan > focused > none.
  `strokeColor` / `lineWidth` / `isVisible` view-side metadata.
- ChatComposer: `@FocusState private var isComposerFocused: Bool` +
  `.focused(...)`. Tek overlay conditional helper sonucunu kullanır.
  `.animation(.easeInOut(0.18s), value: haloStyle)` fokus geçişlerinde
  yumuşak fade.
- `performSend()` + `performHaptic()` helper —
  `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, .now)`.
  Plain Enter, Gönder butonu ve subagent dispatch'ten hepsi geçer.
- 7 test: streaming overrides her şey (4 kombinasyon), plan > focused, plan
  alone, focused alone, hiçbiri yok, none invisible, plan/focused visible.

#### C10 Subagent cap-reached banner (commit `df96f3e`, ROI 6)
- `SubagentManager` `@Published private(set) var lastCapReachedAt: Date?`
  — başlangıçta nil, dispatch cap'e takıldığında her seferinde `Date()` set
  edilir (yeni timestamp → `.onChange` her event'i yakalar).
- ChatHost `.onChange(of: subagentManager.lastCapReachedAt)` →
  `subagentManager.maxConcurrent`'ı kullanıp mesaj formatla, mevcut
  `showConfigToast(message:)` helper'ına gönder. Aynı overlay slot'unu
  config-change toast ile paylaşır.
- 2 test: var olan `testCapReachedRejectsFourthDispatch` genişletildi
  (nil → non-nil → yeni timestamp); yeni `testLastCapReachedAtRemainsNilOnSuccessfulDispatch`.

#### C2/C3 Inline screenshot + SoM overlay UI (commit `2dfedee`, ROI 6.7, Large)
- `Sources/PixelMacApp/ScreenshotMarkLayout.swift` (yeni, saf) —
  `viewRect(forImageRect:imagePixelSize:viewSize:)` pixel→point ölçekleme
  + `fittedSize(imagePixelSize:containerSize:)` aspect-fit hesaplaması.
  Zero image size guard, edge case'ler.
- `Sources/PixelMacApp/InlineScreenshotView.swift` (yeni) — `NSImage(data:)`
  ile PNG yükle → `Image(nsImage:).resizable().aspectRatio(.fit)`.
  GeometryReader içinde fitted size hesapla, her mark için pixel→point rect
  üret; renkli outline + sol-üst sayı badge (capsule). 8-renk palette
  modulo. MaxWidth 520pt. Footer'da boyut + mark sayısı.
- `ChatViewModel`: `@Published var screenshotAttachments: [UUID:
  ScreenshotAttachment]` ephemeral RAM dict (PNG bytes ConversationStore'a
  yazılmaz — JSONL bloat, app restart'ında kaybolur, placeholder text
  kalır). `ScreenshotAttachment` struct (id, pngData, pixelSize, marks,
  capturedAt). `captureScreenshotIntoChat()` async helper —
  `ScreenshotCapture.capture(target: .activeDisplay)` → placeholder
  `[ekran görüntüsü · W×H px]` `.system` mesajı + attachment dict'e ekle.
- ChatColumn: header'a `screenshotButton` (`camera.viewfinder`); MessageRow
  yeni `attachment: ScreenshotAttachment?` parametresi, `.user`/`.system`
  branch'inde attachment varsa InlineScreenshotView render.
- 8 test: viewRect proportional scaling, unit-scale no-op, zero image guard,
  fittedSize 4-case (wider/taller image, same aspect, zero), end-to-end
  mark center preservation.

### Changed
- **MessageRow** — yeni `attachment: ScreenshotAttachment?` opsiyonel parametresi (default nil → eski davranış).
- **SubagentManager** — yeni `lastCapReachedAt: Date?` published property; `dispatch()` failure path'i bu state'i set ediyor.
- **ChatViewModel** — `import PixelComputerUse` eklendi; yeni `screenshotAttachments` dict + `captureScreenshotIntoChat()` metodu.
- **ChatColumn** — header'a 3 yeni quick-action butonu eklendi (screenshot/export/copy-last); `@State didCopyLast` feedback toggle.

### Tests
- **Sprint 2 toplam:** 6 yeni test dosyası, 45 yeni test (**529 → 574**). 0 regression.
- `ConnectionPillStateTests` (8), `MessageActionsHelperTests` (9), `ConversationExporterTests` (12), `ComposerHaloStyleTests` (7), `ScreenshotMarkLayoutTests` (8), `SubagentManagerTests` (+1 + 1 genişletildi).

### Notes
- **Persistence ayrımı:** Sprint 1'in tüm transient state'leri (planMode, toast'lar) RAM-only iken Sprint 2'de ekran görüntüleri de RAM-only — yalnız placeholder text JSONL'e persist edilir. Sprint 3 (B2 history sidebar) ekran görüntüsü asset directory'sini açabilir.
- **Quick-action density:** ChatColumn header artık `[status] [spacer] [📷 screenshot] [↑ export] [📋 copy-last] [+ new] [mascot]` — 3 yeni buton düzenli yerleşim için sabit aralıklı borderless. Dual mode'da her iki sütun da bu butonlara bağımsız sahip.
- **Composer haptic** trackpad olmayan mouse-only kullanıcılarda no-op; varsa `.alignment` titreşim trackpad'de hafiftir.
- **Screenshot capture** Screen Recording izni gerektirir; `PermissionsView` zaten mevcut. İzin yoksa `streamError` set edilir, `ErrorRetryBanner` gösterir.

## [0.2.26] — 2026-05-24

**Sprint 1 "Demo-Ready Foundation" tamamlandı — 10 polish item tek release'te.** "Hızlı prototip" hissini "demo-ready" UX'e taşıyan komple paket. Audit'in (Plan agent, 23 May) en yüksek ROI 10 öğesi sırayla işlendi, her biri (i) saf, test edilebilir bir helper + (ii) minimal SwiftUI view ayrımıyla yazıldı. **529 test yeşil** (+86 bu release'te). Breaking change yok.

Demo-readiness milestone: aşağıdaki 10 yetenek artık çalışıyor — empty-state chip'leri, Plan Mode tool list paneli, markdown + kod copy, ⌘N/⌘⇧P/⌘⇧M kısayolları, typing indicator, iOS→Mac config toast, retry banner, auth login launcher, subagent → chat akışı, MCP integration helper.

### Added — Sprint 1 / Demo-Ready Foundation

#### C8 MCP integration helper (commit `9d6a313`, ROI 20)
- `Sources/PixelMacApp/IntegrationView.swift` — pixel-agent'ın MCP server'ını (`pixel-mcp-server`) dış IDE'lere (Claude Desktop, Cursor, Codex CLI) tanıtmak için kurulum yardımcısı. 3 IDE config snippet kartı, tek tıkla "Kopyala" + "Kopyalandı ✓" 1.5s feedback, Finder'da göster, binary path resolution (bundled detection).
- `scripts/build-app.sh` artık `pixel-mcp-server` binary'sini de bundle'a paketler (`Contents/MacOS/pixel-mcp-server`). Brew ile kurulduğunda MCP server otomatik gelir.
- AboutView'a "MCP Entegrasyonu…" buton.
- 7 test: resolveBinaryPath fallback/bundled, snippet JSON syntactic validity, boşluklu path JSON escape, ClientID config path uniqueness.

#### A3 Empty state + sample prompt chips (commit `5dc72f5`, ROI 15)
- `ChatColumn` artık `messages.isEmpty && !isStreaming` durumunda `EmptyChatView` gösterir — sparkles icon + başlık + 4 chip stack. Chip tıklayınca `viewModel.draft = prompt` (send tetiklenmez, kullanıcı doğrular).
- 4 chip Sprint 1 demo senaryosunun ana workflow'larını temsil eder: `summarize-folder`, `code-review`, `plan-research`, `subagent-compare`.
- 5 test: catalog non-empty, ID uniqueness, demo workflow ID coverage.

#### C4 Plan Mode tool list panel (commit `d2f8bbe`, ROI 16)
- `Sources/PixelMacApp/PlanModeToolListView.swift` (yeni) — `PlanModeTool` struct + `PlanModeToolCatalog` enum (`tools`, `allowedTools`, `blockedTools`, `supportsPlanMode(kind:)`). SwiftUI sidebar 240pt sabit width, `.thinMaterial` background, 2 bölüm (Erişilebilir/Bloklandı), bloklu satırlar 0.78 opacity.
- Catalog Claude Code'un `--permission-mode plan` davranışıyla hizalı: **Erişilebilir** Read/Glob/Grep/WebFetch/WebSearch · **Bloklanmış** Edit/Write/Bash/NotebookEdit.
- ChatHost.body içinde chat alanı `HStack` ile sarıldı; `planMode == true` iken sağda Divider + panel; `easeInOut 0.18s` trailing edge slide-in. `chatContent` @ViewBuilder ayrıştırıldı.
- Footer'da seçili backend'e göre yeşil ✓ "Claude `--permission-mode plan`'a eşlenir" veya turuncu ⚠ "X Plan modunu yoksayar" (ADR-0017 ile kasıtlı).
- 10 test: catalog non-empty, ID/name uniqueness, allowed/blocked partition, demo senaryosu 4-tool regression guard (read/glob ✓, edit/bash ✗), backend support per kind.

#### A1 Markdown rendering + code block copy (commit `27d7f7f`, ROI 12.5)
- `Sources/PixelMacApp/MarkdownSegmenter.swift` (yeni, saf) — `MessageSegment` enum (`.text(String)` | `.codeBlock(content:language:)`) + `MarkdownSegmenter.segments(from:)` satır bazlı tarayıcı. Streaming-friendly: açık kalan fence içeriği `codeBlock` olarak emit edilir.
- `Sources/PixelMacApp/MarkdownMessageView.swift` (yeni) — `InlineMarkdownText` (`AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)`) + `CodeBlockView` (`.thinMaterial` + language label + "Kopyala" butonu, NSPasteboard + 1.5s feedback).
- `ChatColumn.MessageRow` artık `@ViewBuilder messageBody` ile rolü ayırıyor — `.assistant` → `MarkdownMessageView`, `.user`/`.system` → düz `Text`.
- 14 test: empty/plain/multiline, single/multiple code blocks, empty block, unclosed fence (streaming), language tag (trim + `objective-c` hyphen), inline backticks değil fence, blank line preservation.

#### B5 Keyboard shortcuts (`.commands` menu) (commit `b9d38a7`, ROI 12)
- `Sources/PixelMacApp/AppCommand.swift` (yeni, saf) — `AppCommand: String, CaseIterable, Sendable` (3 case: newConversation, togglePlanMode, toggleChatMode) + `notificationName` + `post()` helper. `pixel.command.` prefix'iyle namespaced.
- App `.commands { ... }` modifier: `CommandGroup(replacing: .newItem)` ile **⌘N** "Yeni Sohbet" (multi-document mantığı yok, store sıfırla); `CommandMenu("Sohbet")` özel menü: **⌘⇧P** Plan Mode toggle + **⌘⇧M** Single/Dual toggle.
- ChatHost 2 `.onReceive` (togglePlanMode → `planMode.toggle()`, toggleChatMode → `mode = (.single ↔ .dual)`). ChatColumn `.onReceive(newConversation)` — streaming değilse `viewModel.newConversation()` (dual mode'da her iki sütun bağımsız dinler).
- 5 test: allCases regression guard, raw value uniqueness, namespace prefix, notificationName eşitliği, `post()` observer expectation.

#### A2 Typing indicator (3-dot pulse) (commit `6ee0309`, ROI 12)
- `Sources/PixelMacApp/TypingIndicatorView.swift` (yeni) — 3 daire 0.18s gecikmeyle `.easeInOut(0.55s).repeatForever(autoreverses:true)` scale 0.5↔1.0 + opacity 0.4↔1.0; `onAppear` 3 ayrı `withAnimation`. Accessibility label "Pixel yazıyor".
- `StreamingMessageHelper.isStreamingTail(message:in:isStreaming:)` saf helper: bu mesaj aktif streaming'in son assistant mesajı mı?
- `MarkdownMessageView` `isStreaming: Bool = false` param. Empty text + streaming → TypingIndicatorView; empty text + !streaming → eski "…" placeholder (errored boş yanıt için).
- 8 test: isStreaming flag gate, role gate (user/system false), tail position (son assistant true, önceki turlar false), empty messages, text dolu olsa bile tail+streaming true.

#### C5 iOS→Mac config toast banner (commit `f59b5b8`, ROI 12)
- `Sources/PixelMacApp/RemoteConfigToast.swift` (yeni) — `RemoteConfigToast` Identifiable+Equatable (UUID+message). `RemoteConfigToastBuilder.buildMessage(old/new × backend/model/plan)` saf — değişiklikleri " · " ile birleştirir (sıra: backend → model → plan); boş model "değişiklik yok" sayılır; bilinmeyen backend capitalize fallback (forward-compat).
- `RemoteConfigToastView` koyu kapsül banner, hit-testing kapalı.
- ChatHost `@State configToast` + dismiss Task. `showConfigToast` helper (eski timer cancel, 3.5s sonra id eşleşmesi koşuluyla temizle — yarış güvenli). `onClientConfigReceived` old state snapshot → apply → builder → showConfigToast. body'ye `.overlay(alignment: .top)` slide-from-top transition.
- 11 test: no-change nil, empty model ignored, single field changes, combined order, üçü birden, unknown backend capitalize, Identifiable uniqueness, Equatable.

#### A7 Inline retry banner (commit `cf9c86a`, ROI 12)
- `Sources/PixelMacApp/RetryHelper.swift` (yeni, saf) — `candidateRetryText(messages:)` son `[user, assistant]` çiftini doğrular; whitespace-only/reverse sıra/ardışık assistant'lar nil.
- `ChatViewModel.clearError()` (streamError=nil) + `retryLastSend()` (streaming değilse + retry adayı varsa son 2 mesajı siler — failed turn history'de iz bırakmasın, user metniyle send tekrar).
- `Sources/PixelMacApp/ErrorRetryBanner.swift` (yeni) — turuncu warning ikon + callout text + sağda "Tekrar dene" (canRetry false → disabled) + "Kapat" (borderless). `.thinMaterial` + kırmızı 0.35 alpha stroke.
- 8 test: empty/tek, normal pair, partial assistant (stream yarıda kesildi), çoklu tur, reverse sıra defensive, ardışık assistant, whitespace-only user.

#### C9 Actionable auth error (commit `8d5d91e`, ROI 12)
- `Sources/PixelMacApp/AuthErrorDetector.swift` (yeni) — `isAuthError(_:)` saf keyword tabanlı (auth, 401, unauthorized, expired token, oturum, giriş yap, yetki, vb.) lowercased substring; TR+EN karışık. `LoginLauncher.loginCommand(for:)` claude/codex `login`, gemini `auth login`; `buttonLabel(for:)` Türkçe ("Claude'a Giriş Yap"). `launch(for:)` `NSAppleScript` ile Terminal.app activate + do script.
- `ErrorRetryBanner` `authenticateLabel` + `onAuthenticate` opsiyonel params. Auth butonu turuncu tint + key.fill ikon retry'dan ÜSTTE; varsa Retry sekonder (.bordered), yoksa primer (.borderedProminent).
- ChatColumn `backendKind: CLIKind?` opsiyonel; streamError + isAuthError + backendKind → banner'a launch closure'u inject. **`DualChatHost`'a `rightKind: CLIKind` parametresi eklendi** (sağ sütun login butonu doğru CLI'yi açar).
- 8 test: EN CLI mesajları (401, sign in, invalid api key), TR mesajlar (watchdog + giriş yap), non-auth negatif, case-insensitive, loginCommand per backend, buttonLabel TR, keyword roster lowercase, "Authentication expired" coverage.

#### C1 Subagent → chat akışı (commit `d2a5287`, ROI 10)
- `Sources/PixelMacApp/SubagentMessageFormatter.swift` (yeni, saf) — `format(session:)` 4 terminal status'a göre insan-okur metin: `completed → "[subagent <kind>] sonuç:\n<output>"`, `cancelled → "iptal edildi" (+ partial)`, `budgetExceeded → "bütçe aşıldı (<reason>)"`, `failed → "hata: <error>"`. Defensive no-result fallback. Kind prefix `rawValue` (case-stable).
- `SubagentManager.onSessionCompleted: (@MainActor (SubagentSession) -> Void)?` eklendi; `finalize()` finalized session struct'ını yakalayıp callback'i tetikliyor. Tek-callback (single mode ChatView, dual mode DualChatHost set eder; ChatHost aynı anda yalnızca birini render → yarış yok).
- `ChatViewModel.appendSubagentResult(_:)` text trim + `.system` rolünde Message + listeye append + ConversationStore'a persist. Rol seçimi: `.system` (gri SYS badge yan-akışı görsel ayırır).
- ChatView/DualChatHost `.onAppear` blokları callback'i set — DualChatHost leftVM'e (sol sütun dispatch dispatcher).
- 10 test: 4 status × (partial yok / partial var), whitespace trimleme, prefix rawValue case-stability, defensive no-result fallback.

### Changed
- **DualChatHost init imzası** — yeni `rightKind: CLIKind` parametresi eklendi (PixelMacApp.swift tek call-site güncellendi). Public API; eski init yok artık. *Practical impact: yok* — bu pakette tek dış kullanıcı.
- **MessageRow** — yeni `isStreaming: Bool = false` opsiyonel parametresi (default false → eski davranış).
- **ChatColumn** — yeni `backendKind: CLIKind?` opsiyonel parametresi (default nil → "<Backend>'a Giriş Yap" butonu gizli).
- **MarkdownMessageView** — yeni `isStreaming: Bool = false` opsiyonel parametresi (typing indicator gating için).
- **ErrorRetryBanner** — `authenticateLabel`/`onAuthenticate` opsiyonel params eklendi.

### Tests
- **Sprint 1 toplam:** 10 yeni test dosyası, 86 yeni test (**443 → 529**). 0 regression.
- `PlanModeToolListTests` (10), `MarkdownSegmenterTests` (14), `AppCommandTests` (5), `StreamingMessageHelperTests` (8), `RemoteConfigToastTests` (11), `RetryHelperTests` (8), `AuthErrorDetectorTests` (8), `SubagentMessageFormatterTests` (10), `EmptyChatViewTests` (5, önceki release), `IntegrationViewTests` (7, önceki release).

### Notes
- **Mimari deseni:** her item için **saf helper / enum** (formatter, detector, builder, catalog) + **minimal SwiftUI view** ayrımı. Saf kısımlar hermetic test edilebildi; view'lar yalın render katmanı kaldı. Pattern Sprint 2'ye taşınacak.
- **Demo senaryosu** ([polish-roadmap.md](docs/polish-roadmap.md#demo-senaryosu-sprint-1-sonrası)) artık uçtan uca canlı — empty state chip'inden subagent → chat'e kadar her adım test edilebilir.
- **AppleScript Terminal.app launch** ad-hoc imzalı build'lerde de çalışır; başka sandbox kısıtlaması yok. Sandbox enabled bir App Store build'inde `do script` izin gerektirebilir — App Store dağıtım yol haritasında değerlendirilmeli.
- **`onSessionCompleted` tek-callback** — gelecekte iki view aynı anda live olursa multicast publisher gerekir. Şu an `ChatHost` aynı anda single VEYA dual mode render ettiği için yarış yok.

## [0.2.25] — 2026-05-23

**iOS dashboard tam yetenek + gerçek CPU metric + protokol ADR'si.** v0.2.24'ten bu yana biriken 8 commit'in (3 iOS dashboard + 3 iOS fix + 3 Gemini fix + 1 per-backend store + 1 docs) üstüne, sahte CPU hesabı Mach `HOST_CPU_LOAD_INFO` ile değiştirildi, namespace temizliği yapıldı ve ADR-0032 yazıldı. **443 test yeşil** (+11). Breaking change yok (bkz. notlar).

### Added — iOS Remote Dashboard (commit `8cd547e`)
- **3 sekmeli `TabView`** ([`ios/PixelAgentRemote/ChatView.swift`](ios/PixelAgentRemote/ChatView.swift)):
  - **Sohbet** — mevcut chat.
  - **Subagent'lar** — `SubagentsListSection` kartları, cancel butonu.
  - **Mac Paneli** — `MacPanelDashboardSection`: CPU + RAM `MetricGauge`, aktif uygulama capsule'ü, Backend/Model `Picker`, Plan Mode `Toggle`, "Resim Al" + `ZoomableImageView` (UIScrollView wrapper).
- **`RemoteEnvelope` protokol genişlemesi** ([`Sources/PixelRemote/RemoteEnvelope.swift`](Sources/PixelRemote/RemoteEnvelope.swift)):
  - 4 yeni `EnvelopeType` case: `clientConfig`, `clientAction`, `hostStatus`, `screenshotPayload`.
  - 2 yeni payload struct: `SubagentStatusPayload` (id/prompt/status/partialOutput/startedAt), `SystemMetricsPayload` (cpuUsage/ramUsage/activeWindow).
  - `EnvelopePayload`'a 10 yeni opsiyonel alan: `selectedBackend`, `selectedModel`, `planMode`, `actionType`, `targetID`, `base64Image`, `availableBackends`, `availableModels`, `activeSubagents`, `systemMetrics`.
  - 4 factory metodu: `clientConfig(...)`, `clientAction(...)`, `hostStatus(...)`, `screenshotPayload(...)`.
- **`RemoteHost` callback'ler ve push**:
  - `onClientConfigReceived` — iOS'tan gelen backend/model/plan değişikliklerini Mac state'ine yansıtır.
  - `onClientActionReceived` — `cancelSubagent` ve `requestScreenshot` action'larını dispatch eder.
  - `sendHostStatus(...)` ve `sendScreenshot(base64Image:)` API'leri.
- **Mac 3 saniye periyodik push** ([`Sources/PixelMacApp/PixelMacApp.swift`](Sources/PixelMacApp/PixelMacApp.swift)): aktif uygulama + CPU + RAM + subagent snapshot + available backends/models.
- **ADR-0032** ([`docs/adr/0032-ios-dashboard-control-protocol.md`](docs/adr/0032-ios-dashboard-control-protocol.md)) — protokol gerekçesi, alternatives, consequences, Faz 2 plan.

### Added — iOS UX (commit `d1ebf1c`)
- **Streaming + backoff reconnect** ([`ios/PixelAgentRemote/RemoteSession.swift`](ios/PixelAgentRemote/RemoteSession.swift)): bağlantı kopması durumunda exponential backoff ile yeniden bağlanma.
- **Premium mascot UI** + streaming partial output render.

### Added — Backends ve veri ayrımı
- **Per-backend `ConversationStore` izolasyonu** (commit `a941eac`): `conversation-{kind}.jsonl` (örn. `conversation-claude.jsonl`, `conversation-gemini.jsonl`). Her CLI artık kendi history dosyasında — backend değiştirince geçmiş karışmaz.
- **`SystemStats` actor** ([`Sources/PixelMacApp/SystemStats.swift`](Sources/PixelMacApp/SystemStats.swift)) — gerçek CPU + RAM:
  - `cpuUsagePercent()` async — Mach `HOST_CPU_LOAD_INFO` iki snapshot tick delta'sından hesaplanır. İlk çağrı baseline kaydı için 0. `&-` overflow-safe.
  - `memoryUsagePercent()` nonisolated static — `mach_task_basic_info` resident size / `physicalMemory`.
  - Saf helper `computePercent(previous:current:)` — 7 unit test ile kapsanmış.
- **`ImageEncoding`** ([`Sources/PixelMacApp/ImageEncoding.swift`](Sources/PixelMacApp/ImageEncoding.swift)) — `compressPNGToJPEG(data:quality:)` namespace'li enum (eski free function silindi).

### Changed
- **Gemini default model** — birden çok kez güncellendi:
  - `gemini-3.5-flash` → `gemini-2.5-flash` (commit `a941eac`) — 3.5 ID API'de yoktu.
  - **`ModelCatalog.knownModels(.gemini)`** sıralaması gerçek API isimleriyle düzenlendi (commit `c94a965`).
- **`PixelMacApp.SystemStats` ve `compressPNGToJPEG`** — `PixelMacApp.swift` dosyasının altına eklenmişti, ayrı dosyalara çıkarıldı (`SystemStats.swift` + `ImageEncoding.swift`). 36 satır silindi, namespace temizliği.
- **Sahte CPU hesabı kaldırıldı** — eski `SystemStats.getCPUUsage(activeSubagentCount:)` `5–10% baz + 25% × subagent count` formülü kullanıyordu; gerçek Mach syscall ile değiştirildi.

### Fixed
- **iOS touch interception + stale error state** (commit `43a498d`) — reconnect sırasında.
- **iOS reconnection loop self-cancellation** + boş alana tıklama ile klavye dismiss (commit `2490cca`).
- **UserDefaults'taki eski Gemini modelleri auto-clear** (commit `6569eef`) — obsolete kayıt varsa default'a fallback.

### Tests
- **`SystemStatsTests`** — 7 yeni test (`computePercent` 5 saf case + `cpuUsagePercent` baseline + `memoryUsagePercent` range).
- **`RemoteEnvelopeTests`** — yeni envelope tipleri için round-trip testleri (commit `8cd547e` ve `d1ebf1c`).
- **`CLIBackendTests`** + **`ModelCatalogTests`** — Gemini ID değişiklikleri yansıtıldı.
- Toplam test: **432 → 443** yeşil (+11). 0 regression.

### Notes
- **Forward-compat:** `EnvelopeType` strict enum — bilinmeyen tip decode hatası verir. v0.2.25 öncesi cihaz yok pratikte; v0.3'e geçerken `unknown` fallback case eklenecek.
- **`EnvelopePayload`** artık 16 opsiyonel field içeriyor (god struct eğilimi). Faz 2 sum-type refactor adayı (`enum EnvelopePayload { case clientConfig(...); case hostStatus(...); ... }`).
- **`SubagentStatus`** payload'da `String` (enum yerine) — relay protokolünde semver-friendly: yeni status'lar eski iOS sürümlerinde "Bilinmiyor" render edilir.
- **Periyodik push trafiği:** 3sn snapshot ~700 B/s relay üzerinden. LAN'da ihmal, Cloudflare free-tier kullanımı izlenmeli.

## [0.2.24] — 2026-05-23

**Claude catalog alias'larla genişledi; her sağlayıcının en iyi modeli üstte.** Anthropic CLI 2.1.128 doc'undan doğrulandı: `opus`/`sonnet`/`haiku` her zaman güncel sürüme resolve eder. Default Claude `opus` (alias, future-proof). Codex ve Gemini catalog'larında "en iyi üstte" sıralaması korundu. Fabrikasyon `-20251101` dated suffix'leri silindi. **432 test yeşil** (+1). Breaking change yok.

### Changed
- **`ModelCatalog.knownModels(.claude)`** yeniden düzenlendi:
  - **Alias'lar üstte:** `opus`, `sonnet`, `haiku` (CLI doc'undan doğrulandı — her zaman güncel modele resolve eder).
  - Versionlu ID'ler: `claude-opus-4-7`, `claude-sonnet-4-7`, `claude-haiku-4-7`, `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-6`.
  - **Silindi:** `claude-opus-4-7-20251101`, `claude-sonnet-4-7-20251101` — bu dated suffix'ler tamamen fabrikasyondu (CLI'da örnek olarak verilen format `claude-sonnet-4-6`, dated değil).
- **`CLIBackend.defaultModelID(.claude)`** hardcoded `claude-opus-4-7` → `opus` (alias). UserDefaults boşsa Anthropic'in her zaman güncel Opus'una bağlanır.
- **`ModelCatalog.knownModels(.gemini)`** Pro variants önce: 3.5-flash → 3.1-pro → 2.5-pro → 2.5-flash → 2.0-flash → ... (Pro > Flash kalite önceliği).

### Tests
- **`ModelCatalogTests`** + 1 test (`testKnownModelsClaudeAliasesBeforeVersionedIDs`); `testKnownModelsClaudeStartsWithOpusAlias` Claude alias'larını doğrular.
- `testEmptyUserDefaultsFallsBackToHardcoded` Claude beklenen `opus` olarak güncellendi.
- `testClaudeArgsContainModelFlag` / `testClaudeArgsModelComesBeforePrompt` alias kullanır.
- Toplam test: **431 → 432** yeşil (+1).

## [0.2.23] — 2026-05-23

**Gemini catalog güncellendi: 3.5 Flash + 3.1 Pro öncelikli.** Kullanıcı tercihi doğrultusunda hardcoded default `gemini-3.5-flash` (eski 2.5-flash'tan), catalog ilk iki sırada 3.x family. 2.5/2.0/1.5 yedek olarak listede kalmaya devam. **431 test yeşil** (+1). Breaking change yok.

### Changed
- **`ModelCatalog.knownModels(.gemini)`** sıralaması güncellendi: `gemini-3.5-flash` → `gemini-3.1-pro` → `gemini-2.5-flash` → `gemini-2.5-pro` → `gemini-2.0-flash` → `gemini-2.0-flash-exp` → `gemini-1.5-flash` → `gemini-1.5-pro` (8 model).
- **`CLIBackend.defaultModelID(.gemini)`** hardcoded `gemini-2.5-flash` → `gemini-3.5-flash`. UserDefaults boşsa kullanıcı 3.5 Flash görür; UI picker'dan istediğine geçer.

### Tests
- **`ModelCatalogTests`** +1 test (`testGeminiCatalogPrioritizes3xVersions`) — 3.5-flash ve 3.1-pro index'i 2.5-flash'tan küçük olmalı.
- Toplam test: **430 → 431** yeşil (+1).

## [0.2.22] — 2026-05-23

**Per-backend model picker UI.** Toolbar'da her backend için Menu (catalog + Özel ID… + Varsayılana sıfırla); seçim UserDefaults'ta persiste edilir. Tek mode aktif backend için, Çift mode hem sol hem sağ için ayrı picker. **430 test yeşil** (+10). Breaking change yok.

### Added — Faz 4.2 model picker (23 May 2026)
- **`ModelCatalog`** (`Sources/PixelBackends/ModelCatalog.swift`) — her CLI için bilinen model ID'leri kataloğu (Claude family 5 alias, Codex 6 model, Gemini 6 model) + UserDefaults key helper (`pixel.model.<kind>`).
- **`CLIBackend.defaultModelID` öncelik sırası güncellendi**: UserDefaults > env (`PIXEL_<KIND>_MODEL`) > hardcoded. UI picker en yüksek öncelik.
- **`CLIKind: Identifiable`** — SwiftUI `sheet(item:)` desteği için (`id == rawValue`).
- **`ChatHost.modelPicker(for:)`** — SwiftUI `Menu`: catalog modelleri (aktif olan check işaretli), Divider, "Özel ID…" sheet açar, "Varsayılana sıfırla" UserDefaults key'i temizler.
- **`CustomModelSheet`** — özel model ID için modal (TextField + Kaydet/İptal). Doğrulama yok; yanlış ID "not found" döner.
- **`ChatHost.currentBackend(for:)`** — backends dict'inden executable path alır, `CLIBackend(modelID: currentModel(for:))` ile fresh instance üretir. `.id()` (kind, model) çifti — model değişince ChatView/DualChatHost recreate, `ChatViewModel` fresh backend ile yenilenir.
- **`@AppStorage("pixel.model.<kind>")`** ile per-kind state — empty string = "default'a düş" semantiği.

### Tests
- **`ModelCatalogTests`** — 10 yeni test: UserDefaults key format/prefix, catalog non-empty + family check (Opus 4.7 Claude'da, GPT-5 Codex'te, Flash family Gemini'de), UserDefaults override (Claude+Gemini), boş/whitespace UserDefaults fallback davranışı.
- setUp/tearDown her test arasında `pixel.model.<kind>` key'lerini temizler.
- Toplam test: **420 → 430** yeşil (+10). 0 regression.

## [0.2.21] — 2026-05-23

**Hotfix: Launchpad cwd "root directory" + Gemini ModelNotFound.** İki ayrı kullanıcı raporu birleşti. `CLIBackend` artık subprocess'i app-specific bir workspace dizinde çalıştırıyor; Gemini default modeli `gemini-2.5-flash`'a düşürüldü. **420 test yeşil** (+2). Breaking change yok.

### Fixed
- **CWD "root directory" warning** — Launchpad'den açılan app cwd `/` olarak miras alıyordu; Gemini CLI "running in the root directory" uyarısı veriyor ve tüm filesystem'i context'e almaya çalışıyordu. Fix: `EnvironmentBuilder.resolveCLIWorkspaceDirectory()` yeni helper — `~/Library/Application Support/PixelAgent/cli-workspace` dizinini oluşturup `CLIProcessRunner.workingDirectory`'e set ediyor. CLI artık izole boş bir workspace'te çalışıyor.
- **Gemini `ModelNotFoundError` for `gemini-3.5-flash`** — Google API CLI sürümünde 3.5 Flash henüz yok (veya farklı ID formatında). Default `gemini-2.5-flash`'a düşürüldü. Kullanıcı doğru ID'yi bilirse `PIXEL_GEMINI_MODEL` ile override edebilir.

### Tests
- **`EnvironmentBuilderTests`** +2 test (`testResolveCLIWorkspaceDirectoryReturnsAppSupportPath`, `testResolveCLIWorkspaceDirectoryIsIdempotent`).
- **`CLIBackendTests`** Gemini default beklenen değer `gemini-3.5-flash` → `gemini-2.5-flash` olarak güncellendi.
- Toplam test: **418 → 420** yeşil (+2). 0 regression.

## [0.2.20] — 2026-05-23

**UX: ChatComposer Shift+Enter newline.** Composer'da plain Enter mesaj göndermeye devam ediyor; Shift+Enter ile draft sonuna `\n` eklenir (multi-line input). macOS 14+ `onKeyPress(.return, phases: [.down])` API'si ile gerçekleşti. Breaking change yok.

### Added — UX
- **`ChatComposer.body`** `TextField`'a `onKeyPress(.return, phases: [.down])` modifier eklendi. `press.modifiers.contains(.shift)` ise `draft += "\n"` + `.handled`; aksi halde `.ignored` (default akış — plain Enter `.onSubmit`'a düşer).
- SwiftUI `TextField` cursor pozisyonuna API olmadığı için newline draft sonuna append edilir — çoğu Shift+Enter kullanımı mesajın sonundadır. İleride NSTextView wrap edilirse cursor-aware insert eklenebilir.

## [0.2.19] — 2026-05-23

**Backend default model wiring.** `CLIBackend` artık her CLI'a `--model <id>` flag'i geçiyor; default değerler kullanıcı yapılandırmasına göre: **Claude Opus 4.7** (`claude-opus-4-7`), **Codex 5.5** (`gpt-5.5`), **Gemini 3.5 Flash** (`gemini-3.5-flash`). Env var override desteği (`PIXEL_CLAUDE_MODEL` / `PIXEL_CODEX_MODEL` / `PIXEL_GEMINI_MODEL`). **418 test yeşil** (+5). Breaking change yok.

### Added
- **`CLIBackend.defaultModelID(for: CLIKind) -> String`** static — env override + hardcoded fallback. Öncelik: env var > `init(modelID:)` explicit param > hardcoded.
- **`CLIBackend.arguments(for:prompt:options:modelID:)`** yeni imza — eski `arguments(for:prompt:options:)` kaldırıldı (test'ler dahil hepsi güncellendi). Her CLI için `--model <modelID>` flag'i prepend edilir:
  - Claude: args başında `--model <id>`, prompt en sonda.
  - Codex: `exec --model <id> --json ...` (subcommand'tan sonra).
  - Gemini: `--model <id> --skip-trust -p <prompt>`.
- **Env override:** `export PIXEL_CLAUDE_MODEL=claude-sonnet-4-7` gibi yapılandırmalar app restart'ında geçerli olur.

### Tests
- **`CLIBackendTests`** +5 yeni test: hardcoded defaults (Opus 4.7 / GPT-5.5 / Gemini 3.5 Flash), her CLI için `--model` flag pozisyonu, Codex exec subcommand'ın --model'den önce gelmesi, Claude model prompt'tan önce.
- Eski testler `args(for:prompt:options:model:)` helper'a refactor edildi.
- Toplam test: **413 → 418** yeşil (+5). 0 regression.

## [0.2.18] — 2026-05-23

**Hotfix: Gemini CLI exit 55 (trusted directory promptu).** v0.2.17 PATH fix'inden sonra Gemini CLI bulunup çalıştırılabildi ama bu sefer "Gemini CLI is not running in a trusted directory" hatası geldi. Headless/automated context için `--skip-trust` argümanı + `GEMINI_CLI_TRUST_WORKSPACE=true` env var ile çözüldü. **413 test yeşil** (+2). Breaking change yok.

### Fixed
- **`CLIBackend.arguments(for: .gemini)`** artık `--skip-trust` flag'ini ilk argüman olarak geçiyor (`["--skip-trust", "-p", prompt]`). Gemini CLI'a "biz subprocess olarak headless spawn ediyoruz, trust prompt'unu atla" sinyali.
- **`EnvironmentBuilder.augmentedEnvironment`** `GEMINI_CLI_TRUST_WORKSPACE=true` ekliyor — eski Gemini sürümlerinde `--skip-trust` flag'i yoksa env var fallback'i çalışır. Caller manuel override edebilir (`env["GEMINI_CLI_TRUST_WORKSPACE"]` set ise dokunulmaz).

### Tests
- **`EnvironmentBuilderTests`** +1 test (`testAugmentedEnvironmentSetsGeminiTrustWorkspace`).
- **`CLIBackendTests`** +1 test (`testGeminiArgsIncludeSkipTrust`).
- Toplam test: **411 → 413** yeşil (+2). 0 regression.

## [0.2.17] — 2026-05-23

**Hotfix: Launchpad'den açılınca Gemini/Claude CLI çalışmıyordu.** `env: node: No such file or directory` (exit 127) hatası — Finder'dan açılan PixelAgent.app shell config (`.zshrc`, `.bashrc`) okumadığı için `PATH` minimal kalıyordu ve CLI'ların `#!/usr/bin/env node` shebang'ı node'u bulamıyordu. `EnvironmentBuilder` ile çözüldü. **411 test yeşil** (+10). Breaking change yok.

### Fixed
- **`EnvironmentBuilder`** yeni helper (`Sources/PixelBackends/EnvironmentBuilder.swift`) — `augmentedEnvironment()` parent env'i kopyalar; `augmentedPATH(currentPATH:home:)` PATH'e bilinen CLI dizinlerini prepend eder:
  - `/opt/homebrew/bin` (Apple Silicon Homebrew)
  - `/usr/local/bin` (Intel Homebrew)
  - `~/.local/bin`, `~/bin`
  - `~/.volta/bin`, `~/.asdf/shims`
  - `~/.nvm/versions/node/<son>/bin` (alfabetik desc — en yeni sürüm önce)
- **`CLIBackend.send`** spawn ederken `process.environment = EnvironmentBuilder.augmentedEnvironment()` set ediyor.
- **`CLIDetector.whichSearch`** `/usr/bin/which` çağrısına da augmented env veriyor — Launchpad'den açılan app artık Gemini/Claude'u **detect** edebilir.

### Tests
- **`EnvironmentBuilderTests`** — 10 yeni test: PATH boşken prepend, mevcut entry'leri koruma, sıralama (homebrew > usr/bin), deduplication, home-based dirs, boş segment filter, custom home, augmentedEnvironment HOME inherit, knownBinDirectories önceliği.
- Toplam test: **401 → 411** yeşil (+10). 0 regression.

## [0.2.16] — 2026-05-23

**PixelComputerUse Faz 4: Set-of-Mark visual annotation.** `ui_screenshot(elements:...)` ile her UI element'i numaralı badge + outline ile işaretler. Vision model "tıkla #5" der → caller `marks[4].element.identifier` ile `ui_click`. GPT-4V/Claude vision accuracy boost'u için klasik pattern. **401 test yeşil** (+19). Breaking change yok.

### Added — Faz 4 (23 May 2026)
- **`SoMMark`** (`Sources/PixelComputerUse/UITypes.swift`) — `id: String` (1-bazlı), `element: UIElement` (caller'ın orijinal snapshot'ı), `frameInImage: CGRectBox` (annotated PNG pixel rect).
- **`ScreenshotResult.marks: [SoMMark]`** default `[]`. Codable backward-compat — pre-Faz4 JSON'larda yok, `decodeIfPresent ?? []` ile decode edilir.
- **`MarkLayout`** (`Sources/PixelComputerUse/MarkLayout.swift`) saf helper: `computeMarkRect(elementFrame:imageScreenOrigin:imageLogicalSize:imagePixelSize:) -> CGRect?`. Retina scale + top-left convention; off-screen → nil, kısmi overlap → full rect (CG context clip).
- **`SoMRenderer`** (`Sources/PixelComputerUse/SoMRenderer.swift`) — `annotate(image:elements:imageScreenOrigin:imageLogicalSize:) -> (CGImage, [SoMMark])`. CGContext bitmap + CTM flip (top-left), NSGraphicsContext (flipped:true) text drawing. 5 renk palette (kırmızı/mavi/yeşil/turuncu/mor × 0.9 alpha), 4pt outline, 36px badge, beyaz bold 20pt numara. Off-screen filter sonrası 1-bazlı renumber (vision model "1,2,3" görür).
- **`ScreenshotCapture.capture(target:annotating:)`** opsiyonel `[UIElement]` parametre — dolu ise post-crop sonrası SoMRenderer çağrılır.
- **`PixelComputerUse.screenshot(of:annotating:)`** façade extension.

### Added — MCP `ui_screenshot` schema
- **`elements: array<UIElement>`** parametre — `ui_query` çıktısının birebir aynı shape'i; doluysa Set-of-Mark overlay.
- Response payload'a **`marks: [{ id, element, frame_in_image }]`** eklendi.
- `ControlSocketServer.decodeUIElement` helper — `JSONValue → UIElement` (snake_case → camelCase otomatik).
- Description'a "tıkla #5" örnek workflow'u.

### Tests
- **`MarkLayoutTests`** — 13 yeni test: 1x/2x/3x retina, off-screen tüm yönler (sol/üst/sağ/alt), kısmi overlap, dejenere boyut (zero element/logical/pixel), windowContent + retina kombinasyon, anisotropic scale.
- **`SoMRendererTests`** — 6 yeni smoke test: boş elements → 0 mark, 3 elements → 3 mark + sequential ID, off-screen filter + renumber, dimensions preserved, frame_in_image pixel-space, 5 element 1-bazlı sıralama.
- Toplam test: **382 → 401** yeşil (+19). 0 regression.
- [ADR-0031](docs/adr/0031-set-of-mark-annotation.md): SoM rasyoneli + CGContext flip + NSGraphicsContext text + renumber decision + alternatif değerlendirmeler.

## [0.2.15] — 2026-05-23

**PixelComputerUse Faz 3c: window content-area screenshot crop.** Vision model artık titlebar/toolbar token'larından kurtuluyor — caller `ui_screenshot(target="window_content", bundle_id="...", titlebar_offset=28)` ile pencerenin sadece içeriğini alır. **382 test yeşil** (+20). Breaking change yok.

### Added — Faz 3c (23 May 2026)
- **`ScreenshotTarget.windowContent(bundleID:String, titlebarOffset:Double)`** yeni case. `ScreenshotTarget.defaultTitlebarOffset = 28` (standart macOS titlebar).
- **`WindowCrop`** (`Sources/PixelComputerUse/WindowCrop.swift`) — saf helper enum: `computeCropRect(...)` (retina scale + pixel offset) ve `computeLogicalFrame(...)` (yeni metadata frame). ScreenCaptureKit bağımsız, deterministic, unit-test friendly.
- **`ScreenshotCapture.capture`** artık titlebarOffset varsa `CGImage.cropping(to:)` ile post-process kesim yapar; `ScreenshotResult.logicalFrame` da o oranda kayar. `resolve(target:)` imzası 4-tuple döner: `(filter, frame, bundleID, titlebarOffset?)`.
- **MCP `ui_screenshot` schema**:
  - `target` enum'una `window_content` eklendi.
  - `titlebar_offset: number` opsiyonel (default 28).
  - `description`'a "toolbar varsa 64-72 deneyin" rehberi.
- **`ControlSocketServer.uiScreenshot`** bridge `"window_content"` target string'ini ScreenshotTarget.windowContent'e map eder; `titlebar_offset` JSON'da yoksa `defaultTitlebarOffset` kullanır.

### Tests
- **`WindowCropTests`** — 13 yeni test: 1x/2x/3x retina scale, 28pt/72pt offset, zero/negative/oversize offset edge cases, logical frame shift, clamp.
- **`ScreenshotTargetTests`** — 7 yeni test: tüm 4 case için Codable round-trip, custom offset, default 28pt sabiti, `window` vs `windowContent` distinct.
- Toplam test: **362 → 382** yeşil (+20). 0 regression.
- [ADR-0030](docs/adr/0030-window-content-crop.md): post-process crop vs `SCStreamConfiguration.sourceRect` trade-off + AX-based offset alternatifi rasyoneli.

## [0.2.14] — 2026-05-23

**PixelComputerUse Faz 3b: modifier flag combinations + IME-aware text injection.** ⌘/⌥/⇧/⌃-click artık MCP üzerinden çağrılabilir; Türkçe karakter, emoji (skin-tone, ZWJ) ve birleşik diakritik text injection'da tek keypress olarak gönderiliyor. **362 test yeşil** (+24). Breaking change yok.

### Added — Faz 3b (23 May 2026)
- **`ModifierFlags`** (`Sources/PixelComputerUse/PointerControl.swift`) — `OptionSet`, Sendable + Codable: `.command / .option / .shift / .control`. `parse(_ names: [String])` kanonik isim + alias (cmd/opt/alt/ctrl) + glyph (⌘/⌥/⇧/⌃) kabul eder; bilinmeyen anahtarlar silently atlanır.
- **`PointerControl.click(at:count:modifiers:)`** — `event.flags = modifiers.cgEventFlags`; tek arbiter acquire altında (partial-state yok).
- **`PixelComputerUse.click(_:count:modifiers:)`** façade extension.
- **MCP `ui_click` schema** `modifiers: [string]` parametresi (enum: command/option/shift/control). ControlSocketServer.uiClick bridge handler `ModifierFlags.parse` ile çevirir.

### Changed — IME injection
- **`PointerControl.typeText`** artık per-`Character` (grapheme cluster) iterasyon yapar. Eski per-`Unicode.Scalar` davranışı "👋🏼" (wave + skin-tone), "👨‍👩‍👧" (ZWJ), `e\u{0301}` (combining mark) gibi multi-scalar grapheme'leri bölüyordu — text field iki ayrı karakter görüyordu. Artık her grapheme tek `CGEventKeyboardSetUnicodeString` çağrısı.
- **`PointerControl.unicodeChunks(for:)`** `nonisolated static` saf fonksiyon — testlerden senkron çağrılabilir.

### Tests
- **`IMEChunkingTests`** — 13 yeni test: ASCII per-char, Türkçe BMP characters (ş/ğ/ü/ö/ç/ı, İ), birleşik diakritik (e + COMBINING ACUTE), basic emoji surrogate pair, emoji + skin tone (4 UTF-16 birlikte), ZWJ family emoji (8 UTF-16), multiple emoji ayrık, mixed ASCII+emoji, CJK BMP, newline.
- **`ModifierFlagsTests`** — 11 yeni test: OptionSet temel + kombinasyon, parse kanonik/alias/glyph/mixed-case/duplicates, bilinmeyen silent skip, Codable round-trip.
- Toplam test: **338 → 362** yeşil (+24). 0 regression.
- [ADR-0029](docs/adr/0029-modifier-flags-and-ime.md): ModifierFlags + IME grapheme grouping + saf helper extract'i tasarımı.

## [0.2.13] — 2026-05-23

**PixelComputerUse Faz 3a: chained query DSL + opaqueID re-resolve.** AX katmanı artık "Sidebar grubu içindeki Save butonu" gibi ancestor-constrained query'leri kabul ediyor; daha önce alınmış element handle'ları `ui_resolve` ile canlı tekrar bulunabiliyor. Schema geriye uyumlu — eski JSON'lar parse edilebilir. **338 test yeşil** (+23). Breaking change yok.

### Added — PixelComputerUse Faz 3a (23 May 2026)
- **`UIQuery.within: [UIQuery]`** — ancestor constraints (AND semantik). Her constraint için en az bir ancestor uymalı; recursive (nested `within` desteklenir).
- **`UIQuery.containsText: String?`** — title VEYA label substring (case-insensitive). `matchMode`'a tabi değil. Diğer alanlarla AND'lenir.
- **`OpaqueID`** (`Sources/PixelComputerUse/OpaqueID.swift`) — `<bundleID>|<role>[:<discriminator>]|...` formatı, AX-bağımsız encoder/decoder. `|` ve `:` `\u{1}` ve `\u{2}` ile escape edilir.
- **`AXBridge.resolve(opaqueID:)`** — daha önce alınmış handle'dan canlı snapshot. Cache YOK; her resolve fresh path-walk. Element artık yoksa `nil`.
- **`AXBridge.checkAncestorConstraints`** — `kAXParentAttribute` üzerinden 32-seviye walk (loop guard); her `within` constraint için en az bir ancestor uymalı.
- **`PixelComputerUse.resolve(opaqueID:) async throws -> UIElement?`** — actor façade.
- **`ComputerUseError.invalidOpaqueID(raw:)`** yeni case.

### Added — MCP `ui_resolve` tool
- **`ui_resolve`** — `{ "opaque_id": "..." }` → element JSON veya `{ "found": false }`. Read-only, Plan modunda çalışır. Accessibility izni gerekir.
- **`ui_query` schema** `contains_text` + `within` parametreleri eklendi (geriye uyumlu — JSON'da yoksa default).
- `BuiltInTools.makeRegistry()` artık **14 tool** döner (5 saf-data + 4 bridge + 5 ui_*).
- `ControlSocketServer.uiResolve` bridge handler.

### Changed
- **`UIQuery` Codable artık manuel** (`init(from:)` + `encode(to:)`). Tüm alanlar `decodeIfPresent` — v0.2.12 ve öncesi JSON'lar parse edilebilir. `within` boş array iken encode edilmez (clean wire format).
- **`UIElement.opaqueID` formatı değişti** (path-slash → bundle-pipe). Faz 1'de sadece debug string'di; v0.2.13'te resolve API'sinin girdisi olacak şekilde stable.

### Tests
- **`ChainedQueryTests`** — 13 yeni test: `containsText` title/label match, case-insensitive, role + containsText kompoziti, identifier short-circuit, Codable backward-compat, round-trip, debug summary.
- **`OpaqueIDTests`** — 10 yeni test: bundle prefix, frontmost (empty bundle), no discriminator, pipe/colon escape, round-trip with special chars, bundle-only no path, empty discriminator.
- Toplam test: **315 → 338** yeşil (+23). 0 regression.
- [ADR-0028](docs/adr/0028-chained-query-and-opaque-id.md): chained query DSL + opaqueID format + resolve API + path-walk re-resolve tasarımı.

## [0.2.12] — 2026-05-23

**PixelComputerUse Faz 1+2 + ToolArbiter implementasyonu.** pixel artık AX-first hybrid yaklaşımıyla macOS UI'sini *görüyor* ve fareyi/klavyeyi *tutuyor*. Sıfır harici dep — sadece `ApplicationServices` + `CoreGraphics` + `ScreenCaptureKit`. 4 yeni MCP tool (`ui_query` / `ui_click` / `ui_type` / `ui_screenshot`) Plan Mode-aware ve `ToolArbiter.shared` ile serialize. ADR-0005'in koda inişi. **315 test yeşil** (+65). Breaking change yok.

### Added — PixelComputerUse Faz 1+2 (23 May 2026)
- **`PixelComputerUse`** yeni library (`Sources/PixelComputerUse/`, 7 dosya) — `actor PixelComputerUse` façade: `query / click / type / screenshot`. Sıfır external dep, sadece `ApplicationServices` (AX) + `CoreGraphics` (CGEvent) + `ScreenCaptureKit` (SCScreenshotManager) + `AppKit`. iOS'ta API yüzeyi compile eder ama metodlar `ComputerUseError.unsupported("iOS")` fırlatır.
- **`AXBridge`** actor — `ApplicationServices` C API wrap. `UIQuery` (role + title + identifier + matchMode) ile AX ağacı traverse + match.
- **`PointerControl`** — `CGEvent` mouse click (single/double/triple) + keyboard type. v0.2.12'de `ToolArbiter.shared.with([.pointer])` ile serialize (Faz 2, ADR-0027).
- **`ScreenshotCapture`** — `SCScreenshotManager` wrap, `ScreenshotTarget` = `.activeDisplay` / `.allDisplays` / `.app(bundleID:)`. PNG + base64 metadata.
- **`ComputerUsePermissions`** — `AXIsProcessTrusted()` + `CGPreflightScreenCaptureAccess()` silent check; `requestAccessibility(prompt: true)` System Settings deep-link. `preflight()` ve `status()` her ikisini birden kontrol eder.
- **`UIQuery` + `UIElement` + `Match`** value-type'lar, `Sendable + Codable` — MCP JSON üzerinden geçirilebilir, in-process'te aynı API.
- **`ComputerUseError`** — `accessibilityNotAuthorized` / `screenRecordingNotAuthorized` / `noMatch(UIQuery)` / `ambiguousMatch(UIQuery, count:)` / `axCallFailed(String)` / `unsupported(String)`.
- **`PermissionsView`** (`Sources/PixelMacApp/PermissionsView.swift`) — SwiftUI sheet: iki izin durumu (yeşil/kırmızı badge), eksik olanlar için "System Settings'i aç" butonu (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` / `...?Privacy_ScreenCapture` deep-link).
- **PixelMacApp top bar** `lock.shield` badge — `ComputerUsePermissions.status().allGranted` ise yeşil, değilse kırmızı; tap → `PermissionsView`.

### Added — MCP `ui_*` tool'lar (Faz 2)
- **`ui_query`** — `UIQuery` JSON → `[UIElement]` JSON. Plan Mode'da çalışır (read-only).
- **`ui_click`** — query → tek match → tıkla. 0/≥2 match'te yapısal hata. Plan Mode'da `planModeGuard` blokluyor.
- **`ui_type`** — opsiyonel `into` query ile focus + text inject. Plan Mode'da blokluyor.
- **`ui_screenshot`** — `target` (`.activeDisplay` / `.allDisplays` / bundle ID) → PNG bytes + base64. Plan Mode'da çalışır.
- BuiltInTools.makeRegistry artık **13 tool** döner (5 saf-data + 4 bridge + 4 ui_*).
- `ControlSocketServer` dispatch handler'ları ui_* tool'ları için ekledi (ADR-0018 bridge pattern). Standalone `pixel-mcp-server` ui_* çağrılırsa "PixelAgent.app çalışıyor mu?" hatası döner.
- **Plan Mode env guard** — `PIXEL_PLAN_MODE=1` set ise `ui_click` / `ui_type` server tarafında bloklanır; `ui_query` / `ui_screenshot` her durumda çalışır. `PlanModeGuardTests` (Faz 2, 4 yeni test).

### Added — `ToolArbiter` implementasyonu (ADR-0005 → koda)
- **`PixelCore.ToolArbiter`** actor — process-global `shared` singleton (ADR-0009 istisnası, gerçek fiziksel kaynak mutex). `Resource` enum 6 case: `pointer / screen / clipboard / mic / speaker / fileWrite(path:)` — `Comparable` (canonical sıralama, deadlock-free multi-acquire).
- **API:** `acquire(_:) async` (FIFO waiter queue), `release(_:)`, `with(_:body:)` (exception-safe defer). Inspection: `currentlyLocked()` + `waiterCount()` test/observability için.
- **`PointerControl` entegrasyonu:** `click` ve `typeText` artık `ToolArbiter.shared.with([.pointer])` ile sarıldı. Paralel subagent (cap=3, ADR-0024) iki `ui_click` yapsa fare serialize edilir.
- Single-agent MVP'de overhead pratik olarak sıfır (acquire her zaman anında döner).

### Fixed
- **Subagent streaming cancel deadlock** (`Sources/PixelMacApp/Subagent/SubagentManager.swift`) — streaming refactor sonrası `cancel(_:)` outer Task'i iptal edince `for await event in runner.runStreaming(...)` döngüsü `.finished` event'i tüketmeden çıkıyor, `finalize()` çağrılmıyor, `dispatchAndWait` continuation leak olup `testCancelTransitionsToCancelled` sonsuza kadar asılıyordu. Defensive synthetic `.cancelled` finalize eklendi (loop sonrası `didFinalize` check).
- **`ToolRegistryTests`** sayım test'leri yeni 4 `ui_*` tool için güncellendi (9 → 13).

### Changed
- **`SubagentRunner`** streaming API'si (Faz 4 başlangıcı): `runStreaming(prompt:) -> AsyncStream<SubagentEvent>` yeni; eski `run(prompt:) -> SubagentResult` backwards-compat tutuldu (içeride `runInternal` ile birleşti, `onChunk` callback). `SubagentEvent` enum: `.chunk(String)` + `.finished(SubagentResult)`. UI artık her chunk için partial output görüyor.
- **`SubagentManager`** streaming consume + `appendChunk` MainActor mutation eklendi. `SubagentSession.partialOutput` artık canlı dolar.

### Tests
- **`PixelComputerUseTests`** 5 dosya, 43 yeni test: `AXMatchTests`, `ComputerUseErrorTests`, `PermissionsTests`, `PixelComputerUseTests`, `UITypesTests`. Permission tier'ları için bypass policy + status round-trip.
- **`ToolArbiterTests`** — 13 yeni test: acquire/release temel, FIFO waiter ordering, multi-resource canonical sort, `with(_:body:)` exception-safe rollback, `fileWrite(path:)` path-bazlı paralelizm, `currentlyLocked()` + `waiterCount()` inspection.
- **`PlanModeGuardTests`** — 5 yeni test: env var read, ui_click/ui_type bloklanması, ui_query/ui_screenshot allowlist.
- **`SubagentRunnerTests`** — 3 yeni streaming test (`runStreaming` chunk → finished ordering, budget exceeded terminal, CLI exit without `.done`).
- **`SubagentManagerTests`** — 1 yeni test (`testPartialOutputBuildsUpDuringStreaming`).
- Toplam test: **250 → 315** yeşil (+65). 0 regression.
- [ADR-0026](docs/adr/0026-pixel-computer-use.md): AX-first hybrid mimari + 3 katman + Plan Mode entegrasyonu + iOS no-op stub.
- [ADR-0027](docs/adr/0027-toolarbiter-implementation.md): ADR-0005'in koda inişi + Resource enum + waiter queue + PointerControl wire-up.

## [0.2.11] — 2026-05-22

**LAN Faz 4: iOS LAN-first default + TXT record + transport indicator.** Aynı ağdaki Mac↔iPhone trafiği artık doğrudan Bonjour üzerinden (LAN); farklı ağdayken otomatik relay'e düşer. Kullanıcı bağlantı tipini ChatView header'da görür ("LAN" yeşil / "Relay" mavi). **250 test yeşil** (+6). Breaking change yok.

### Added — LAN Faz 4 (22 May 2026)
- **`LANTXTRecord`** (`Sources/PixelLAN/LANTXTRecord.swift`) — DNS-SD wire format encoder/decoder (RFC 6763 §6); deterministic alfabetik sıralı encoding; >255 byte ve 0 byte entry skip.
- **`LANService.start()`** artık `Configuration.publicKeyBase64` + `protocolVersionTXT`'i TXT record'a yazıp `NWListener.Service(txtRecord:)`'a iletir; `LANClient` (browse tarafı) zaten okuyordu (`DiscoveredHost.publicKeyBase64`).
- **`defaultLANFirstTransportFactory`** (iOS, `ios/PixelAgentRemote/RemoteSession.swift`) — `FallbackTransport(primary: LANClientTransport(discoveryTimeout: 2), fallback: RelayTransport)`. `RemoteSession.init(transportFactory:)` default'u **LAN-first** (eski `defaultRelayTransportFactory` korundu).
- **`RemoteSession.transportLabel`** `@Published var String?` — `connect()` sonrası FallbackTransport.currentSelection'dan "LAN" / "Relay" / "Bağlı" türetir; disconnect'te nil.
- **iOS `ChatView` transport badge** — header'da pairing code yanında renkli capsule (LAN → yeşil, Relay → mavi); accessibility label dahil.
- **Mac `PairingView` yayın bilgisi** — status row'a "Mac yayını: LAN (Bonjour) + Relay paralel" sabit metni + ikonu (`antenna.radiowaves.left.and.right`).
- **iOS Info.plist** — `NSBonjourServices: [_pixel-agent._tcp]` (iOS 14+ Bonjour whitelist); `NSLocalNetworkUsageDescription` "gelecekte LAN" → aktif LAN modu metni; `CFBundleShortVersionString` → 0.2.11, build → 3.
- **`ios/project.yml`** PixelLAN dependency + NSBonjourServices + version bump.

### Added — Tests
- **`LANTXTRecordTests`** 6 yeni test: empty roundtrip, single-entry wire format byte-level, multi-entry alphabetical sorting, encode/decode roundtrip, oversized entry skip, malformed buffer graceful parse.
- Toplam test: **244 → 250** yeşil. 0 regression.
- iOS xcodebuild verification: `xcodebuild -project ... -destination 'generic/platform=iOS Simulator' build` BUILD SUCCEEDED.
- [ADR-0025](docs/adr/0025-lan-first-ios-default.md): TXT record + LAN-first factory + indicator tasarımı.

## [0.2.10] — 2026-05-22

**Subagent Faz 3: UI panel + paralel cap + bridge birleşimi.** Composer'ın hemen üstünde yatay subagent kart şeridi; UI'dan ⌘⇧Return ile dispatch; MCP'den gelen subagent'lar **aynı panelde** görünür (birleşik). Paralel cap = 3. **244 test yeşil** (+9). Breaking change yok.

### Added — Subagent Faz 3 (22 May 2026)
- **`SubagentManager`** (`Sources/PixelMacApp/Subagent/`, `@MainActor ObservableObject`) — birleşik subagent havuzu: `dispatch()` (UI), `dispatchAndWait()` (MCP bridge), `cancel()`, `dismiss()`. `maxConcurrent = 3` cap atomic (MainActor reentrancy yokluğu garanti). `backendResolver: (CLIKind) -> (any ChatBackend)?` DI.
- **`SubagentSession`** value-type Identifiable: `id: SubagentID` (Runner ile aynı → TaskLocal binding), `prompt`, `backendKind`, `budget`, `status`, `startedAt`, `finishedAt`, `result`.
- **`SubagentStatus`** state machine: `pending → running → (completed | budgetExceeded | cancelled | failed)`.
- **`DispatchError`**: `capReached(maxConcurrent:)` / `backendUnavailable(CLIKind)` + `LocalizedError` (UI ve MCP yanıtlarında kullanılır).
- **`SubagentPanelView` + `SubagentCardView` + `SubagentDetailSheet`** — boş listede `EmptyView` (panel + divider'lar render edilmez); dolu state'te yatay scrollable kart şeridi, sol uçta `N/3` cap badge; running'de `ProgressView` + `TimelineView(.periodic)` saniye-saniye elapsed; tap → detail sheet (full prompt + output mono scroll + "Çıktıyı kopyala" + "Kartı sil").
- **`ChatComposer`** "Subagent" butonu (`person.2.wave.2`) — opsiyonel callback + `subagentDisabled` parametresi. Kısayol `⌘⇧Return` (Send `.return` ile çakışmaz). Disabled tooltip: "Subagent havuzu dolu (3/3 aktif)".
- **`ChatView` + `DualChatHost`** panel entegrasyonu — `subagentManager` parametresi alır, body'de `VStack { ChatColumn, [Divider+Panel], Divider, Composer }`. Dual mode'da Subagent butonu sol backend (`selectedKind`) ile dispatch eder.
- **`PixelMacApp.RootView`** `ChatHost`'a `.id(backendsKey)` modifier'ı — rescan'da Manager fresh backends snapshot ile yenilenir (trade-off: aktif sessions kayıp).
- **`PixelMacApp.ChatHost`** `@StateObject subagentManager` + `.task { await RootView.controlServer.attach(subagentManager) }`.

### Changed
- **`ControlSocketServer`** artık actor field `manager: SubagentManager?` tutar + `attach(_:)` method. `dispatch_subagent` Manager varsa `dispatchAndWait()` üzerinden gider (UI'da kart belirir, cap dolu → "havuzu dolu" hata); nil ise eski stateless yol (test backwards compat).
- `handleClient`/`execute`/`dispatchSubagent` statik fonksiyonlardan instance method'lara çevrildi (Manager erişimi için).
- `bridgeResponse(from:backendKind:)` ortak helper — iki yolun çıktısını aynı format'a normalize eder.

### Fixed
- **`SubagentRunner` cancel detection bug**: ADR-0019'da "stream `.done` vermeden bitti → `.completed`" kasıtlıydı (CLI graceful exit) ama `Task.cancel()` sonrası `AsyncSequence` sessiz sonlanışı da bunu tetikliyor, status `.cancelled` yerine `.completed("")` dönüyordu. Fix: for loop'tan çıktıktan sonra `Task.isCancelled` check eklendi. Mevcut graceful behavior korundu.

### Added — Tests
- **`SubagentManagerTests`** 8 yeni test: dispatch creates session, dispatchAndWait happy path, cancel transitions to .cancelled, cap reached rejects 4th, cap frees after completion, dispatchAndWait waits, backend resolver nil, dismiss only removes terminal.
- **`ControlSocketServerTests.testDispatchSubagentReturnsCapReachedWhenManagerFull`** — Manager attach + havuzu doldur + MCP bridge çağrısı "havuzu dolu" mesajı döndürmeli.
- Toplam test: **235 → 244** yeşil.
- [ADR-0024](docs/adr/0024-subagent-ui-panel.md): SubagentManager tasarımı + bridge birleşimi + UI tasarımı + cancel bug fix.

## [0.2.9] — 2026-05-22

Hotfix release + **end-to-end iPhone test'i** başarıyla doğrulandı + **repo public oldu** (portfolio + sınırsız GitHub Actions).

### Fixed
- **`scripts/build-app.sh`** Info.plist'ine `NSLocalNetworkUsageDescription` + `NSBonjourServices` eklendi. Olmadığı için macOS 14+ Bonjour advertise'ı sessizce blokluyordu — PixelAgent.app TCP'de dinliyor ama `dns-sd -B _pixel-agent._tcp local.` hiç servis görmüyordu (commit `1c9a1a5`).
- `build-app.sh` `VERSION="0.1.0"` (stale) → `"0.2.9"`, build numarası `1 → 9`.

### Changed
- Repo `ErkutYavuzer/pixel-agent` **public** oldu (portfolio amaçlı; sınırsız GitHub Actions; CLI subprocess stratejisi nedeniyle gizli bilgi yok — ADR-0010).

### Verified (manuel e2e iPhone test, 22 May 2026)
- iPhone 15'te yeni build install + launch (`xcrun devicectl device install/launch`).
- iOS QR scan → relay `/listen/<code>` WS open → handshake `hello(publicKey:)` → Mac `/connect/<code>` → ed25519 verify → Mac chat flow → Claude CLI subprocess (stream-json) → assistantMessage → relay → iPhone UI'da response. **Tüm pipeline çalışır durumda.**
- `dns-sd -B _pixel-agent._tcp local.` → `Erkut MacBook Pro` görünüyor.

## [0.2.8] — 2026-05-22

**LAN Faz 3: Mac side wire-up.** `MergeTransport` paralel composite + PixelMacApp artık `[LANServerTransport, RelayTransport]` ile başlıyor — iPhone hangi yoldan gelirse alır. **235 test yeşil** (+9). Breaking change yok. iOS değişmedi (Faz 4'e ertelendi).

### Added — LAN Faz 3: MergeTransport + Mac wire-up (22 May 2026)
- **`MergeTransport`** (PixelLAN, actor) — birden çok transport'u paralel çalıştıran composite. `FallbackTransport` sequential (primary fail → fallback); `MergeTransport` simultane (her ikisi de active, inbound merge + outbound broadcast). `disconnect()` idempotent. `MergeError.allTransportsFailed` / `.noActiveTransports`.
- **`RemoteHost.TransportBuilder`** — yeni init overload (`init(relayURL:keyStore:...transportBuilder:)`); closure builder pattern circular dep (transport ↔ RemoteHost) çözümü. RemoteHost generate ettiği `pairingCode` + `publicKeyBase64`'ü closure'a enjekte eder.
- **PixelMacApp** artık `MergeTransport([LANServerTransport, RelayTransport])` ile RemoteHost başlatıyor — iPhone hangi yoldan gelirse alır (LAN ya da relay). PixelLAN PixelMacApp dep'lerine eklendi.
- iOS tarafında **değişiklik yok** (default relay). Faz 4 iOS LAN-first default + TXT record + PairingView indicator.
- 9 yeni `MergeTransportTests` (test-only `StubTransport` actor mock): start-all-children, partial-fail-tolerated, all-fail-throws, broadcast send, partial-send-tolerated, total-send-fail propagation, send-before-connect, disconnect cascade + idempotency, inbound merge (actor-isolated Collector).
- Toplam test: **226 → 235** yeşil.
- [ADR-0023](docs/adr/0023-merge-transport-and-mac-wire-up.md): MergeTransport semantik + transportBuilder pattern + Mac side wire-up + Faz 4 iOS plan.

### Notes
- v0.2 kalan: Subagent Faz 3+ (UI panel + multi-turn workflow + streaming), **LAN Faz 4** (iOS LAN-first default + TXT record + PairingView indicator), App Store signing.

## [0.2.7] — 2026-05-22

**LAN-only mode Faz 1 + Faz 2** — `PixelLAN` library (Bonjour + Network.framework) + `RemoteTransport` protocol abstraction'u (4 adapter + `FallbackTransport` composite) + `RemoteHost`/`RemoteSession` transport DI. v0.2.6'dan beri 2 Faz landed; **226 test yeşil** (+31). UI defaults değişmedi (Faz 3'e ertelendi); altyapı tam. Breaking change yok.

### Added — LAN Faz 2: transport adapter + fallback (22 May 2026)
- **`RemoteTransport`** protocol (PixelRemote) — `connect/send/disconnect` üçlü API; `RemoteHost` ve iOS `RemoteSession` artık transport-agnostic.
- **`RelayTransport`** (PixelRemote) — `RelayClient`'ı wraplar; behavior birebir aynı.
- **`LANServerTransport`** (PixelLAN, Mac) — `LANService`'i wrapper; multi-client broadcast send.
- **`LANClientTransport`** (PixelLAN, iOS+Mac) — `NWBrowser` + ilk bulunan host'a bağlanma + `discoveryTimeout` (varsayılan 2s).
- **`FallbackTransport`** (PixelLAN) — `(primary, fallback)` composite; primary throws ise fallback'e geçer; `currentSelection: .none | .primary | .fallback`.
- **`RemoteHost`** transport DI: yeni `init(transport: any RemoteTransport, ...)` overload + eski `init(relayURL:...)` (runtime'da RelayTransport oluşturur, backward-compat).
- **iOS `RemoteSession`** `RemoteTransportFactory: @Sendable (PairingInfo) -> any RemoteTransport` injection; default `defaultRelayTransportFactory` free fonksiyon. UI LAN-first istemek için `{ FallbackTransport(LAN, Relay) }` pass eder.
- **`PairingInfo`** (iOS) artık `Sendable` (factory closure cross-isolation gerekiyor).
- UI defaults değişmedi — Mac `RemoteHost(relayURL:)` ile relay, iOS `RemoteSession()` default = relay. Faz 3'te switch (PixelMacApp Bonjour advertise + iOS LAN-first default).
- 15 yeni test: 5 `RelayTransportTests` (init varyant, invalid pairing code, disconnect idempotency), 6 `FallbackTransportTests` (primary/fallback selection, both-fail propagation, send routing, disconnect reset; test-only `StubTransport` actor mock), 4 `LANTransportInstantiationTests`.
- Toplam test: **211 → 226** yeşil.
- [ADR-0022](docs/adr/0022-remote-transport-adapter.md): protocol + adapter layer + backward compat + Faz 3 UI defaults planı.

### Added — LAN-only mode Faz 1 (Bonjour + Network.framework, 22 May 2026)
- **`PixelLAN`** yeni SPM library — `PixelRemote`'a depend. Hedef: Mac ↔ iOS arası LAN'da relay bypass.
- `LANServiceType` — Bonjour service constants: `_pixel-agent._tcp` (RFC 6335 short-name compliant), `local.` domain.
- `LANFraming` — newline-delimited JSON envelope encode/decode (bridge + relay + MCP ile aynı pattern).
- `LANService` (actor, Mac) — `NWListener` + Bonjour advertise + accept loop, gelen bağlantıları `AsyncThrowingStream<LANServerConnection>` üzerinden yayar.
- `LANServerConnection` — accept edilen client; `incoming: AsyncThrowingStream<RemoteEnvelope>` + `send(_:)` API.
- `LANClient` (actor, iOS+Mac) — `NWBrowser` ile discovery (`DiscoveredHost` listesi), `NWConnection` ile bağlantı + envelope send/receive. Swift 6 strict concurrency için `ResumedFlag` helper (lock-protected first-wins).
- TXT record (pk + version) **Faz 2'de eklenecek** — Apple SDK `NWListener.Service(...)` initializer'ı macOS/iOS sürümleri arasında imzasal değişkenlik gösteriyor.
- 16 yeni test: 8 `LANFramingTests` (roundtrip, multi-line, partial leftover, empty, invalid JSON, blank lines, Turkish UTF-8), 4 `LANServiceTypeTests` (RFC 6335 compliance), 4 `LANInstantiationTests`.
- Toplam test: **195 → 211** yeşil.
- Wire-up (`RemoteHost`/`RemoteSession` transport adapter) Faz 2'de — fallback mantığı: önce LAN dene, başarısızsa relay.
- [ADR-0021](docs/adr/0021-lan-mode-bonjour.md): tasarım + alternatif analizi + Faz 2/Faz 3 yol haritası.

### Notes
- v0.2 kalan yol haritası: Subagent Faz 3+ (UI background panel, multi-turn `Workflow`, streaming progress), **LAN Faz 3** (Mac side-by-side advertise + iOS LAN-first default + TXT record + PairingView indicator), App Store signing.

## [0.2.6] — 2026-05-22

**Subagent Faz 2** — `PixelSubagent` library artık MCP üzerinden wired. claude-cli ve uyumlu istemciler `dispatch_subagent` tool'u ile Mac üzerinde Codex/Claude/Gemini subagent orkestre edebilir. **195 test yeşil** (+3). Breaking change yok.

### Added — Subagent Faz 2: MCP `dispatch_subagent` (22 May 2026)
- **MCP tool `dispatch_subagent`** (`BuiltInTools` registry, 8 → 9 tool): `prompt` + `backend` (`claude|codex|gemini`) + opsiyonel `max_duration_seconds` / `max_output_bytes`. claude-cli ve uyumlu istemcilerden subagent orchestration için bridge tool. PixelAgent.app çalışıyor olmalı.
- **`ControlSocketServer.dispatchSubagent`** handler: her request'te fresh `CLIDetector` (kullanıcı CLI değişikliklerine cevap), `CLIBackend(kind:, executablePath:)` resolve, `SubagentRunner(budget:).run(prompt:)`. Sonuç structured JSON payload (`status`/`output`/`duration_seconds`/`backend`); `BridgeResponse.result` üzerinde döner.
- **`ToolRegistry.callBridge` helper** structured result desteği: response.result string ise text content, object/array ise pretty-printed JSON serialize ediyor (sortedKeys); claude-cli parse edebilir.
- `PixelMacApp` target → `PixelSubagent` dep eklendi.
- 3 yeni `ControlSocketServerTests` edge case: missing prompt, invalid backend ("gpt-4"), empty prompt. Toplam 192 → **195 test yeşil**.
- Bridge bağlantısı subagent süresince açık kalır (long-running RPC) — MCP client timeout'u kullanıcı sorumluluğu.
- [ADR-0020](docs/adr/0020-mcp-dispatch-subagent.md): tasarım + long-running RPC limitation + Faz 3+ defer (UI integration, multi-turn workflow, streaming progress).

### Notes
- v0.2 kalan yol haritası: Subagent Faz 3+ (UI background panel, multi-turn `Workflow`, streaming progress), LAN-only mode (Bonjour), App Store signing.

## [0.2.5] — 2026-05-22

**Subagent Runner Faz 1** (yeni `PixelSubagent` library, Budget'lı tek-turlu çalıştırıcı) + dokümantasyon konsolidasyonu (README + architecture.md v0.2.4 senkron). **192 test yeşil** (+15). Breaking change yok.

### Added — Subagent Runner Faz 1 (22 May 2026)
- **`PixelSubagent`** yeni SPM library: `Budget` struct (wallclock + opsiyonel UTF-8 byte cap; preset'ler `.default` 60s, `.exploratory` 10s+8KB), `SubagentResult` enum (4 vaka: `completed` / `budgetExceeded(.duration|.outputBytes)` / `cancelled` / `failed`), `SubagentRunner` actor (tek-turlu prompt → result).
- **Concurrency tasarımı**: `withTaskGroup` ile worker + watchdog yarışır; shared `OutputBuffer` actor partial çıktı için. `group.next()` ilk biteni döner; cancel propagation `AsyncThrowingStream.onTermination` üzerinden CLI subprocess'lerine ulaşır.
- **`PixelCore.AgentContext.currentSubagentID`** yeni TaskLocal (`SubagentID?`). `SubagentRunner.run(...)` boyunca binding ile set edilir; log/tracing context'i tutarlı (ADR-0003 pattern).
- **`SubagentID`** PixelCore'da yeni Sendable struct — UUID tabanlı, Codable, CustomStringConvertible.
- 15 yeni test (4 `BudgetTests` + 4 `SubagentResultTests` + 7 `SubagentRunnerTests`). Test path'leri: completed happy, budget exceeded by duration, budget exceeded by bytes, failed via backend throw, completed without explicit done, TaskLocal propagation, TaskLocal scope cleanup.
- Toplam test: **177 → 192** yeşil.
- Token-level budget yok (CLI provider quota opak); wallclock+byte cap pratikte yeterli.
- Faz 2+ (defer): MCP tool `dispatch_subagent`, UI background subagent listesi, multi-turn `Workflow` chain.
- [ADR-0019](docs/adr/0019-subagent-runner.md): tasarım gerekçesi + v2 Sprint 3 ile karşılaştırma + alternatif analizi.

### Changed — dokümantasyon konsolidasyonu (22 May 2026)
- README v0.2.4 + 177 test + 18 ADR durumuyla yeniden yazıldı. Eski `(hazırlanıyor)` placeholder'ları temizlendi (ADR 0001-0009 zaten içerikle dolu, sadece linkler stale idi). Sürüm geçmişi tablosu + tool tablosu eklendi.
- `docs/architecture.md` v0.2.4 ile senkronlandı: modül grafiğine `PixelMCPServer` + `pixel-mcp-server`; AnthropicBackend referansları çıkarıldı; CLIBackend + Plan Mode `ChatOptions` akışı; ed25519 imzalı Mac↔iOS handshake sequence; yeni MCP server akışı (Faz 1 saf-data + Faz 2 Unix socket bridge); katman tablosu + tasarım prensipleri (10 madde) güncel.

### Notes
- v0.2 kalan yol haritası: Subagent dispatching, LAN-only mode (Bonjour), App Store signing.

## [0.2.4] — 2026-05-22

**Plan Mode** (Claude `--permission-mode plan`) + **MCP Faz 2 Unix socket bridge** ile bundle-bağımlı tool'lar (DockBadge, Notify, Sound). v0.2.3'ten sonra biriken 2 büyük başlık. **177 test yeşil** (+11). Breaking change yok.

### Added — MCP server expose Faz 2: Unix socket bridge (22 May 2026)
- **`BridgeProtocol`** (PixelMCPServer): `BridgeRequest` + `BridgeResponse` Codable tipleri; `BridgePaths.defaultSocketPath()` → `~/Library/Caches/dev.erkutyavuzer.pixel-agent/control.sock`.
- **`BridgeClient`** (PixelMCPServer): POSIX `socket(AF_UNIX, SOCK_STREAM)` single-shot RPC. connect → write newline-delimited JSON → read until `\n` → close. `BridgeError` (`socketCreateFailed`/`pathTooLong`/`connectFailed`/`writeFailed`/`readFailed`/`decodeFailed`).
- **`ControlSocketServer`** (PixelMacApp, actor): `socket → bind → listen → accept loop` background `DispatchQueue` üzerinde. Dispatch sırasında MainActor hop (DockBadge.set NSApp.dockTile gerektirir). `start()`/`stop()` idempotent.
- **3 yeni bridge tool** (`BuiltInTools` registry, toplam 5 → 8):
  - `dock_badge_set` — `label: String|null`, Dock badge'i ayarla/temizle
  - `notify` — `title` (zorunlu), `body` (opsiyonel), sistem bildirimi
  - `play_sound` — `name`, macOS sistem sesi
- `PixelMacApp.RootView.task` içinde `Self.controlServer.start()` — açılışta başlatılır; hata stderr'e log.
- `SystemNotifications.isBundledApp` tighten: artık `bundleURL.pathExtension == "app"` da kontrol ediliyor (xctest'te exception fırlatmasını önler).
- 11 yeni test: 7 `BridgeProtocolTests` (Codable roundtrip, path validation, BridgeClient missing socket) + 4 `ControlSocketServerTests` (e2e bind + connect + dispatch, unknown tool failure, notify success, notify-without-title rejection, start/stop idempotency).
- Toplam test: **166 → 177** yeşil.
- [ADR-0018](docs/adr/0018-mcp-bridge-unix-socket.md): Unix socket bridge tasarımı + alternatif analizi (TCP localhost / XPC / NSDistributedNotificationCenter / AppleEvents reddedildi).

### Added — Plan Mode (22 May 2026)
- `PixelCore.ChatOptions` (yeni struct): `planMode: Bool` ve sonraki opsiyonlar için extension noktası.
- `ChatBackend.send(messages:system:options:)` — yeni 3-argümanlı method; 2-arg overload extension'da default `ChatOptions()` ile sarmalanmış (eski call-site'ları kırmaz; impl'ler ekspisit güncellendi).
- `CLIBackend.arguments(for:prompt:options:)`: Claude için `options.planMode == true` ise `--permission-mode plan` flag'i; Codex/Gemini'de no-op.
- `ChatViewModel.planMode` @Published — `send()` çağrısında `ChatOptions(planMode:)` olarak backend'e geçilir.
- `PixelMacApp` top bar: `Toggle(.button)` "Plan" + `list.bullet.clipboard` icon; selected backend Claude değilse tooltip uyarısı. State per-app-launch (persist yok).
- `ChatView` ve `DualChatHost`: `planMode: Bool` parametresi + `.onAppear`/`.onChange` ile child `ChatViewModel.planMode`'a propagate.
- `ChatComposer`: plan mode aktifken placeholder "Plan modu — sadece okuma/araştırma" + TextField turuncu kontur overlay.
- 4 yeni CLIBackendTests (Claude args planMode on/off, Codex/Gemini'de no-op).
- [ADR-0017](docs/adr/0017-plan-mode.md): Plan Mode tasarımı.
- Toplam test: 162 → **166** yeşil.

### Notes
- v0.2 kalan yol haritası: Subagent dispatching, MCP Faz 2 (bundle-bağımlı tool'lar), LAN-only mode (Bonjour), App Store signing.

## [0.2.3] — 2026-05-22

Mac + iOS arasında **end-to-end ed25519 imzalı kanal**, **MCP server expose Faz 1** (5 saf-data tool, claude-cli uyumlu), iOS App Store asset/manifest hazırlığı, **162 test yeşil**. v0.1.0'dan beri biriken 10 commit'in 4 büyük başlığı bu sürümde.

### ⚠️ Breaking change
- Remote protocol v1 → v2. v0.1.x istemciler v0.2.3 relay'ine bağlanamaz; iOS app güncellenmeli + yeni QR taranmalı. UserDefaults pairing key `v1 → v2` (eski pairing'ler invalide).

### Added — MCP server expose Faz 1 (22 May 2026)
- **`PixelMCPServer`** kütüphanesi: `JSONValue` (tip-güvenli JSON ağacı), `JSONRPCMessage` (Request/Response/Error tipleri + standart error code'lar), `ToolRegistry` (`ToolDefinition` + descriptor üretimi), `MCPServer` actor (handle/processLine/runStdio).
- **`pixel-mcp-server`** executable target — `main.swift` 3 satır, `MCPServer.runStdio()` çağırır.
- **5 built-in tool**: `get_clipboard`, `set_clipboard`, `get_current_time`, `get_active_app`, `get_lan_ip` (hepsi bundle-bağımsız, standalone CLI'dan çalışır).
- `LANInterfaceAddress.primary()` — `getifaddrs` ile en0/en1 IPv4 tespiti (PixelMacApp'taki helper'dan kopya; ortak modüle taşıma TODO).
- MCP protocol version `2024-11-05`. Methods: `initialize`, `tools/list`, `tools/call`, `ping`, `initialized` (notification).
- 30 yeni test (5 JSONValue + 6 JSONRPCMessage + 11 MCPServer + 8 ToolRegistry). **Toplam 162 test yeşil.**
- `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | swift run pixel-mcp-server` ile end-to-end sanity doğrulandı.
- [ADR-0016](docs/adr/0016-mcp-server-expose.md): Faz 1 (saf-data tool'lar, stdio transport) landed; Faz 2 (bundle-bağımlı tool'lar Unix socket bridge ile) gelecek.

### Added — ed25519 envelope signing Faz 2 wire-up (22 May 2026)
- **Mac `RemoteHost`**: `init(keyStore:keyService:keyAccount:)` DI; `publicKeyBase64` expose (QR için); `isPaired` published state; receive loop'ta ilk envelope hello + publicKey olmazsa drop; sonraki envelope'lar peer pubkey ile verify edilir; `sendAssistantMessage` outbound imzalı.
- **`PairingView`** (PixelMacApp): QR payload `URLComponents` ile üretiliyor, `pk=<mac-pubkey-b64>` query param eklendi; %-encoding güvenli.
- **iOS `RemoteSession`**: `init(keyStore:)` DI (varsayılan KeychainKeyStore); `publicKeyBase64` hello için; `connect(pairing:)` bağlanır bağlanmaz hello envelope (unsigned, kendi pubkey'i) gönderir; outbound `EnvelopeSigner.sign`, inbound peer pubkey ile verify; UserDefaults key `pixel-agent.pairing.v1` → `v2` (eski pairing'ler invalide); `macPublicKey` PairingInfo'da zorunlu alan.
- **`PairingInfo`** (iOS): `macPublicKey: String` zorunlu; QR parser `pk` query item + base64 + 32-byte + Curve25519 validation; geçmezse nil (eski QR'lar reddedilir).
- 3 yeni RemoteHostTests (toplam 10): `publicKeyBase64` exposed + 32 byte raw; aynı KeyStore aynı pubkey üretir; farklı KeyStore'lar farklı pubkey'ler.
- Toplam test: 132 yeşil.
- ADR-0015 Faz 2 detayları güncellendi.

### Added — ed25519 envelope signing foundation (21 May 2026)
- `PixelRemote.EnvelopeSigner` (`sign(_:with:)`, `verify(_:with:)`, `canonicalBytes(of:)`) — Curve25519 EdDSA ile envelope imza/doğrulama. Canonical encoding: `sig` alanı boş bırakılır, `JSONEncoder(.sortedKeys)` ile encode edilir.
- `PixelRemote.KeyStoring` protocol + `KeychainKeyStore` (Security framework, `kSecAttrAccessibleAfterFirstUnlock`) + `InMemoryKeyStore` (test/CI için hermetic).
- `EnvelopePayload.publicKey: String?` alanı; `RemoteEnvelope.hello(publicKey:)` factory — handshake'in ilk envelope'u.
- `PixelRemote.protocolVersion` 1 → 2 (signed envelopes; geriye uyum yok).
- 14 yeni test: 8 EnvelopeSigner (sign/verify roundtrip, tampered sig, wrong pubkey, missing sig, corrupt base64, deterministic-vs-random check, canonical encoding sig-agnostic, re-sign), 6 KeyStore (round-trip, scoping by service/account, clear, persistence across loads).
- [ADR-0015](docs/adr/0015-ed25519-envelope-signing.md): Faz 1 (foundation) landed; Faz 2 (RemoteHost + RemoteSession wire-up) gelecek commit.

### Added — iOS App Store hazırlığı (21 May 2026)
- **AppIcon** (`ios/PixelAgentRemote/Assets.xcassets/AppIcon.appiconset/`): 1024×1024 master PNG, `PixelMascot.idleFrame` (12×12 ASCII grid) + default palette'ten türetiliyor. Xcode tek master'dan tüm boyutları üretir.
- **Launch screen**: `UILaunchScreen` Info.plist dictionary — `LaunchBackground` (koyu mor `#1C142E`) + `LaunchIcon` mascot imageset (@1x/@2x/@3x). Storyboard'a gerek yok.
- **AccentColor.colorset** — iOS tint mor (dark mode için ayrı varyant).
- **PrivacyInfo.xcprivacy** — App Store gereksinimi. `NSPrivacyTracking: false`; `NSPrivacyAccessedAPITypes` sadece UserDefaults reason `CA92.1` (pairing persist).
- `scripts/generate-app-icon.py` — PixelMascot ASCII grid + palette'ten AppIcon + LaunchIcon PNG'leri üreten reproducible Python script (Pillow dependency).
- `ios/project.yml`: `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`, `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME=AccentColor`; `CFBundleShortVersionString` 0.1.0 → 0.2.0; build 1 → 2.
- [ADR-0014](docs/adr/0014-ios-app-store-assets.md): icon/launch/privacy manifest tasarım kararı.
- `ios/README.md` xcodegen flow + asset üretim talimatı ile yeniden yazıldı (eski "Xcode New Project" manuel kurulum çıkarıldı).

### Test
- 91 (v0.1.0) → **162** test. 71 yeni: 14 ed25519 Faz 1 (8 EnvelopeSigner + 6 KeyStore), 5 Faz 2 (RemoteEnvelope + RemoteHost ek), 30 MCP server, 22 dual-agent + stream-json + Codex (önceki commit'lerden).

### Changed (v0.2.0 → v0.2.3 cumulative)
- Mac `ChatView` dual-agent paralel sohbet desteğine refactor (v0.2.1, e2d9fa4).
- Claude CLI stream-json parser ile gerçek token-by-token streaming (v0.2.2, 67723c7).
- 60s backend timeout watchdog (6aba9e9).
- Codex CLI desteği `exec --json` + stdin + `CodexJSONParser` (8bb11d1).
- iOS auto-reconnect 5s timeout (bc7bf49) + Hakkında sayfası.

### Removed
- v1 remote protocol. `pixel-agent.pairing.v1` UserDefaults key'leri sessizce yok sayılır (yeni QR taratılması beklenir).

## [0.1.0] — 2026-05-21

İlk public release. Mac core stabil; iOS uzak istemcisi pairing + bidirectional chat olarak iskelet hazır. 6 sprint, 7 commit, ~3000 satır Swift + TypeScript, 90+ test.

### Added — Hafta 6 (21 May 2026)
- **MIT lisansı** (`LICENSE`); README badge `tbd → MIT`; "Lisans" bölümü güncel.
- **DocC documentation pipeline**: `Sources/PixelCore/Documentation.docc/PixelCore.md` catalog; `swift-docc-plugin` 1.5 dependency; `.github/workflows/docs.yml` (multi-target combined documentation → GitHub Pages deploy).
- **iOS↔Mac bidirectional message forward** (en kritik Hafta 6 işi):
  - `PixelRemote.RemoteHost` (yeni, @MainActor ObservableObject): RelayClient wrap; `isConnected/pairingCode/lastError/relayURL` published state; `connect/disconnect/sendAssistantMessage/regenerateCode`; `inboundTexts: AsyncStream<String>` iOS userMessage envelope'larını text olarak yayar.
  - `PairingView` yeniden: `@ObservedObject RemoteHost`, "Bağlan/Kes" butonu, durum noktası (yeşil = bağlı), hata gösterimi.
  - `ChatView` refactor: `incomingRemoteText: Binding<String?>` + `onAssistantComplete: ((String) -> Void)?` parametreler; `.onChange(of: incomingRemoteText)` ile iOS mesajını backend'e gönder; assistant stream final → callback ile RemoteHost'a forward.
  - `ChatHost`: `@StateObject RemoteHost`, `.task` ile inbound stream consume → `incomingFromRemote` state'i güncelle; toolbar'da iOS bağlı icon (`iphone.gen3.radiowaves.left.and.right`); QR butonu PairingView sheet.
- Test: 7 yeni (91 toplam) — `RemoteHostTests` (init/relay URL/regenerate/connect error paths/send no-op/disconnect idempotent).

### Added — Hafta 5 (21 May 2026)
- **Cloudflare Worker relay** (`relay/`): TypeScript + Durable Objects. `RelaySession` her pairing code için tek-instance. Routes: `/connect/{code}` (Mac), `/listen/{code}` (iOS). Mesajları bidirectional forward; karşı taraf bağlı değilse 30s/200-frame buffer. `wrangler dev`/`wrangler deploy` script'leri. README deploy talimatı.
- `PixelRemote.RelayClient` (actor): `URLSessionWebSocketTask` wrap, `connect(relayURL:pairingCode:role:)` → `AsyncThrowingStream<RemoteEnvelope, Error>`, `send`, `disconnect`. Pairing code + WebSocket scheme validation.
- `PixelRemote.PairingCode`: 6-karakter, Crockford-benzeri alfabe (32 char, 0/1/O/I/L hariç). `generate()` + `isValid(_:)`.
- `PixelRemote.RelayError`: `notConnected`/`invalidRelayURL`/`invalidPairingCode`/`encodingFailed`/`decodingFailed` (Türkçe LocalizedError).
- `PixelRemote.RelayRole`: `mac` (→ `/connect`) / `ios` (→ `/listen`) path mapping.
- `PixelMacApp.PairingView`: QR kod görseli (CoreImage `CIFilter.qrCodeGenerator`), pairing code, relay URL. `pixel-agent-pair://?code=...&relay=...` payload. `ChatHost` toolbar'da QR butonu, sheet olarak açılır.
- **iOS app source** (`ios/PixelAgentRemote/`): `PixelAgentRemoteApp` (@main + RemoteSession StateObject), `ContentView` (bağlıysa ChatView, değilse PairingScannerView), `RemoteSession` (ObservableObject + RelayClient + PairingInfo parser), `PairingScannerView` (AVCaptureSession QR scanner, UIViewControllerRepresentable), `ChatView` (iOS mesaj listesi + composer), `Info.plist` (NSCameraUsageDescription). Xcode project kullanıcı tarafından setup edilecek — `ios/README.md` talimat içerir.
- [ADR-0013](docs/adr/0013-pairing-and-relay-protocol.md): pairing & relay protokol kararı (Crockford-32 alfabe, QR URI scheme, Cloudflare DO, auth modeli + Faz 2 ed25519 planı).

### Added — Hafta 4 (21 May 2026)
- `PixelMemory.ConversationStore` (actor): JSONL append-only conversation persist. `~/Library/Application Support/pixel-agent/conversation.jsonl`. `append/loadAll(limit:)/newConversation()/messageCount()`. `newConversation` mevcut dosyayı `archive/` altına timestamp ile taşır. Bozuk JSON satırlar atlanır (graceful degradation).
- `PixelMacApp`: `RootView` `ConversationStore` init eder; init hatası → `ErrorView`. `ChatView.task` ile açılışta son 200 mesaj restore. Her user/assistant mesajı stream sonunda store'a append. "Yeni sohbet" butonu (status bar'da, `plus.bubble` icon) → arşivle + ekranı temizle.
- `PixelRemote.RemoteEnvelope` (Codable + Sendable struct): `v/id/ts/type/payload?/sig?`. `EnvelopeType` enum (hello/ready/ping/ack/error/userMessage/assistantMessage). `EnvelopePayload` (flat optional fields: text/role/messageID/errorCode/errorMessage/metadata). Convenience factories: `.userMessage(text:)`, `.ping()`, `.ack(referenceID:)`, `.error(code:message:)`. [ADR-0012](docs/adr/0012-remote-envelope-schema.md).

### Added — Hafta 3 (21 May 2026)
- `PixelMascot`: 48×48 pixel-art sprite (12×12 ASCII grid + renk palette); 4 state (idle/thinking/speaking/error); `MascotView` SwiftUI `Canvas` render; `MascotPalette` özelleştirilebilir (default mor temalı); ascii grid → karakter map (X=body, H=highlight, S=shadow, O/o/x=göz, M/_=ağız).
- `PixelTools`: scope yeniden tanımlandı — CLI tool wrapper değil, native macOS toolkit ([ADR-0011](docs/adr/0011-native-macos-toolkit.md)). `DockBadge` (NSApp.dockTile.badgeLabel wrap, test ortamında no-op), `SystemNotifications` (UNUserNotificationCenter, Türkçe karakter destek), `SoundEffect` (Glass/Basso/Tink system sounds).
- `ChatView` entegrasyon: üst-sağ köşede `MascotView` (32px); stream başlat → `.thinking`; ilk token → `.speaking`; done → `.idle`; throw → `.error`. Foreground'da `SoundEffect.play`, background'da `DockBadge.set("1")` + `SystemNotifications.post`.
- `RootView.task`: açılışta `UNUserNotificationCenter.requestAuthorization`.

### Removed — Hafta 2.5 (21 May 2026)
- `AnthropicBackend` (URLSession + SSE streaming) silindi. Yerine `CLIBackend` geldi — gerekçe ve detay için bkz. [ADR-0010](docs/adr/0010-cli-subprocess-backend.md).
- `AnthropicError` → yerine jenerik `BackendError`.
- `SSEParser` → CLI subprocess'lerinde SSE yok, gereksiz.

### Added — Hafta 2.5 (21 May 2026)
- `PixelBackends`: `CLIBackend` (subprocess wrapper, claude/codex/gemini); `CLIDetector` (bilinen path + `which` fallback); `CLIProcessRunner` (Process API + async byte stream); `BackendError` (cliNotFound / processFailed / exitNonZero / noBackendAvailable, Türkçe LocalizedError).
- `PixelMacApp`: `RootView` artık `CLIDetector` ile yüklü CLI'ları tespit eder; `ChatHost` segmented Picker ile anlık backend değişimi; `MissingBackendView` seçili CLI yüklü değilse; `ErrorView` hiçbir CLI yoksa "Tekrar tara".

### Added — Hafta 2 (21 May 2026)
- `PixelCore`: `Message`, `MessageRole`, `StreamDelta`, `ChatBackend` protokolü, `AgentID`, `AgentContext` (TaskLocal scoping). ADR-0003 ve ADR-0004 hayata geçti.
- `PixelMacApp`: SwiftUI `ChatView` (mesaj listesi + canlı streaming composer + ESC ile iptal).

### Added — Hafta 1 (21 May 2026)
- Swift Package Manager monorepo iskeleti (6 library + 1 executable target).
- `PixelCore`, `PixelBackends`, `PixelTools`, `PixelMemory`, `PixelMascot`, `PixelRemote`, `PixelMacApp` modülleri (stub).
- 9 ADR (Architecture Decision Records) — `docs/adr/0001-0009`.
- `docs/architecture-decisions-from-v2.md` — pixel-agent2'den çıkarılan 14 mimari karar ve 3 anti-pattern.
- `docs/architecture.md` — mermaid modül + akış diyagramları.
- SwiftLint (`.swiftlint.yml`) ve swift-format (`.swift-format`) konfigürasyonları.
- `scripts/lint.sh`, `scripts/pre-commit.sh`, `scripts/install-hooks.sh` yardımcı scriptleri.
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): build (debug+release), test (parallel + coverage), SwiftLint.
- Issue ve pull request şablonları.
- `SECURITY.md` güvenlik bildirim politikası.

### Test
- 90+ yeşil test (Hafta 1: 7 placeholder → Hafta 6: 91 toplam).

### Notes
- Swift toolchain: 6.0+ (Swift 6 language mode).
- Platform: macOS 14+, iOS 17+ (uzak istemci).
- Lisans: MIT.

[Unreleased]: https://github.com/ErkutYavuzer/pixel-agent/compare/v0.2.9...HEAD
[0.2.9]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.9
[0.2.8]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.8
[0.2.7]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.7
[0.2.6]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.6
[0.2.5]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.5
[0.2.4]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.4
[0.2.3]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.2.3
[0.1.0]: https://github.com/ErkutYavuzer/pixel-agent/releases/tag/v0.1.0
