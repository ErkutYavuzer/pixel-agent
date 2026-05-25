# Changelog

`pixel-agent` projesindeki tüm önemli değişiklikler bu dosyada belgelenir.

Format [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) tabanlıdır,
sürümleme [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) kurallarına uyar.

## [Unreleased]

### Notes
- v0.2 kalan: Subagent Faz 4+ (multi-turn workflow + settings UI); App Store signing.
- v0.2.25 follow-up adayları (hâlâ açık): iOS continuous screenshot streaming; `hostStatus` delta-only push.
- v0.2.38 follow-up: test isolation refactor (flake'ı yapısal çöz); SoM Faz 5 follow-up (badge'i element rect dışına content-aware kaydırma için OCR/AX label-aware logic — şimdi sadece 4 köşe + bounds clamping).
- Bekleyen kullanıcı aksiyonu: Apple Developer ID + notarization; demo GIF recording.

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
