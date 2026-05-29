# ADR-0038: Computer-Use Macro Recorder — Semantic AX Replay

**Status:** Accepted (Faz 1 = A+B+C landed; v0.2.81) · Faz 2 defer
**Date:** 2026-05-29
**Tags:** computer-use, macro, recording, replay, accessibility, jsonl, mcp

## Context

[ADR-0026](0026-pixel-computer-use.md) (PixelComputerUse, AX-first hybrid) agent'ın UI'yi semantik olarak (AX query/opaqueID) tıklamasını/yazmasını sağlıyor — ama her görev tek-seferlik. Tekrarlanan işler ("her sabah şu app'te şu adımlar") için **kaydet-bir-kez, tekrar-oynat** bir makro, pixel'in en güçlü farklılaştırıcısı olan AX moat'ını sergiler: makro **koordinat değil semantik** saklanır; replay'de element AX ile yeniden çözülür → pencere taşınsa/boyut değişse bile çalışır. Bu, "Show HN" için killer demo ("agent bir kez yaptı → makro → pencereyi taşı → yine çalışıyor").

## Decision

### Recording kaynağı: `ControlSocketServer` hook (CGEventTap DEĞİL)

Agent'ın tüm `ui_*` çağrıları tek noktadan (`ControlSocketServer.execute`, ADR-0018 bridge) akıyor. Başarılı `ui_click`/`ui_type`'ta `onUIActionRecorded` hook'u semantik `MacroStep` yayar. **CGEventTap (insan input) reddedildi:** koordinat-tabanlı (kırılgan replay), Input Monitoring izni + tüm klavyeyi dinleme (privacy), ve AX moat'ını kullanmaz. `ui_query`/`ui_resolve`/`ui_screenshot` kaydedilmez (exploratory/read-only).

### Veri modeli: ayrı `MacroStore` (SkillStore'u genişletme)

- **`MacroStep`** (PixelComputerUse): enum `.click(query:opaqueID:count:modifiers:)` / `.type(text:into:)` / `.screenshot` / `.wait`. `UIQuery`/`ModifierFlags`/`ScreenshotTarget` zaten Codable → otomatik serialize. **`.click` hem query hem opaqueID tutar** → replay'de çift-handle.
- **`MacroRecording` + `MacroStore`** (PixelMemory): `macros.jsonl`, JSONL append-only (ADR-0006 / MemoryStore paterni), latest-wins by id, tombstone. **`PixelMemory` → `PixelComputerUse` dep eklendi** (MacroStep için; döngü yok). Skill'lerden ayrı çünkü skill = LLM'e doğal-dil reçete, macro = deterministik AX aksiyon (farklı execute modeli — [ADR-0037](0037-skill-recipe-extraction.md)'nin "ayrı tip" gerekçesi birebir).

### Replay: semantik re-resolve + runaway safety

- **`PixelComputerUse.clickResolved(opaqueID:)`** — resolve-and-click primitifi (yoksa nil).
- **`MacroReplayer`** (actor) — adım sırayla: önce `opaqueID` re-resolve, başarısızsa `query` fallback, hiç yoksa `NotFoundPolicy` (retry×3/abort). Karar mantığı saf **`MacroReplayPlan`** (validate + decideOnNotFound + isBlockedByPlanMode → test edilebilir; AX'sız).
- **Runaway safety:** `maxSteps` cap + `maxDurationSeconds` wallclock + her adımda `Task.checkCancellation()` (UI "Durdur").
- **Plan Mode guard:** destructive (.click/.type) adım + `allowDestructive == false` → bloklanır. MCP yolunda `planModeGuard("replay_macro")` da enforce eder.
- **ToolArbiter:** replay `.pointer` mutex'ini sarmaz (re-entrancy deadlock riski) → Faz 1 makro **atomik değil** (her adım kendi acquire'ı). Replay'in click'leri `computer`'a doğrudan gider (execute'a re-enter etmez → recording hook tetiklenmez, döngü yok).

### MCP + UI

- **`list_macros`** (standalone, MacroStore) + **`replay_macro`** (bridge, plan-guarded) — agent makroları listeleyip çalıştırabilir.
- **Settings "Makrolar" tab** — kayıt toggle (canlı adım) + makro listesi + "Oynat" (progress + Durdur) + sil.

## Alternatives considered

- **CGEventTap insan-recording** — koordinat-tabanlı, kırılgan, privacy-ağır (Input Monitoring + tüm klavye), AX moat'ını kullanmaz. Reddedildi (Faz 2'de bile düşük öncelik; yine de koordinat değil per-event AX hit-test gerekir).
- **SkillStore'u action-typed step'lerle genişletmek** — `SkillEntry.steps: [String]` bilinçli doğal-dil; action enum'a çevirmek geriye-uyumu kırar + iki kavramı bulandırır. Ayrı MacroStore.
- **Koordinat makroları** — pencere taşınınca kırılır; AX semantik re-resolve tercih edildi (moat).
- **Atomik replay (ToolArbiter ile sar)** — re-entrant olmayan arbiter'da deadlock; Faz 2'de re-entrancy gerekir.

## Consequences

**Olumlu:**
- AX moat'ını doğrudan sergileyen killer demo (semantik replay, pencere-taşımaya dayanıklı).
- Zero-dep (UIQuery/Codable + JSONL reuse); recording ek izin gerektirmez (mevcut AX yeterli).
- MCP-exposed → agent makro listeleyip çalıştırır; Settings'ten kullanıcı kaydeder/oynatır.
- Saf `MacroReplayPlan` + `MacroStep`/`MacroStore` hermetic test (replay execution integration).

**Olumsuz / bilinen sınırlar:**
- **Privacy — `.type` düz metin saklar** (şifre dahil). Secure-field (`AXSecureTextField`) maskeleme **Faz 2'ye ertelendi** — Faz 1'de kullanıcı uyarılmalı (makro yazılan metni saklar).
- UI-değişiminde replay kırılganlığı (title dile/state'e göre değişirse re-resolve fail) → çift-handle (opaqueID + query) + retry azaltır, sıfırlamaz.
- Sabit `interStepDelayMs` bazı app'lerde yetersiz/fazla → adaptif wait Faz 2.
- Makro atomik değil (replay sırasında başka pointer aksiyonu araya girebilir).
- Multi-process file lock yok (ADR-0033/0037 ile aynı bilinen sınır).

## Plan (iterative)

- **Faz 1A ✓** (v0.2.81): `MacroStep` + `MacroReplayPlan` (saf) + `MacroRecording` + `MacroStore` + testler. (AX/UI yok.)
- **Faz 1B ✓** (v0.2.81): `ControlSocketServer` hook + `MacroRecorder` (@MainActor) + wire-up + Settings "Makrolar" kayıt/liste.
- **Faz 1C ✓** (v0.2.81): `clickResolved` + `MacroReplayer` + `list_macros`/`replay_macro` MCP + Settings "Oynat" + progress.
- **Faz 2 (defer):** secure-field maskeleme (privacy); adaptif wait (AX-stable polling); atomik replay (ToolArbiter re-entrancy); MenuBarExtra/⌘⇧R + mascot "recording/replaying" state; agent-tetikli `start/stop_macro_recording`; (düşük öncelik) CGEventTap insan-recording.

## References

- [`Sources/PixelComputerUse/MacroTypes.swift`](../../Sources/PixelComputerUse/MacroTypes.swift) · [`MacroReplayPlan.swift`](../../Sources/PixelComputerUse/MacroReplayPlan.swift) · [`MacroReplayer.swift`](../../Sources/PixelComputerUse/MacroReplayer.swift) · [`PixelComputerUse.swift`](../../Sources/PixelComputerUse/PixelComputerUse.swift) (`clickResolved`)
- [`Sources/PixelMemory/MacroRecording.swift`](../../Sources/PixelMemory/MacroRecording.swift) · [`MacroStore.swift`](../../Sources/PixelMemory/MacroStore.swift)
- [`Sources/PixelMacApp/MacroRecorder.swift`](../../Sources/PixelMacApp/MacroRecorder.swift) · [`ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (hook + replay handler) · [`MacroSettingsTab.swift`](../../Sources/PixelMacApp/MacroSettingsTab.swift)
- [`Sources/PixelMCPServer/MacroTools.swift`](../../Sources/PixelMCPServer/MacroTools.swift) + `ToolRegistry.replayMacro`
- [ADR-0026 — PixelComputerUse](0026-pixel-computer-use.md) · [ADR-0028 — opaqueID re-resolve](0028-chained-query-and-opaque-id.md) · [ADR-0037 — Skill Extraction](0037-skill-recipe-extraction.md)
