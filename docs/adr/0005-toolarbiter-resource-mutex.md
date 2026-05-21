# ADR-0005: ToolArbiter Resource Mutex

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** concurrency, tools

## Context

Tool çağrıları paylaşılan fiziksel kaynaklara erişir: ekran/klavye (input), clipboard, mikrofon, hoparlör, dosya yazımı. Tek agent senaryosunda bile arka plan task'ları aynı kaynağı isteyebilir. İleride dual-agent (primary + secondary peer) eklenirse kaynak yarışı zorunlu olarak ortaya çıkar.

## Decision

Actor-based `ToolArbiter.shared` paylaşılan kaynakları serialize eder:

```swift
public enum Resource: Hashable {
    case input
    case clipboard
    case mic
    case speaker
    case fileWrite(path: String)
}

public actor ToolArbiter {
    public static let shared = ToolArbiter()
    public func acquire(_ resources: [Resource]) async
    public func release(_ resources: [Resource])
}
```

Path-keyed file lock: iki agent farklı dosyalara paralel yazabilir, aynı dosyaya yazımlar serialize olur. Shell komutları için global sentinel (`<shell>`) — komut metninden path çıkarılamadığı için tüm shell çağrıları tek sıralı. Canonical sıralama (`.input` → `.clipboard` → ... → `.fileWrite`) deadlock-free multi-acquire sağlar.

## Alternatives considered

- **Tool başına global lock** — paralel hiçbir tool çalışmaz; tek agent'ta bile overhead.
- **Per-agent sandbox (virtual display)** — macOS native değil; `xvfb` benzeri infrastructure gerek.
- **Optimistic locking (versioning)** — conflict resolution model determinism'i bozar.

## Consequences

**Positive**
- Deadlock-free (canonical order).
- Fairness: FIFO waiter queue, priority yok.
- Observable: `onWaitStart` / `onWaitEnd` callbacks → UI'da "Secondary kaynağı bekliyor" bildirimi.
- MVP single-agent'ta acquire her zaman anında geri döner — overhead sıfıra yakın.

**Negative / tradeoffs**
- Path-keyed cache büyüyebilir (uzun ömürlü process'lerde periyodik temizleme gerek).
- `Resource` enum genişlerse acquire sıralaması yeniden gözden geçirilmeli.

## Lessons from pixel-agent2

v2'de path-keyed file lock dual-agent'ın paralel dosya editing yapabilmesini mümkün kıldı — git merge conflict yerine arbiter queue. Shell global sentinel olmasaydı iki paralel `run_bash` race condition üretirdi.

## References

- [Swift actor isolation](https://developer.apple.com/documentation/swift/actor)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-3)
