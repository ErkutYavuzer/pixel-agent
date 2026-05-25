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

## Demo Senaryosu (Sprint 1 sonrası)

> Kullanıcı pixel-agent'ı açar. `⌘N` ile yeni sohbet. **Empty state'te 4 prompt chip görür** ("Bu klasörü özetle" / "Code review yap" / "Plan modunda araştırma" / "Subagent ile karşılaştır"). "Plan modunda araştırma" chip'ine tıklar. **Plan toggle otomatik açılır**, sağ tarafta **read-only tool list paneli** belirir (Read ✓ / Glob ✓ / Edit ✗ / Bash ✗). Send'e basar. **Typing indicator 3 dot pulse** ile başlar. Claude yanıtı **markdown formatında** stream eder; kod bloğunun sağ üstünde **"Kopyala" butonu**. Kullanıcı subagent panelinden Gemini'ye "PDF özetle" dispatch eder. Subagent panelde çalışırken, **bittiğinde ana chat'e `[subagent gemini] sonuç:` mesajı düşer**. Bu sırada telefonundan iOS dashboard ile backend'i Codex'e değiştirir; **Mac üstte "📱 Telefon: Codex'e geçildi" toast** belirir. Authentication exparit olursa **"Authenticate Claude" butonu**na basıp `claude login` Terminal'i açılır. Sohbet bitince "About" → **"MCP Entegrasyonu"** menüsünden JSON snippet'i kopyalayıp Claude Code config'ine yapıştırır.

## Tracking

Bu dosya kalıcı kayıt; her sprint sonu güncellenir (status değişimleri, yeni eklenen gap'ler, kaldırılan/birleşen item'lar). Plan agent yeniden audit çağrılırsa sonuç bu dosyaya merge edilir.

Audit kaynağı: Plan agent çağrısı, oturum 23 May 2026 (memory: pixel_agent_v3.md madde 34 sonrası).
