# ADR-0006: JSONL Append-Only Storage

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** storage, memory

## Context

Conversation history ve memory entry'leri persist edilmeli. Tipik seçimler: SQLite, Core Data, plist, JSON file, JSONL. MVP'de basit tutmak ama büyümeye izin vermek istiyoruz; aynı zamanda kullanıcı dosyalarının okunabilir ve taşınabilir olması bir hedef.

## Decision

İki ayrı dosya, satır-bazlı JSON (JSONL):

- `~/Library/Application Support/pixel-agent/conversation.jsonl`
- `~/Library/Application Support/pixel-agent/memory.jsonl`

Her satır bağımsız bir JSON nesnesidir. Append-only — varolan satırlar düzenlenmez (logical delete için `deleted: true` flag). Yazım `FileHandle.seekToEnd()` + `write(_:)` ile atomik satır ekleme. Okuma satır bazlı stream; bozuk satır → atla, sonrakini oku.

## Alternatives considered

- **SQLite + FTS5** — güçlü query, ama migration schema versioning + concurrent write lock + encryption-at-rest karmaşıklığı. MVP'de gereksiz.
- **Core Data** — relational overhead, iCloud sync privacy kaygısı, NSManagedObject lifecycle Swift Concurrency ile uyumsuz.
- **Plist** — boyut limiti (~100k), tüm dosya rewrite (append yok).
- **Plain text** — parse hata payı yüksek, schema yok.

## Consequences

**Positive**
- Durability: append-only → process crash orta satırda olursa son satır eksik kalabilir, önceki satırlar zarar görmez.
- Human-readable: `cat`, `jq`, GitHub diff ile okunur.
- Incremental indexing: append → notification → background index task, ana thread bloklanmaz.
- Encryption-at-rest kolay (IV+key rotation).
- Portable: drag-drop başka makineye, iCloud sync friendly.

**Negative / tradeoffs**
- Random access slow (lineer tarama).
- Update için ya logical delete + new entry ya da arşivleme.
- 100k+ entry sonrası okuma yavaşlar (ileride FTS5 acceleration opsiyonel).

## Lessons from pixel-agent2

v2'de JSONL + opsiyonel FTS5 hibrit kullanıldı. MVP'de FTS5 yok — sadece JSONL. Performans sınırına yaklaşıldığında (kullanıcının kendi gözlemine göre) FTS5 katmanı eklenir.

## References

- [JSON Lines spec](https://jsonlines.org/)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-6)
