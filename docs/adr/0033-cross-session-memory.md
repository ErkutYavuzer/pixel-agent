# ADR-0033: Cross-Session Memory — MemoryStore + PlaybookLearner + Semantic Matching

**Status:** Accepted (Sprint 36-37 + 41 landed; v0.2.63 / v0.2.64 / v0.2.68)
**Date:** 2026-05-26
**Tags:** memory, persistence, jsonl, nlembedding, playbook, agent

## Context

v3 başından beri ([ADR-0006](0006-jsonl-append-only-storage.md)) `ConversationStore` sohbet geçmişini saklıyordu, ama bu **per-conversation** idi — agent oturumlar arası hiçbir şey "hatırlamıyordu". Kullanıcı "Beni Erkut diye çağır" dediğinde bir sonraki oturumda unutuluyordu.

pixel-agent2 (~64k LOC) bunu `MemoryStore` (5 kategori) + `MemoryConsolidator` (cosine 0.92) + `PlaybookLearner` ile çözmüştü (bkz. [[pixel_agent_projects]] / docs/architecture-decisions-from-v2.md). v3'te MVP olarak yeniden inşa edildi: önce embedding-free (Sprint 36), sonra semantic matching ile güçlendirildi (Sprint 37), en son agent-tetiklemeli otomatik capture eklendi (Sprint 41).

Hedef: agent her user mesajı öncesi geçmiş ilgili bilgileri otomatik olarak `system` prompt'a enjekte etsin; kayıt hem manuel (`save_memory` MCP tool) hem agent-otomatik (capture intent) yapılabilsin.

## Decision

### Katman 1 — Persistence (Sprint 36, v0.2.63)

`PixelMemory` modülüne (ConversationStore yanına) memory subsystem:

- **`MemoryEntry`** — 5 kategori (`profile`/`preference`/`project`/`task`/`note`) + `promptWeight` (0-4 ranking boost) + tags + timestamp + soft-delete tombstone.
- **`MemoryStore`** (actor) — JSONL append-only `~/Library/Application Support/pixel-agent/memory.jsonl`. Soft tombstone (silme = tombstone append), `loadAll` latest-wins dedup. ADR-0006 ile aynı durability ilkesi.
- **`TextSimilarityScorer`** (saf) — Jaccard token similarity, TR+EN stopword filter, minTokenLength=3.
- **`MemoryConsolidator`** — Jaccard ≥ 0.85 + aynı kategori duplicate → merge (newer wins + union tags). v2'nin cosine 0.92'sinin embedding-free eşi.
- **`PlaybookLearner`** — query → top-N relevant: score × kategori weight × recipe-tag boost.

### Katman 2 — Wire (Sprint 36)

```
ChatViewModel.send(query)
  └─ PlaybookLearner.relevant(query:) → top-N MemoryEntry
       └─ formatPrompt → backend system: prefix
```

Agent her mesajda geçmiş bağlamı görür. MCP tool ([`MemoryTools.swift`](../../Sources/PixelMCPServer/MemoryTools.swift)): `save_memory` + `search_memory` — standalone, bundle-bağımlı değil (doğrudan PixelMemory, MCP server in-process).

### Katman 3 — Semantic matching (Sprint 37, v0.2.64)

Word Jaccard kısa metinde zayıf ("Beni Erkut diye çağır" ↔ "Erkut burada" düşük skor verir). 3-tier `EmbeddingScorer`:

| Dil | Scorer | Neden |
|---|---|---|
| İngilizce | Apple `NLEmbedding` sentence (dim=512) | yüksek kalite semantic |
| Türkçe / diğer | `CharNGramScorer` (trigram Jaccard) | **NLEmbedding TR sentence/word DESTEKLEMİYOR** (probe ile doğrulandı); morphology-aware |
| fallback | word Jaccard (Sprint 36) | dil tespit edilemezse |

`LanguageDetector` (`NLLanguageRecognizer` + 12-char minimum defensive eşik) dispatcher seçer. threshold 0.55 → 0.35 düşürüldü. Settings "Anlamsal Eşleştirme" toggle (default ON; Sprint 36 word Jaccard'a opt-out).

### Katman 4 — Otomatik capture (Sprint 41, v0.2.68)

Manuel `save_memory`'den agent-tetiklemeli'ye:
- **`CaptureIntentDetector`** (saf) — 28 TR + 24 EN pattern, substring case-insensitive; `detectCategory` per-kategori priority.
- **`MemoryCaptureInstruction`** (saf) — iki katmanlı system prompt: `baseInstruction` (kalıcı talimat) + `contextualPrefix` (intent-hit inline hint) + `assembleSystemPrompt` (PlaybookLearner + base + contextual section order).
- Agent format kuralı: "(Hafızaya kaydedildim: …)" ile kullanıcıya bildirir. `save_memory` description'ına "NE ZAMAN ÇAĞIR/ÇAĞIRMA" + TR+EN trigger örnekleri + format kuralı eklendi.

## Alternatives considered

- **CoreML multilingual MiniLM (paraphrase-multilingual-MiniLM-L12-v2, ~135MB)** — TR sentence embedding kalitesi en iyisi olurdu, ama bundle 7.9MB → ~143MB şişerdi. v0.2.65+ defer; char n-gram MVP için yeterli.
- **Core Data / SQLite** — ADR-0006 JSONL ilkesi korundu (append-only, git-diff'lenebilir, debug-friendly, zero-dep).
- **v2'nin cosine 0.92 embedding consolidator'ı** — embedding pipeline gerektirir; Jaccard 0.85 MVP'de yeterli, semantic Sprint 37'de ayrı katman geldi.
- **Embedding caching (entry kaydında precompute)** — JSONL schema breaking; v0.2.65+ defer.

## Consequences

**Olumlu:**
- Agent oturumlar arası kullanıcı tercihlerini/projelerini hatırlar — "kişisel agent" iddiası güçlenir.
- Embedding-free MVP zero-dep ilkesine sadık; Apple NLEmbedding system framework.
- v2 memory paterniyle kavramsal uyum (5 kategori, playbook) — portfolio'da "v2'den öğrenilmiş mimari" anlatısı.

**Olumsuz:**
- JSONL büyüdükçe `loadAll` tüm dosyayı okur — binlerce entry'de latency (consolidation amortize eder ama unbounded değil).
- NLEmbedding TR desteklemediği için Türkçe semantic kalitesi char n-gram ile sınırlı (CoreML defer).
- Otomatik capture false-positive riski (pattern-based) — agent gereksiz "kaydedildim" diyebilir; pattern listesi gerçek kullanımla balanslanmalı.
- Multi-process file lock yok — iki app instance aynı anda yazarsa race (durability follow-up).

## Plan (iterative)

- **Sprint 36 ✓** (v0.2.63): MemoryStore + MemoryEntry + scorer + consolidator + PlaybookLearner + MCP tools + Settings "Hafıza" tab.
- **Sprint 37 ✓** (v0.2.64): EmbeddingScorer 3-tier + LanguageDetector + threshold 0.35; "Erkut" regression geçer.
- **Sprint 41 ✓** (v0.2.68): CaptureIntentDetector + MemoryCaptureInstruction + auto-capture.
- **Defer (v0.2.65+):** CoreML multilingual MiniLM; embedding caching; iOS memory list (read-only); multi-process file lock.

## References

- [`Sources/PixelMemory/`](../../Sources/PixelMemory/) — MemoryStore, MemoryEntry, PlaybookLearner, EmbeddingScorer, CharNGramScorer, LanguageDetector, CaptureIntentDetector, MemoryCaptureInstruction, MemoryConsolidator, TextSimilarityScorer
- [`Sources/PixelMCPServer/MemoryTools.swift`](../../Sources/PixelMCPServer/MemoryTools.swift) — save_memory / search_memory
- [ADR-0006 — JSONL Append-Only Storage](0006-jsonl-append-only-storage.md)
- [ADR-0010 — CLI Subprocess Backend](0010-cli-subprocess-backend.md) (system prompt injection point)
- [Apple — NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding)
