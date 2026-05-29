# ADR-0037: Skill / Recipe Extraction — Self-Improving Workflows

**Status:** Accepted (Faz 1 landed; v0.2.80) · Faz 2 (otomatik extraction) defer
**Date:** 2026-05-29
**Tags:** memory, skills, jsonl, mcp, playbook, self-improving, agent

## Context

[ADR-0033](0033-cross-session-memory.md) cross-session memory'yi getirdi: `MemoryStore` + `PlaybookLearner` agent'ın **atomik fact**'leri ("Beni Erkut diye çağır", "kısa cevap tercih ederim") hatırlamasını sağlıyor. Ama **tekrarlanabilir çok-adımlı workflow**'lar (recipe: "PR review akışı: 1… 2… 3…") tek bir `content` string'e sıkışıyordu; ne yapılandırılmış adımlar, ne versiyon, ne kullanım takibi vardı.

Rekabet analizi (Nous Research **Hermes Agent**, 171k★) en güçlü farkını "self-improving skill loop" olarak konumluyor: agent karmaşık bir görevi çözünce yeniden kullanılabilir bir skill yazar, kullandıkça rafine eder. pixel-agent'ın memory altyapısı buna parity için doğal bir aday. Bu ADR, `PlaybookLearner`'ın yanına **ayrı bir skill subsystem** ekler.

## Decision

### Veri modeli: ayrı `SkillEntry` + `SkillStore` (skills.jsonl)

`MemoryEntry`'ye `.skill` kategorisi eklemek yerine **ayrı tip + ayrı store**. Gerekçe: skill yapılandırılmış (title/trigger/steps[]), versiyonlu ve kullanım-takipli; `MemoryEntry`'ye sıkıştırmak schema'yı kirletir ve `MemoryConsolidator`'ın Jaccard-merge'ü skill versiyonlarını yanlışlıkla birleştirir. Ayrı store, `MemoryStore`/`ConversationStore`'un kanıtlanmış JSONL append-only paternini ([ADR-0006](0006-jsonl-append-only-storage.md)) birebir izler ve `ArchiveTagsStore`/`ArchiveTitleStore` gibi mevcut "ayrı küçük JSONL store" desenine uyar.

### Self-improving: lineage-aware versiyonlama

```
SkillEntry { id, lineageID, version, supersedesID, title, trigger,
             steps:[String], tags, usageCount, createdAt, updatedAt,
             deleted, origin(.explicit/.auto) }
```

- **`lineageID`** kalıcı kimlik; tüm versiyonlar paylaşır. **`update`** yeni satır (`version+1`, `supersedesID`) append eder — eski versiyon arşivde kalır (tombstone DEĞİL).
- **Aktif head** = lineage içindeki en yüksek `version` (latest-by-id → group-by-lineage max-version). `loadActive()` deleted olmayan head'leri döner.
- **`recordUsage`** aynı id'yi `usageCount+1` ile yeniden yazar (latest-wins by id → versiyon artmaz) — her `apply_skill`'de sayaç artar.
- **`delete(lineageID:)`** deleted tombstone versiyonu append eder (lineage gizlenir). **`compact()`** sadece aktif head'leri tutar (eski versiyonlar + collapsed usage satırları + deleted purge).

### Adım formatı: `[String]` (yapılandırılmış-lite)

Serbest-metin markdown yerine adım dizisi — JSON-temiz, UI numaralı liste, test edilebilir, `append_steps` ile mutation kolay. İç içe/şartlı adımlar YAGNI.

### Ranking + injection: `SkillRanker`

[PlaybookLearner](0033-cross-session-memory.md) paterni; `EmbeddingScorer` (NLEmbedding + char n-gram + Jaccard) yeniden kullanılır — **yeni dependency yok**. Skor `score(query, trigger + " " + title)` (steps gürültü); `usageCount` boost'u (`min(usageCount,5)×0.02`) sık kullanılan skill'i öne çıkarır (self-reinforcing). `ChatViewModel.send` her mesaj öncesi `SkillStore.loadActive()` → `relevant` → `formatPrompt` ile system prompt'a **ayrı "[İlgili skill'ler]" section** enjekte eder (memory'den bağımsız ranklanır).

### Extraction: explicit (Faz 1) + 4 MCP tool

- **`CaptureIntentDetector.detectSkillIntent`** (mevcut detector'a saf fonksiyon) — "şu adımları izle / step by step / this workflow" sinyali; `MemoryCaptureInstruction.contextualPrefix` bunu yakalayıp `create_skill` nudge'u ekler. `extractStepHints` numaralı satırları kaba böler (LLM gerçek çıkarımı yapar).
- **MCP tool'lar** (`SkillTools`, standalone — `MemoryTools` paterni): `create_skill` / `update_skill` (self-improve) / `list_skills` / `apply_skill` (usageCount++). `BuiltInTools.makeRegistry`'ye kayıtlı; bundle-bağımsız.

### UI

Settings "Hafıza" tab'ına skill `Section` — başlık + versiyon + usageCount + origin rozeti + adım `DisclosureGroup` + sil. Ayrı tab gerekmez.

## Alternatives considered

- **`MemoryEntry`'ye `.skill` kategorisi + steps alanı** — en az kod ama `MemoryConsolidator` Jaccard-merge skill versiyonlarını bozar; schema kirlenir. Reddedildi.
- **Serbest-metin tek-string steps** — yapısal sorgu/mutation imkânsız; `[String]` tercih edildi.
- **Otomatik (görev-sonrası) extraction Faz 1'de** — en yüksek FP/gürültü riski (her çok-adımlı tur skill üretir). Faz 2'ye ertelendi; self-improving altyapısı (versiyonlama) Faz 1'de hazır olduğundan Faz 2 sadece "tetikleme talimatı" ekler.
- **CoreData/SQLite** — [ADR-0006](0006-jsonl-append-only-storage.md) JSONL ilkesi korundu.

## Consequences

**Olumlu:**
- Hermes-tarzı self-improving skill loop'a parity — pixel'in "memory derinliği" açığını kapatır.
- usageCount boost → sık kullanılan skill ranking'de yükselir (self-reinforcing).
- Zero-dep (EmbeddingScorer + JSONL reuse); `MemoryConsolidator` çakışması yok.
- MCP-exposed → Claude/Codex/Gemini CLI doğrudan skill yönetir; Mac app gerekmez.

**Olumsuz:**
- JSONL şişmesi (her update + recordUsage yeni satır) → `compact()` lineage-aware purge ile sınırlanır (manuel/Settings "Optimize" benzeri; otomatik schedule v0.3+).
- Otomatik extraction Faz 1'de yok → skill'ler şimdilik explicit niyet / agent tool çağrısıyla doğar.
- Multi-process file lock yok (ADR-0033 ile aynı bilinen sınır).
- system prompt şişmesi riski → skill section limit=2 + eşik 0.35.

## Plan (iterative)

- **Faz 1 ✓** (v0.2.80): `SkillEntry` + `SkillStore` (versiyon/supersede/recordUsage/compact) + `SkillRanker` + `CaptureIntentDetector.detectSkillIntent`/`extractStepHints` + 4 MCP tool + ChatViewModel injection + `MemoryCaptureInstruction` skillSection + Settings UI + testler. **Self-improving Faz 1'de** (update + versiyon + usageCount boost) — explicit re-use ile çalışır.
- **Faz 2 (defer):** Otomatik görev-sonrası extraction (system prompt talimatı + Settings toggle, default OFF — FP riski) + `origin:.auto` ayrımı + (opsiyonel) iOS read-only skill listesi + geçmiş-versiyon görünümü.

## References

- [`Sources/PixelMemory/SkillEntry.swift`](../../Sources/PixelMemory/SkillEntry.swift) · [`SkillStore.swift`](../../Sources/PixelMemory/SkillStore.swift) · [`SkillRanker.swift`](../../Sources/PixelMemory/SkillRanker.swift)
- [`Sources/PixelMemory/CaptureIntentDetector.swift`](../../Sources/PixelMemory/CaptureIntentDetector.swift) · [`MemoryCaptureInstruction.swift`](../../Sources/PixelMemory/MemoryCaptureInstruction.swift)
- [`Sources/PixelMCPServer/SkillTools.swift`](../../Sources/PixelMCPServer/SkillTools.swift)
- [`Sources/PixelMacApp/ChatViewModel.swift`](../../Sources/PixelMacApp/ChatViewModel.swift) (send injection) · [`SettingsView.swift`](../../Sources/PixelMacApp/SettingsView.swift) (skill UI)
- [ADR-0033 — Cross-Session Memory](0033-cross-session-memory.md) · [ADR-0006 — JSONL Append-Only Storage](0006-jsonl-append-only-storage.md)
