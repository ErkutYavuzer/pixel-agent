# Polish Roadmap — "Demo-Ready" Milestone

> **Mission.** Mac + iOS pixel-agent'ı sürekli daha yetenekli ve "demo-ready" hale getir. Marketing katmanı (README/landing/brew tap/OG image) Faz A'da kuruldu — şu an ürün polish'i öne çıkıyor. Hedef sabit: **her oturum projeyi bir derece daha satılabilir + bir derece daha kullanışlı yapmak**.
>
> **Why this document.** "Binlerce yıldız" iddiası ile mevcut demo-readiness seviyesi arasındaki gap'i objektif tut. Plan agent'ın 23 May 2026'da yaptığı source-level audit (39 spesifik gap) burada listelenir; her item ROI'lendirilmiş, sprint atanmış, durum izlenir.

## Demo-Readiness tanımı

pixel-agent **demo-ready** sayılır eğer:

1. Yeni bir kullanıcı uygulamayı kurduğunda **empty state'te ne yapacağını biliyor** (sample prompt chip'leri).
2. Streaming sırasında **typing indicator** ve markdown render var (kod blokları + copy button).
3. **Plan Mode aktif iken hangi tool'lar bloklandı** kullanıcıya görsel olarak belli.
4. **Keyboard shortcuts** çalışıyor (⌘N yeni sohbet, mod geçiş, vs.).
5. **Subagent dispatch sonucu** ana chat akışına entegre (sadece panel kartında kalmıyor).
6. **iOS dashboard'dan yapılan değişiklikler** Mac'te toast/banner ile feedback veriyor.
7. **CLI auth hatası** durumunda actionable retry/login butonu çıkıyor.
8. **MCP entegrasyon helper** (Claude Code / Cursor / Codex için JSON snippet + bin path + copy button) içinde.
9. **Hata durumlarında** "Tekrar dene" butonu (sessiz fail yok).
10. **Pairing status** günlük kullanımda görünür (sadece sheet açıkken değil).

Bu 10 madde **Sprint 1**'in kapsamı. Tamamlandığında "demo-ready" milestone'u açılır.

## Gap Kategorileri (Plan agent audit, 23 May 2026)

39 madde, 3 kategori. Her madde için dosya referansı, mevcut durum, hedef hal Plan agent çıktısında — özet aşağıda.

### A. UX/Görsel Polish (13 madde)
Markdown rendering, typing indicator, empty state, mascot polish, focus halos, error retry, asymmetric bubble, toolbar gruplama, scroll spring, reconnect countdown — feature çalışıyor ama "hızlı prototip" hissi veriyor.

### B. Eksik Temel Feature (14 madde)
Settings scene yok, conversation history sidebar/search/export yok, drag-drop file context yok, keyboard shortcuts (.commands) yok, per-message actions (copy/regenerate/edit) yok, iOS settings tab yok, MCP setup UI yok, conversation rename/tag yok, paired-devices yönetimi yok.

### C. End-to-End Workflow (12 madde)
Subagent → chat entegrasyonu yok, screenshot chat'e düşmüyor, Set-of-Mark numbered overlay UI'da görünmüyor, Plan Mode tool list panel yok, iOS→Mac config-change toast yok, connection-lost pulse yok, daimi pairing pill yok, MCP entegrasyon helper yok, actionable auth error yok, subagent cap reached transient banner yok, screenshot → "soruna sor" akışı yok, tool-call event'leri envelope'ta yok.

## ROI Tablosu (top-16)

ROI = (Impact × Demo visibility) / Effort. Effort: S=1, M=2, L=3.

| # | Item | Effort | Impact (1-5) | Demo (1-5) | ROI | Sprint |
|---|---|---|---|---|---|---|
| **C8** | MCP entegrasyon helper (JSON + bin + copy) | S | 4 | 5 | **20** | S1 |
| **C4** | Plan Mode tool list panel | S | 4 | 4 | **16** | S1 |
| **A3** | Empty state + sample prompt chips | S | 3 | 5 | **15** | S1 |
| **A1** | Markdown rendering + code block copy | M | 5 | 5 | **12.5** | S1 |
| **B5** | Keyboard shortcuts (.commands) | S | 3 | 4 | **12** | S1 |
| **A2** | Typing indicator (3-dot pulse) | S | 3 | 4 | **12** | S1 |
| **C5** | iOS→Mac config-change toast | S | 3 | 4 | **12** | S1 |
| **A7** | Inline retry banner on error | S | 4 | 3 | **12** | S1 |
| **C9** | Actionable auth error (login deep-link) | S | 4 | 3 | **12** | S1 |
| **C1** | Subagent sonucu chat'e akıt | M | 5 | 4 | **10** | S1 |
| **C7** | Daimi connection pill | S | 3 | 3 | **9** | S2 |
| **B6** | Quick-actions menu (copy last) | S | 3 | 3 | **9** | S2 |
| **B3** | Conversation export (markdown/JSON) | S | 3 | 3 | **9** | S2 |
| **A8** | Composer focus halo + haptic | S | 2 | 4 | **8** | S2 |
| **C10** | Subagent cap-reached banner | S | 2 | 3 | **6** | S2 |
| **C2/C3** | Screenshot in-chat + SoM overlay UI | L | 4 | 5 | **6.7** | S2 |
| **B2** | Conversation history sidebar | L | 5 | 4 | **6.7** | S3 |
| **C12** | Tool-call envelope events (iOS) | M | 3 | 4 | **6** | S3 |
| **B1** | Settings scene (tab'lı) | L | 4 | 3 | **4** | S3 |
| **B8** | iOS settings tab | M | 3 | 3 | **4.5** | S3 |

## Sprint 1 — "Demo-Ready Foundation" (1-2 hafta, 10 item)

| Status | # | Item |
|---|---|---|
| ✅ | C8 | MCP entegrasyon helper |
| ✅ | C4 | Plan Mode tool list panel |
| ✅ | A3 | Empty state + sample prompts |
| ✅ | A1 | Markdown + code block copy |
| ✅ | B5 | Keyboard shortcuts |
| ✅ | A2 | Typing indicator |
| ✅ | C5 | iOS→Mac config toast |
| ✅ | A7 | Inline retry banner |
| ✅ | C9 | Actionable auth error |
| ✅ | C1 | Subagent → chat akışı |

Bitince **demo-ready milestone açılır** + demo GIF kaydı + Show HN hazırlığı başlar.

**24 May 2026: Sprint 1 tamamlandı — demo-ready milestone AÇILDI.** Tüm 10 item landed (commits 9d6a313, 5dc72f5, d2f8bbe, 27d7f7f, b9d38a7, 6ee0309, f59b5b8, cf9c86a, 8d5d91e, ve C1'in commit'i). Test sayısı: 443 → 529 (+86). PixelAgent.app rebuild edildi. Sonraki adım: v0.2.26 release tag + demo GIF kaydı + DMG (notarized signing varsa) + Show HN hazırlığı.

## Sprint 2 — "Power-User Touches" (Sprint 1 sonrası)

C7, B6, B3, A8, C10, C2/C3 + sprint 1 follow-up'lar.

| Status | # | Item |
|---|---|---|
| ✅ | C7 | Daimi connection pill |
| ✅ | B6 | Quick-actions menu (copy last) |
| ✅ | B3 | Conversation export (markdown/JSON) |
| ✅ | A8 | Composer focus halo + haptic |
| ✅ | C10 | Subagent cap-reached banner |
| ✅ | C2/C3 | Screenshot in-chat + SoM overlay UI |

**24 May 2026: Sprint 2 tamamlandı — Power-User Touches paketi.** 6 commit (c876e1e, 23317d7, e161fbc, 2d720d8, df96f3e, ve C2/C3 commit'i). Test sayısı: 529 → 574 (+45). PixelAgent.app rebuild edildi. Sonraki adım: v0.2.27 release tag (Sprint 2 bundle) + demo GIF kaydı + Sprint 3 (B2, B1, B8, C12).

## Sprint 3 — "Persistent State + iOS Parity" (Sprint 2 sonrası)

B2 (conversation history sidebar — büyük), B1 (Settings scene), B8 (iOS settings tab), C12 (tool-call envelope events).

| Status | # | Item |
|---|---|---|
| ✅ | B2 | Conversation history sidebar |
| ✅ | B1 | Settings scene (tab'lı) |
| ✅ | B8 | iOS settings tab |
| ✅ | C12 | Tool-call envelope events |

**24 May 2026: Sprint 3 tamamlandı — Persistent State + iOS Parity paketi.** 4 commit (7f6665a, 102332a, 0350b12, ve C12 commit'i). Test sayısı: 574 → 606 (+32). PixelAgent.app + iOS BUILD SUCCEEDED. Sonraki adım: v0.2.28 release tag (Sprint 3 bundle).

## Sprint 4 — "Persistence Follow-up" (v0.2.29)

| Status | # | Item |
|---|---|---|
| ✅ | C2/C3 follow-up | Screenshot disk persistence |
| ✅ | B2 follow-up | "Bu sohbete devam et" archive load |
| ✅ | C7 follow-up | Connection-lost pulse animation (Mac) |
| ✅ | C11 | Screenshot → composer prefill prompt |
| ✅ | forward-compat | `EnvelopeType.unknown` sentinel |

**v0.2.29 release** (commit `6d49cbc`) — Sprint 4 paketlemesi.

## Sprint 5 — "Cross-Platform Parity" (v0.2.30)

| Status | # | Item |
|---|---|---|
| ✅ | C7 parity | iOS connection-lost pulse |
| ✅ | A-polish | Mascot subtle animations |
| ✅ | Composer | Drag-drop file context |
| ✅ | B2 parity | iOS conversation history viewer |

**v0.2.30 release** (commit `df4592c`) — 4 atomic item, Mac↔iOS UX simetrisi. Test: 631 → 675 (+44).

## Sprint 6 — "Persistence + Polish" (v0.2.31)

| Status | # | Item |
|---|---|---|
| ✅ | C2/C3 follow-up | SoM marks JSONL sidecar persistence |
| ✅ | new | iOS → Mac archive load handler |
| ✅ | B kategorisi | MCP setup wizard (auto config edit) |
| ✅ | B2 power | Conversation rename (sidecar, contextMenu, sheet) |

**25 May 2026: Sprint 6 tamamlandı — Persistence + Polish paketi.** 4 commit (69bb2f6, a976c20, b0a0482, ve v0.2.31 release commit'i). Test: 698 → 718 (+20). Sprint 6 "tag/etiketleme" ayağı Sprint 7'ye taşındı (rename scope odağı korundu).

## Sprint 7 — "Conversation tag" (v0.2.32)

| Status | # | Item |
|---|---|---|
| ✅ | B2 power | ArchiveTagsStore sidecar (`tags.json` flat dict) |
| ✅ | B2 power | TagNormalizer + TagFilter saf helper'lar |
| ✅ | B2 power | EditTagsSheet (chip'ler + TextField + Enter Add) |
| ✅ | B2 power | Sidebar filter chip bar (multi-select OR/union) |
| ✅ | B2 power | Row inline tag preview (`#x #y #z +N`) + contextMenu |
| ✅ | wire | `ArchiveEntryPayload.tags` opsiyonel (iOS read-only) |

**25 May 2026: Sprint 7 tamamlandı — Conversation tag.** v0.2.31'in (rename) eşi: 27 yeni test (+8 ArchiveTagsStore + 9 TagNormalizer + 6 TagFilter + 4 ConversationStore). Test: 718 → 745. iOS UI'da tag görünümü v0.2.34'e ertelendi (şu an wire-only data layer). Apple Developer ID + notarization + demo GIF hâlâ kullanıcı aksiyonu olarak bekliyor.

## Sprint 8 — "EnvelopePayload sum-type refactor" (v0.2.33)

| Status | # | Item |
|---|---|---|
| ✅ | v0.3 hazırlığı | EnvelopePayload struct → enum (15 case, EnvelopeType ile 1:1) |
| ✅ | yapısal | HostStatusContent sub-struct (7 field aggregator) |
| ✅ | wire-compat | RemoteEnvelope custom Codable (type-aware decode) |
| ✅ | backward-compat | 20 computed getter (eski caller'lar migrate olmadan çalışır) |
| ✅ | cleanup | Dead `metadata` field silindi + manual Equatable kaldırıldı (auto-synth) |

**25 May 2026: Sprint 8 tamamlandı — EnvelopePayload sum-type.** v0.2.32'ye kadar 20 opsiyonel field'lı flat struct'tı; şimdi 15 case'lı sum type, derleyici hangi case'in hangi data taşıdığını biliyor. Wire format değişmedi (eski sürümler uyumlu). 15 yeni test (+15 EnvelopePayloadSumTypeTests). Caller migration zorunlu değil.

## Sprint 9 — "iOS tag chip UI" (v0.2.34)

| Status | # | Item |
|---|---|---|
| ✅ | iOS parity | IOSArchiveTitleResolver saf helper (Mac paraleli) |
| ✅ | iOS row | customTitle fallback + rename rozet (pencil.circle.fill) |
| ✅ | iOS row | Tag inline preview `#x #y #z +N` |
| ✅ | iOS detail | Navigation title = display title, tag chip ScrollView |

**25 May 2026: Sprint 9 tamamlandı — iOS visual parity.** v0.2.31 rename + v0.2.32 tag wire field'ları artık iOS UI'da görünür. **Read-only** — iOS'tan düzenleme Sprint 10'da iniş yaptı.

## Sprint 10 — "iOS rename/tag dispatch" (v0.2.35)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | `archiveRename` + `archiveSetTags` EnvelopeType + sum case |
| ✅ | mac handler | 2 callback + otomatik archiveListResponse refresh |
| ✅ | mac wire | TagNormalizer defense in depth + ConversationStore mutation |
| ✅ | iOS API | RemoteSession.renameArchive/setArchiveTags async metodlar |
| ✅ | iOS UI | EditArchiveSheet (Başlık + Etiketler editor) + Düzenle toolbar buton |
| ✅ | iOS reaktif | liveEntry session.archiveEntries'ten güncel hali çeker |

**25 May 2026: Sprint 10 tamamlandı — iOS mutation dispatch.** v0.2.34 read-only görünümün üzerine düzenleme açıldı. iOS edit sheet → Mac handler → ConversationStore → otomatik archiveListResponse round-trip. Yeni envelope case'leri sum-type refactor (Sprint 8) sayesinde tip güvenli eklendi. PixelRemoteTests 100 → 122. iOS xcodebuild simulator BUILD SUCCEEDED. Mac + iOS feature parity tam.

## Sprint 11 — "A items polish" (v0.2.36)

| Status | # | Item |
|---|---|---|
| ✅ | A — Mac UX | Scroll spring (default linear → spring 0.35/0.85) |
| ✅ | A — Mac UX | Asymmetric chat bubble (user sağ mavi / assistant sol mor / system ortada gri) |
| ✅ | A — iOS UX | Reconnect countdown banner ("X sn sonra tekrar deneme…") |
| ✅ | testable helpers | BubbleStyle (saf, +9 test) + ReconnectCountdownFormatter (saf, iOS) |

**25 May 2026: Sprint 11 tamamlandı — A items polish.** Polish-roadmap'in A kategorisinde "feature çalışıyor ama hızlı prototip hissi" şikayetlerine 3 cevap. Mac chat görünümü modern asymmetric bubble pattern'ine geçti (badge prefix kaldırıldı, alignment + renk yeterli). iOS reconnect feedback'i TimelineView ile her saniye güncellenir countdown'a kavuştu. Mac test 745 → 754. iOS xcodebuild simulator BUILD SUCCEEDED.

## Sprint 12 — "iOS bubble parity + archive delete + flake debug" (v0.2.37)

| Status | # | Item |
|---|---|---|
| ✅ | iOS refactor | IOSBubbleStyle saf helper (Mac BubbleStyle paraleli) |
| ✅ | yeni feature | archiveDelete envelope + ConversationStore.deleteArchive static |
| ✅ | iOS UI | Swipe-to-delete + confirmation dialog |
| ✅ | docs | Pre-existing test flake root cause analysis (CHANGELOG'da) |
| ⏸ | v0.3+ | Test isolation refactor (flake'ı yapısal çöz) |

**25 May 2026: Sprint 12 tamamlandı — bundle.** Üç paralel iş tek release'de. iOS chat row Mac ile cross-platform tutarlı (görsel değişiklik yok, sadece refactor); arşiv silme tam round-trip (iOS swipe → Mac delete → otomatik refresh); flake için root cause kayıt altına alındı (parallel mode'da deterministik PixelLAN SIGSEGV, default mode'da nadir random SIGBUS — test isolation refactor v0.3+ adayı). Mac test 754 → 762 (+8). iOS xcodebuild simulator BUILD SUCCEEDED.

## Sprint 13 — "PixelComputerUse Faz 5" (v0.2.38)

| Status | # | Item |
|---|---|---|
| ✅ | SoM Tier 2 | SoMOptions saf struct (palette/outline/badge/font/textColor/placement) |
| ✅ | SoM Tier 2 | BadgeLayout saf helper (4 köşe + smartCorner + bounds clamping) |
| ✅ | renderer | SoMRenderer.annotate(options:) parametrize |
| ✅ | auto-discover | AXRole.interactiveRoles set + AXBridge.discoverInteractive BFS |
| ✅ | API | PixelComputerUse.screenshot(autoDiscover:options:) genişletme |
| ✅ | MCP wire | ui_screenshot şeması auto_discover + som_options |

**25 May 2026: Sprint 13 tamamlandı — PixelComputerUse Faz 5.** v0.2.31 Faz 4'ün üç eksiği kapatıldı: palette/badge override, AX-based otomatik element keşfi, content-aware badge placement. Vision model artık `ui_screenshot(auto_discover: true)` tek çağrıyla "ne tıklanabilir?" özetini alabilir; SoM stil tasarımı caller-side configurable. Mac test 762 → 783 (+21: 11 SoMOptions + 10 BadgeLayout). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (geri uyumlu default davranış).

## Sprint 14 — "Subagent Faz 4 (multi-turn + settings UI)" (v0.2.39)

| Status | # | Item |
|---|---|---|
| ✅ | runner | MultiTurnSubagentRunner actor (N turn sequential + shared budget + history) |
| ✅ | result | TurnResult + MultiTurnSubagentResult enum (4 case getter'lar) |
| ✅ | settings | SubagentSettings struct + SubagentSettingsStore UserDefaults persistence |
| ✅ | UI | Mac Settings "Subagent" sekmesi (5. tab, budget/backend/reset Form) |
| ✅ | MCP wire | dispatch_subagent follow_ups param + multiTurnBridgeResponse |
| ⏸ | v0.3+ | UI panel'de multi-turn turn list görselleştirme (Manager bypass mevcut path) |

**25 May 2026: Sprint 14 tamamlandı — Subagent Faz 4.** v0.2.7 one-shot subagent multi-turn workflow + kullanıcı yapılandırılabilir bütçe ile genişletildi. Vision model artık `dispatch_subagent --follow-ups '["t1", "t2"]'` ile sıralı turn dispatch edebilir; her turn full history ile backend'e gider, shared budget tüm turn'lere uygulanır. Mac Settings'te yeni "Subagent" sekmesi (5/5 — Genel/Modeller/Bağlantı/Subagent/İzinler). Mac test 783 → 797 (+14: 6 MultiTurnRunner + 8 SubagentSettings). iOS xcodebuild simulator BUILD SUCCEEDED.

## Sprint 15 — "iOS continuous screenshot stream" (v0.2.40)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | screenshotStreamStart + screenshotStreamStop EnvelopeType + sum case |
| ✅ | mac coordinator | ScreenshotStreamCoordinator @MainActor ObservableObject (task management) |
| ✅ | mac handler | RemoteHost 2 callback + ChatHost wire (host snapshot let, Swift 6 uyumu) |
| ✅ | iOS API | RemoteSession start/stopScreenshotStream async + isStreamingScreenshots |
| ✅ | iOS UI | Mac Paneli "Canlı/Durdur" toggle (yeşil/kırmızı capsule, tek-shot disabled stream aktifken) |
| ⏸ | v0.2.41+ | Cancellation upstream (disconnect → coordinator.stop, şu an ~1 interval gecikme) |
| ⏸ | v0.2.41+ | Adaptive rate (interval auto-tune CPU/bandwidth) |

**25 May 2026: Sprint 15 tamamlandı — iOS continuous screenshot streaming.** v0.2.25 release notlarındaki eksik kapatıldı: iOS Mac Paneli'nde "Canlı" toggle ile Mac her 1s'de screenshot push'lar (250-5000 ms clamp). Tek-shot mode hâlâ çalışır. Mac test 797 → 802 (+5). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 16 — "Subagent Faz 5 UI panel multi-turn turn list" (v0.2.41)

| Status | # | Item |
|---|---|---|
| ✅ | data | SubagentSession.multiTurnTurns: [TurnResult]? field |
| ✅ | manager | SubagentManager.dispatchMultiTurnAndWait + finalizeMultiTurn + combinedOutput helper |
| ✅ | wire | ControlSocketServer.dispatchMultiTurn: manager attached path |
| ✅ | UI | SubagentDetailSheet turn list expansion (per-turn outcome badge + duration + output) |
| ⏸ | v0.2.42+ | Per-turn live streaming (chunk akışı UI'da, finalize öncesi) |

**25 May 2026: Sprint 16 tamamlandı — Subagent Faz 5.** v0.2.39 multi-turn runner UI panel'inde görünür hale geldi. Manager attached path açıldı: dispatch_subagent --follow-ups artık UI'da tek session kartı + detail sheet per-turn expandable list (outcome badge + duration + output) gösterir. Mac test 802 → 811 (+9 SubagentMultiTurnManagerTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 17 — "Stream cancellation upstream" (v0.2.42)

| Status | # | Item |
|---|---|---|
| ✅ | upstream fix | ChatHost .onChange(of: remoteHost.isConnected) → screenshotStream.stop |
| ✅ | tests | ScreenshotStreamCoordinatorTests (start/stop/clamping/idempotency) |
| ⏸ | v0.2.43+ | Stream rate adaptive (interval auto-tune Mac CPU/bandwidth) |

**25 May 2026: Sprint 17 tamamlandı — Stream cancellation upstream.** v0.2.40 continuous screenshot stream'in bilinen kısıtı (~1 interval gecikmeli stop) düzeltildi: ChatHost.onChange(of: remoteHost.isConnected) disconnect anında screenshotStream.stop() çağırır → immediate cancel. Mac test 811 → 820 (+9 ScreenshotStreamCoordinatorTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 18 — "Per-turn live streaming" (v0.2.43)

| Status | # | Item |
|---|---|---|
| ✅ | runner | MultiTurnSubagentEvent enum (turnStarted/chunk/turnFinished/allFinished) |
| ✅ | runner | runConversationStreaming AsyncStream + runConversationInternal helper |
| ✅ | session | activeTurnIndex + activeTurnPartial fields |
| ✅ | manager | dispatchMultiTurnAndWait streaming consume + beginTurn/appendTurnChunk/completeTurn |
| ✅ | UI | SubagentDetailSheet @ObservedObject manager + activeTurnRow (mavi spinner + dashed border + monospaced live partial) |

**25 May 2026: Sprint 18 tamamlandı — Per-turn live streaming.** v0.2.41 batch render → live chunk akışı: aktif turn'ün çıktısı real-time görünür (in-progress mavi kart, her chunk re-render). Sheet @ObservedObject manager ile live update kontratı. Mac test 820 → 825 (+5 MultiTurnSubagentStreamingTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 19 — "hostStatus delta-only push" (v0.2.44)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | hostStatusDelta envelope + HostStatusDeltaContent (tüm opsiyonel) |
| ✅ | saf helper | HostStatusDeltaCalculator (last vs new → delta, isEmpty skip) |
| ✅ | Mac | sendHostStatusDelta API + periyodik push diff-based |
| ✅ | iOS | combined switch arm (handler zaten delta-aware field-by-field merge) |
| ✅ | bandwidth | idle ~700 B/s → 0; partial change ~50-300 B/s |

**25 May 2026: Sprint 19 tamamlandı — hostStatus delta-only push.** v0.2.25 release notlarındaki son açık follow-up kapatıldı. Mac 3sn periyodik push şimdi diff-based: idle 0 push, sadece değişen field'lar gönderiliyor. iOS handler reuse (zaten delta-aware). Mac test 825 → 837 (+12 HostStatusDeltaCalculatorTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 20 — "AX label-aware badge placement" (v0.2.45)

| Status | # | Item |
|---|---|---|
| ✅ | enum | BadgePlacement.labelAware yeni case |
| ✅ | saf helper | LabelAwarePlacementResolver (role → BadgePlacement mapping) |
| ✅ | renderer | SoMRenderer per-element resolve labelAware'da |
| ✅ | MCP | ui_screenshot.som_options schema label_aware enum |
| ⏸ | v0.2.46+ | OCR-based (Vision framework text bbox detection) |

**25 May 2026: Sprint 20 tamamlandı — AX label-aware badge placement.** v0.2.38 BadgeLayout geometry-aware idi ama element içerik anlamı yoktu. AX role-based heuristic eklendi: button → topRightOutside (text merkez), link → topRightInside (text sol kenar), checkbox/radio → topRightOutside (simge sol + label sağ). Mac test 837 → 849 (+12 LabelAwarePlacementResolverTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 21 — "Adaptive stream rate" (v0.2.46)

| Status | # | Item |
|---|---|---|
| ✅ | saf helper | AdaptiveRateController.nextInterval (slow lane 1.5x, fast lane 0.8x, hysteresis) |
| ✅ | coordinator | baseIntervalMs (kullanıcı taban) + currentIntervalMs (dinamik) + lastSendLatencyMs |
| ✅ | loop | Per-tick latency ölçümü + controller call + state update |
| ✅ | v0.2.47 | Wire-level latency (Sprint 22 ile iniş — iOS ACK round-trip) |

**25 May 2026: Sprint 21 tamamlandı — Adaptive stream rate.** v0.2.40 continuous screenshot stream sabit interval'den **latency-aware** adaptive'e geçti. Slow network → 1.5x backoff (max 5000ms); rahat network → 0.8x speedup baseMs alt sınıra kadar; hysteresis zone osilasyon engeller. Mac test 849 → 859 (+10 AdaptiveRateControllerTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 22 — "Wire-level latency" (v0.2.47)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | `EnvelopeType.screenshotFrameAck` + `screenshotPayload.frameID: String?` (additive, eski iOS sürümleri görmez) |
| ✅ | saf helper | `WireLatencyState` + `WireLatencyTracker` (record/consumeAck/prune/effectiveLatencyMs) |
| ✅ | coordinator | Her tick UUID frameID, wireState pending map, `recordAck` callback, `effectiveLatencyMs` adaptive controller'a |
| ✅ | host wire | `RemoteHost.onScreenshotFrameAckReceived` callback + inbound switch + `sendScreenshot(frameID:)` optional param |
| ✅ | iOS wire | RemoteSession: screenshotPayload alındığında frameID varsa `sendScreenshotFrameAck` (best-effort, sessizce yutar) |
| ⏸ | v0.2.48+ | UI'da wire latency badge (`lastWireLatencyMs` Mac Paneli'nde "Ağ: 87 ms") |

**25 May 2026: Sprint 22 tamamlandı — Wire-level latency.** v0.2.46 adaptive rate `lastSendLatencyMs`'i **local** ölçüyordu (capture + JPEG + transport handoff) — backpressure'a duyarlı ama ağ koşulundan habersiz. Sprint 22 Mac her frame'e UUID frameID iliştiriyor, iOS aynı ID ile `screenshotFrameAck` döner; coordinator round-trip ms = wire latency. Adaptive controller artık gerçek ağ latency'sine göre scale ediyor. Henüz ACK yokken (stream başlangıcı, eski iOS) `WireLatencyTracker.effectiveLatencyMs` 5 sn freshness window dışında **local fallback**'e düşer — graceful degradation. Mac test 859 → 871 (+12 net: 16 WireLatencyTracker + 3 Coordinator + 5 EnvelopePayload + 1 RemoteEnvelope regression set + 1 SettingsTab v0.2.39 pre-existing fix; bazıları aynı modülde duplicate-counted). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (`screenshotPayload` factory default `frameID: nil` ile eski callsites unchanged).

## Sprint 23 — "Wire latency badge UI" (v0.2.48)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | `HostStatusContent.screenshotWireLatencyMs: Int?` + `HostStatusDeltaContent.screenshotWireLatencyMs: Int?` (additive, encodeIfPresent) |
| ✅ | delta calc | `HostStatusDeltaCalculator.delta` field-by-field diff'e wireLatency dahil; bootstrap (from nil) için new'den kopyalanır |
| ✅ | Mac push | Periyodik 3 sn loop'ta `coordinator.isActive ? coordinator.lastWireLatencyMs : nil` snapshot'a |
| ✅ | iOS merge | RemoteSession `@Published screenshotWireLatencyMs`; hostStatus/Delta merge handler; stopScreenshotStream reset |
| ✅ | iOS UI | Mac Paneli "Ekran Resmi" badge: `isStreamingScreenshots && latency != nil` gate; renk bantları (<100 yeşil / <300 turuncu / ≥300 kırmızı); monospaced "Ağ: X ms" + wifi icon |
| ⏸ | v0.2.49+ | Per-frame latency embed (`screenshotPayload.wireLatencyMs`) — 3 sn lag yerine 1Hz real-time güncelleme |

**25 May 2026: Sprint 23 tamamlandı — Wire latency badge UI.** Sprint 22 Mac side wire latency'i ölçüyordu ama iOS user'a görsel feedback yoktu. Sprint 23 protocol additive (hostStatus + hostStatusDelta `screenshotWireLatencyMs: Int?`) + Mac periyodik push + iOS Mac Paneli renk-bantlı rozet. 3 saniyelik delta loop'a piggyback — debug-tier feedback için yeterli, gerçek-zamanlı değil. Mac test 871 → 880 (+9 HostStatusDeltaCalculator: change/unchanged/value→nil edge case, full bootstrap, host envelope round-trip, isEmpty truth table, getter passthrough). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 24 — "Per-frame wire latency embed" (v0.2.49)

| Status | # | Item |
|---|---|---|
| ✅ | protokol | `EnvelopePayload.screenshotPayload(base64Image:frameID:wireLatencyMs:)` — 3. associated value (additive, encodeIfPresent) |
| ✅ | getter | `payload?.screenshotWireLatencyMs` artık screenshotPayload case'ini de kapsar (hostStatus/Delta yanına) |
| ✅ | Mac coordinator | `start(...sendImage:)` callback `(base64, frameID, wireLatencyMs?)`; loop her tick `lastWireLatencyMs` snapshot embed |
| ✅ | RemoteHost | `sendScreenshot(...wireLatencyMs:)` opsiyonel param |
| ✅ | iOS merge | `.screenshotPayload` handler `if let latency` guard ile @Published update — per-frame ~1Hz, hostStatus path'ından daha güncel |
| ⏸ | v0.2.50+ | Wire latency timeline grafiği (son N frame trend) Mac Paneli'nde |

**25 May 2026: Sprint 24 tamamlandı — Per-frame wire latency embed.** Sprint 23'ün 3 sn hostStatus delta lag'i giderildi. Mac coordinator her `screenshotPayload` envelope'una önceki frame'in ACK round-trip ölçümünü embed eder; iOS Mac Paneli badge stream rate'inde (~1Hz default) güncellenir. hostStatus path fallback olarak kalır (eski Mac uyumu için). Mac test 880 → 883 (+3 EnvelopePayloadSumType: round-trip, getter cross-case, frameID/latency independence). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (additive opsiyonel field). Bandwidth: per-frame ~10 byte ek — ihmal edilebilir.

## Sprint 25 — "Wire latency timeline grafiği" (v0.2.50)

| Status | # | Item |
|---|---|---|
| ✅ | saf helper | `LatencySparkline.points` (0-1 normalize) + `push` (ring buffer); SwiftUI bağımsız |
| ✅ | iOS state | `@Published wireLatencyHistory: [Int]` ring buffer, max 20 frame |
| ✅ | iOS view | `WireLatencySparklineView` SwiftUI Path + GeometryReader, badge yanında 80×16 inline |
| ✅ | iOS wire | `.screenshotPayload` handler `LatencySparkline.push`; stopScreenshotStream removeAll |
| ✅ | tests | 14 sparkline test: edge cases, normalize, ring buffer, NormalizedPoint Equatable |
| ⏸ | v0.2.51+ | Sparkline genişliği user preference; OCR-based SoM badge placement (Sprint 20 follow-up); test isolation refactor |

**25 May 2026: Sprint 25 tamamlandı — Wire latency timeline grafiği.** Sprint 24 spot değer (badge) yanına son 20 frame'in trendi inline sparkline olarak eklendi. Saf normalize helper (`Sources/PixelRemote/LatencySparkline.swift`) SwiftUI/CG bağımsız — view katmanı `proxy.size`'a çarpıp Y'yi flip eder. Mac test 883 → 897 (+14). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 26 — "OCR-based SoM badge placement" (v0.2.51)

| Status | # | Item |
|---|---|---|
| ✅ | enum | `BadgePlacement.contentAware` yeni case |
| ✅ | saf helper | `OCRBadgePlacement` — overlapArea/scorePlacements/bestPlacement; Vision dep yok |
| ✅ | async wrapper | `OCRTextDetector` — `VNRecognizeTextRequest(.fast)` background queue + CheckedContinuation; coords pixel + top-left |
| ✅ | renderer | `SoMRenderer.annotate(...textRegions:)` opsiyonel param; `resolvePlacement` per-element strategy resolver |
| ✅ | capture | `ScreenshotCapture.capture` orkestra: contentAware ise upfront OCR + textRegions passla |
| ✅ | MCP | `ui_screenshot.som_options.badge_placement` schema'sına `'content_aware'` enum |
| ⏸ | v0.2.52+ | Per-element OCR crop (whole-image yerine) — performance tuning |
| ⏸ | v0.2.52+ | OCR text confidence threshold (low-conf observations filter) |

**25 May 2026: Sprint 26 tamamlandı — OCR-based SoM badge placement.** v0.2.45 AX role heuristic konvansiyon tabanlıydı; özel layout'larda yine badge text alanını örtebilirdi. v0.2.51 Vision `VNRecognizeTextRequest` ile tüm text bbox'larını çıkarır; her element için 4 köşe adayından **text ile en az çakışan** seçilir. OCR başarısız → `.labelAware` fallback (graceful degradation). Mac test 897 → 913 (+16: 14 OCRBadgePlacement + 2 SoMOptions content-aware coverage). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (additive enum case + opsiyonel param).

## Sprint 27 — "Per-element OCR crop" (v0.2.52)

| Status | # | Item |
|---|---|---|
| ✅ | saf helper | `ElementRegionExpander.expandedRect` — element + badge + padding, image bounds clamp |
| ✅ | async overload | `OCRTextDetector.detectTextRegions(in:cropRect:)` — crop CGImage, Vision pass, coords translate back |
| ✅ | enum | `OCRCropMode` (`.wholeImage` default | `.perElement`); **snake_case raw values** wire docs ile tutarlı |
| ✅ | SoMOptions | `ocrCropMode` field + manuel Codable (backward-compat decode without field) |
| ✅ | capture | `collectTextRegions` dispatcher — `.wholeImage` Sprint 26 path; `.perElement` loop per-element crop + union |
| ✅ | MCP | `ui_screenshot.som_options.ocr_crop_mode` schema |
| ⏸ | v0.2.53+ | OCR text confidence threshold (low-conf observations filter) |
| ⏸ | v0.2.53+ | Parallel per-element Vision (TaskGroup ile wall-clock azaltma) |

**25 May 2026: Sprint 27 tamamlandı — Per-element OCR crop.** Sprint 26 whole-image OCR'a opt-in alternatif olarak per-element crop mode eklendi. Az element + büyük screen senaryolarında scoping benefit + wall-clock saving. Default `.wholeImage` korunur — Sprint 26 davranışı backward-compat. Snake_case enum raw value Sprint 27 ile standart oldu (BadgePlacement camelCase Sprint 26 shipped). Mac test 913 → 928 (+15: 9 ElementRegionExpander + 6 SoMOptions ocrCropMode). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 28 — "Parallel per-element Vision" (v0.2.53)

| Status | # | Item |
|---|---|---|
| ✅ | saf helper | `ParallelCropDetection.detect(cropRects:ocr:)` — withTaskGroup generic OCR orchestration |
| ✅ | capture | `collectTextRegions` `.perElement` branch: sync crop rect list + parallel Vision dispatch |
| ✅ | tests | 10 yeni — empty/single/multi/mixed results, parallel speedup, peak concurrency observer, defensive empty |
| ⏸ | v0.2.54+ | OCR text confidence threshold (low-conf observations filter) |
| ⏸ | v0.2.54+ | OCR cancellation propagation (task cancel → Vision request cancel) |

**25 May 2026: Sprint 28 tamamlandı — Parallel per-element Vision.** Sprint 27 sequential per-element loop'u `withTaskGroup` ile parallel'e geçti. 5 element × 100ms test: sequential 500ms+ → parallel ~300ms+. CPU path'inde gerçek paralelizm; Neural Engine internal serialize ederse worst case sequential (regresyon yok). Mac test 928 → 938 (+10). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (orchestration internal; union ordering Sprint 26'dan beri deterministic değildi).

## Sprint 29 — "Small UX tuning bundle" (v0.2.54)

| Status | # | Item |
|---|---|---|
| ✅ | OCR | `SoMOptions.ocrMinConfidence: Double` + `OCRTextDetector` filter — `.fast` mode noise reduction |
| ✅ | OCR | Cancellation propagation: `Task.isCancelled` guards (`OCRTextDetector` pre/post dispatch; `ParallelCropDetection` collection loop + `group.cancelAll()`) |
| ✅ | iOS UX | Sparkline genişliği user preference — `SparklinePreferences` saf helper + `SettingsTabView` "Görselleştirme" slider + `ChatView` `@AppStorage` wire |
| ✅ | MCP | `ui_screenshot.som_options.ocr_min_confidence` schema |
| ⏸ | v0.2.55+ | Test isolation refactor (LAN SIGBUS flake yapısal çöz) |
| ⏸ | v0.2.55+ | Demo GIF + Apple Developer signing (kullanıcı aksiyonu) |

**25 May 2026: Sprint 29 tamamlandı — 3-in-1 small UX tuning bundle.** Üç bağımsız küçük item (OCR confidence threshold, OCR cancellation propagation, iOS sparkline width preference) tek release'te toplandı. Sprint 1/2/3 bundle paterniyle aynı. Mac test 938 → 945 (+7: 5 SoMOptions confidence + 2 ParallelCropDetection cancellation). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok (3 item'ın tümü additive + backward-compat defaults).

## Sprint 30 — "Test hygiene + flake root cause" (v0.2.55)

| Status | # | Item |
|---|---|---|
| ✅ | analysis | v0.2.37+ flake root cause: **build cache hassasiyeti** (network/port değil) — `LANFramingTests` pure data testi deterministik signal 11; debug print eklemek + clean rebuild çözüyor |
| ✅ | harness | `scripts/test.sh` — clean rebuild + swift test + PASS/FAIL summary (default + `--quick` modu) |
| ✅ | integration test | `LANServiceLifecycleTests` (yeni, 3 test) — gerçek `LANService.start()`/`stop()` port=0 + tearDown pattern referansı |
| ✅ | docs | CHANGELOG'da hypothesis update + Apple Bug Reporter candidate notu |
| ✅ | counts | Önceki PixelLANTests sayım hatası düzeltildi (per-suite "Executed 6" yerine package-level kullan) |

**25 May 2026: Sprint 30 tamamlandı — Test hygiene.** v0.2.37+ documented intermittent LAN test flake root cause analysis: **gerçek test isolation veya port collision değil, Swift toolchain (6.3.2 + Xcode 16+) test target incremental build'inde rare object file corruption** (Heisenbug — print veya clean rebuild ile düzeliyor). Workaround: `scripts/test.sh` clean rebuild önce. Mac test 980 → 983 (+3 LANServiceLifecycleTests). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 35 — "iOS stale-pairing detection + auto-recovery" (v0.2.62)

| Status | # | Item |
|---|---|---|
| ✅ | saf tip | `Sources/PixelRemote/ReconnectAttemptTracker.swift` — `Sendable Equatable` struct, iki bağımsız sayaç (connect/verify) + threshold'lar (5/3) + ready timeout (8s); overflow-safe |
| ✅ | iOS wire | `RemoteSession`: `@Published pairingStaleSuspected` + `establishConnection` catch counter + ready timeout task + `handle()` verify guard counter + ilk verify-passed envelope reset |
| ✅ | iOS UX | `ConnectionLostBanner` ikili mod — normal (Sprint 11 turuncu countdown) + stale prominent kırmızı kart + tek-tıkla "QR'ı Yeniden Tara" butonu |
| ✅ | iOS recovery | `RemoteSession.forgetAndRescan()` — disconnect(forget:true) + tracker fresh + flag clear; ContentView otomatik PairingScannerView'a düşer |
| ✅ | tests | 15 ReconnectAttemptTrackerTests (initial state, threshold partitioning, success reset, overflow, demo scenario regression) + 1 RemoteEnvelopeTests regression fix (conversationSync Sprint 33 v2 eksik) |
| ⏸ | v0.2.63+ | Mac side PairingView teşhis görseli (current code + pk fingerprint kopyalanabilir + regenerate refresh) |
| ⏸ | v0.2.63+ | iOS Settings → Tracker debug expand (count + threshold gözlemi) |

**26 May 2026: Sprint 35 tamamlandı — iOS stale-pairing detection + auto-recovery.** Sprint 34 Mac side `PairingCode` UserDefaults persist + signing key Keychain'de stabil; ama iOS-tarafı eski random code veya değişmiş public key ile reconnect loop'unu sessizce sonsuza dek deniyordu. Bu release threshold-based detection ekledi (5 connect fail / 3 verify fail / 8s ready timeout) + UI prominent kırmızı banner + tek-tıkla recovery. Mac test 983 → 998 (+15 + 1 regression fix). iOS xcodebuild simulator BUILD SUCCEEDED. Breaking change yok.

## Sprint 36 — "MemoryStore + PlaybookLearner MVP" (v0.2.63)

| Status | # | Item |
|---|---|---|
| ✅ | data | `MemoryEntry` + 5 kategori (`profile`/`preference`/`project`/`task`/`note`) + `promptWeight` (0-4) ranking boost |
| ✅ | persist | `MemoryStore` actor — JSONL append-only, `~/Library/Application Support/pixel-agent/memory.jsonl`, soft tombstone, latest-wins loadAll |
| ✅ | scorer | `TextSimilarityScorer` saf helper — Jaccard token similarity (TR+EN stopword filter, minTokenLength=3) |
| ✅ | dedup | `MemoryConsolidator` — Jaccard ≥ 0.85 + aynı category duplicate detection + merge (newer wins + union tags) |
| ✅ | rank | `PlaybookLearner` — query → top-N relevant entries; score × category weight × recipe tag boost |
| ✅ | wire | `ChatViewModel.send` → `relevantContext` → `formatPrompt` → backend `system:` prefix |
| ✅ | MCP | `save_memory` + `search_memory` tool'ları (standalone, MCP server bağımsız) |
| ✅ | UI | Settings → "Hafıza" 6. tab (entry list + swipe delete + Optimize Et) |
| ⏸ | v0.2.64+ | CoreML/SwiftNLP embedding (kısa metin similarity kalitesi) |
| ⏸ | v0.2.64+ | iOS memory list UI (read-only) |
| ⏸ | v0.2.64+ | Otomatik post-task capture (Claude tool-call sonrası entry önerisi) |
| ⏸ | v0.2.64+ | File lock multi-process race koruması (durability) |

**26 May 2026: Sprint 36 tamamlandı — MemoryStore + PlaybookLearner MVP.** v3'e ilk kez cross-session persistent memory. Agent her user mesajı öncesi geçmiş benzer task'leri otomatik olarak `system` prompt'a enjekte eder (PlaybookLearner top-N ranking). v2'nin (~64k LOC) memory paterniyle uyumlu, ama embedding-free Jaccard MVP. Mac test 998 → 1043 (+45: 17 store + 12 scorer + 9 consolidator + 13 learner + 4 regression update). iOS BUILD SUCCEEDED. Breaking change yok.

## Sprint 37 — "Semantic memory matching" (v0.2.64)

| Status | # | Item |
|---|---|---|
| ✅ | probe | `NLEmbedding` Türkçe için ne sentence ne word destek YOK (probe doğrulandı); İngilizce sentence dim=512 mevcut |
| ✅ | tier 2 | `CharNGramScorer` (n=3 trigram Jaccard) — multilingual morphology, sıfır model overhead |
| ✅ | language | `LanguageDetector` (NLLanguageRecognizer wrap + 12-char minimum eşik defensive guard) |
| ✅ | dispatcher | `EmbeddingScorer` 3-tier: English→NLEmbedding sentence, other→char n-gram, fallback→word Jaccard |
| ✅ | wire | `PlaybookLearner.relevant()` artık `EmbeddingScorer.score()` çağırır; threshold 0.55 → 0.35 |
| ✅ | settings | `@AppStorage` toggle "Anlamsal Eşleştirme" (default ON); Sprint 36 word Jaccard'a dönmek için opt-out |
| ✅ | tests | 38 yeni (14 ngram + 16 embedding + 8 language); **Sprint 36 "Erkut" regression artık geçiyor** |
| ⏸ | v0.2.65+ | CoreML multilingual MiniLM (~135MB bundle, paraphrase-multilingual-MiniLM-L12-v2) — TR sentence embedding kalitesi |
| ⏸ | v0.2.65+ | Embedding caching (entry kaydedildiğinde precompute, JSONL schema breaking) |

**26 May 2026: Sprint 37 tamamlandı — Semantic memory matching.** Sprint 36 word Jaccard'ın kısa metin zayıflığı çözüldü. Apple NLEmbedding (İngilizce sentence, dim=512) + character n-gram (Türkçe + multilingual morphology) + Sprint 36 fallback 3-tier hybrid scorer. "Beni Erkut diye çağır" + "Erkut burada" artık anlamlı skor verir (regression test geçiyor). Mac test 1043 → 1081 (+38). iOS BUILD SUCCEEDED. Breaking change yok.

## Sprint 38 — "ProactiveEngine MVP (idle + appChange)" (v0.2.65)

| Status | # | Item |
|---|---|---|
| ✅ | enum | `ProactiveTrigger` + `TriggerKind` (idle/appChange Tier 1; Sprint 39 +3 case rezerv) |
| ✅ | mute | `SuppressionStore` — kind-level + bundle-level UserDefaults persist |
| ✅ | rate | `ProactiveRateLimiter` — global cooldown (300s default) + per-kind override + Date injection |
| ✅ | detector | `IdleDetector` — `CGEventSource.secondsSinceLastEventType` polling 10s, threshold 15dk default, mockable IdleSource |
| ✅ | detector | `AppChangeObserver` — `NSWorkspace.didActivateApplicationNotification` + per-bundle 60s debounce, self-filter |
| ✅ | orchestrator | `ProactiveEngine` actor — start/stop, suppression+rate-limit chain, `SystemNotifications.post` delivery |
| ✅ | UI | Settings → "Proaktif" 7. tab (master toggle + per-kind on/off + idle stepper + suppressed bundles list) |
| ✅ | lifecycle | `RootView.task` blokunda `proactiveEngine.start()` (SystemNotifications.requestAuthorization sonrası) |
| ✅ | tests | 43 yeni (9 trigger + 9 suppression + 10 rate-limiter + 8 engine + 7 idle detector) + 1 regression update |
| ⏸ | v0.2.66+ | Sprint 39 Tier 2 — windowDwell (Accessibility), typedPause (CGEventTap), calendarEvent (EKEventStore) |
| ⏸ | v0.2.66+ | Hot-reload master toggle (şu an Restart-required) |
| ⏸ | v0.2.66+ | Notification tap → ChatView pre-fill ("Boştasın, ne yapmak istersin?") |

**26 May 2026: Sprint 38 tamamlandı — ProactiveEngine MVP.** v2'nin pasif UX paterni v3'e MVP olarak indi (idle + appChange, no permission). System notification ile kullanıcıyı yönlendirir; suppression + rate limiter spam'i önler. Sprint 39 Tier 2 (windowDwell, typedPause, calendar) permission-required trigger'lara ayrıldı. Mac test 1081 → 1124 (+43). iOS BUILD SUCCEEDED. Breaking change yok.

## Sprint 39 — "ProactiveEngine Tier 2 (v2 paritesi)" (v0.2.66)

| Status | # | Item |
|---|---|---|
| ✅ | enum | `ProactiveTrigger` +3 case (windowDwell/typedPause/upcomingEvent); TriggerKind 2→5 |
| ✅ | enum | `PermissionRequirement` yeni enum (.none/.accessibility/.calendar) — Settings UI badge için |
| ✅ | detector | `TypedPauseDetector` actor — CGEventSource keyDown polling, 8-30s pause window state machine, **permission YOK** |
| ✅ | detector | `WindowDwellDetector` actor — AXUIElement title polling + per-window dwell counter, Accessibility downgrade (title boş → bundle bazında) |
| ✅ | detector | `CalendarEventDetector` actor — EKEventStore polling 60s, 3-10dk fire window, dedupKey "title@unix_start", Calendar permission |
| ✅ | engine | ProactiveEngine 3 yeni detector lifecycle + format() Turkish copy 3 yeni case |
| ✅ | UI | Settings → Proaktif tab: per-kind permission badge (✓/⚠), İzinler section (Accessibility deep-link + Calendar requestAccess + Durumu Yenile) |
| ✅ | tests | 30 yeni (9 TypedPause + 7 WindowDwell + 7 Calendar + 5 ProactiveTrigger Sprint 38 update + 2 humanDescription/bundle key); Mac 1124 → 1150 |
| ⏸ | v0.2.67+ | Notification tap → ChatView pre-fill ("Proaktif uyarı: ..." kontekst) |
| ⏸ | v0.2.67+ | Calendar event metadata Inline (location → harita link, attendees → ChatView'da listele) |
| ⏸ | v0.2.67+ | iOS proactive (Background App Refresh — sınırlı, calendar widget) |

**26 May 2026: Sprint 39 tamamlandı — v2 paritesi.** v2'nin 5 trigger enum case'in tamamı v3'e modüler SPM mimarisinde indi. typedPause permission YOK (CGEventSource public API). windowDwell Accessibility (yoksa downgrade). upcomingEvent Calendar (yoksa no-op). Settings UI permission badge + System Settings deep-link. Mac test 1124 → 1150 (+26 net). iOS BUILD SUCCEEDED. Breaking change yok.

## Sprint 40 — "Notification tap → ChatView smooth handoff" (v0.2.67)

| Status | # | Item |
|---|---|---|
| ✅ | composer | `ProactivePromptComposer` saf helper — 5 trigger için Turkish first-person user voice prompt |
| ✅ | encode | `ProactiveTrigger.userInfoPayload()` + `init?(userInfoPayload:)` — UNNotification.userInfo Sendable dict round-trip |
| ✅ | system | `SystemNotifications.post(title:body:userInfo:)` overload — UNMutableNotificationContent.userInfo set |
| ✅ | dispatch | `NotificationActionDispatcher` UNUserNotificationCenterDelegate — didReceive tap → normalize → decode → compose → broadcast |
| ✅ | engine | `ProactiveEngine.Delivery` typealias 2-arg → 3-arg (`userInfo`); defaultDelivery + handle(_:) trigger.userInfoPayload() forward |
| ✅ | wire | `ChatViewModel.injectDraft(_:)` + ChatView/DualChatHost `.onReceive(.proactivePromptInject)` listener |
| ✅ | lifecycle | RootView .task `NotificationActionDispatcher.shared.register()` |
| ✅ | UI | Settings → Proaktif tab "Bildirimi tıklayınca sohbete prompt aktar" opt-out toggle (default ON) |
| ✅ | tests | 30 yeni (9 composer + 12 userInfo round-trip + 9 dispatcher) + 8 Sprint 38 regression update |
| ⏸ | v0.2.68+ | Dual mode: aktif focus sütun (left-only yerine last-active track) |
| ⏸ | v0.2.68+ | Calendar trigger: location → harita link + attendees ChatView pre-fill |
| ⏸ | v0.2.68+ | iOS proactive — Background App Refresh sınırlı calendar widget candidate |

**26 May 2026: Sprint 40 tamamlandı — smooth handoff.** Sprint 38-39 notification tap'i muğlaktı (sadece app aktivasyon). Sprint 40 trigger-spesifik hazır prompt'la ChatView composer'ı otomatik doldurur. **Confirm-first UX** (auto-send YOK) — kullanıcı kontrolünde. Mac test 1150 → 1180 (+30). iOS BUILD SUCCEEDED. Breaking change yok pratikte (Delivery typealias 3-arg ama dış API uyumlu).

## Demo Senaryosu (Sprint 1 sonrası)

> Kullanıcı pixel-agent'ı açar. `⌘N` ile yeni sohbet. **Empty state'te 4 prompt chip görür** ("Bu klasörü özetle" / "Code review yap" / "Plan modunda araştırma" / "Subagent ile karşılaştır"). "Plan modunda araştırma" chip'ine tıklar. **Plan toggle otomatik açılır**, sağ tarafta **read-only tool list paneli** belirir (Read ✓ / Glob ✓ / Edit ✗ / Bash ✗). Send'e basar. **Typing indicator 3 dot pulse** ile başlar. Claude yanıtı **markdown formatında** stream eder; kod bloğunun sağ üstünde **"Kopyala" butonu**. Kullanıcı subagent panelinden Gemini'ye "PDF özetle" dispatch eder. Subagent panelde çalışırken, **bittiğinde ana chat'e `[subagent gemini] sonuç:` mesajı düşer**. Bu sırada telefonundan iOS dashboard ile backend'i Codex'e değiştirir; **Mac üstte "📱 Telefon: Codex'e geçildi" toast** belirir. Authentication exparit olursa **"Authenticate Claude" butonu**na basıp `claude login` Terminal'i açılır. Sohbet bitince "About" → **"MCP Entegrasyonu"** menüsünden JSON snippet'i kopyalayıp Claude Code config'ine yapıştırır.

## Tracking

Bu dosya kalıcı kayıt; her sprint sonu güncellenir (status değişimleri, yeni eklenen gap'ler, kaldırılan/birleşen item'lar). Plan agent yeniden audit çağrılırsa sonuç bu dosyaya merge edilir.

Audit kaynağı: Plan agent çağrısı, oturum 23 May 2026 (memory: pixel_agent_v3.md madde 34 sonrası).
