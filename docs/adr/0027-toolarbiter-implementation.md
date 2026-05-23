# ADR-0027: ToolArbiter Implementasyonu (ADR-0005 → koda)

**Status:** Accepted
**Date:** 2026-05-22
**Tags:** concurrency, tools, computer-use

## Context

[ADR-0005](0005-toolarbiter-resource-mutex.md) MVP'de "forward-looking design" olarak yazıldı — kod olarak yoktu. Tek-agent senaryosunda race yoktu, MVP scope dışında bırakıldı. v0.3'te Computer Use'a geçilince ([ADR-0026](0026-pixel-computer-use.md)) durum değişti:

1. **Paralel subagent** ([ADR-0024](0024-subagent-ui-panel.md)) cap=3 — iki subagent aynı anda `ui_click` yaparsa fare iki yere gider, deterministic değil.
2. **Dual-agent** (Claude + Codex peer'lar) — paralel `ui_screenshot` çekebilir, sorun değil; ama paralel `ui_type` aynı text field'a karışır.
3. **`pointer` fiziksel kaynak** — bir tane, paylaşılamaz.

ADR-0005'in tasarımı şu an gerçekten ihtiyaç olduğu için koda iniyor.

## Decision

### `PixelCore.ToolArbiter`

Actor-based, process-global singleton. ADR-0005 spesifikasyonunu birebir takip eder; `Resource` enum bu sprintte 6 case:

```swift
public enum Resource: Hashable, Sendable, Comparable {
    case pointer          // mouse + keyboard CGEvent inject
    case screen           // ScreenCaptureKit session
    case clipboard        // NSPasteboard
    case mic              // AVAudioEngine input
    case speaker          // AVSpeechSynthesizer / NSSound
    case fileWrite(path: String)  // path-keyed — farklı path'ler paralel
}
```

`Comparable` impl deadlock-free multi-acquire için canonical sıralama sağlar (`pointer < screen < clipboard < mic < speaker < fileWrite`, fileWrite içinde path lexicographic).

### API

```swift
public actor ToolArbiter {
    public static let shared = ToolArbiter()

    public func acquire(_ resources: [Resource]) async
    public func release(_ resources: [Resource])
    public func with<T: Sendable>(_ resources: [Resource], body: @Sendable () async throws -> T) async rethrows -> T

    // Inspection (test/observability)
    public func currentlyLocked() -> Set<Resource>
    public func waiterCount() -> Int
}
```

`with(_:body:)` exception-safe — body throw etse, cancel olsa, normal döndürse: `defer { release(...) }` çağrılır.

### Bekleyici (waiter) kuyruğu

```swift
private struct Waiter {
    let id: UUID
    let resources: Set<Resource>
    let continuation: CheckedContinuation<Void, Never>
}
private var waiters: [Waiter] = []
```

FIFO — array sırası. `wakeNextWaiterIfPossible` her `release` sonrası çağrılır; waiter'ları sırayla kontrol eder, kaynak müsaitse `continuation.resume()` ile uyandırır. Bir release birden çok waiter'ı (farklı resources kümeleri) uyandırabilir.

### `PointerControl` entegrasyonu

`PointerControl.click` ve `PointerControl.typeText` `ToolArbiter.shared.with([.pointer])` ile sarıldı. Tüm tıklama serisi (double-click dahil) tek acquire altında — paralel subagent araya giremez. Yazma serisi de aynı; yarı-yazılı string yarışı engellendi.

`PixelComputerUse` artık `PixelCore`'a depend ediyor (önceden hiç dep yoktu).

## Alternatives considered

- **Process-wide single global lock** (semaphore) — paralel hiçbir tool çalışmaz, single-agent'ta bile overhead.
- **OS-level lock (flock/lockf)** — process-içi paralel subagent için faydası yok; cross-process da pixel'in tek process modeliyle gereksiz.
- **Reentrant lock** — aynı task tekrar acquire ederse bekler mi? Faz 1'de YOK; gerekirse `(resources, taskID)` keyed cache eklenir (Faz 3).

## Consequences

**Olumlu:**
- Computer Use paralel subagent senaryosunda deterministic.
- `fileWrite(path:)` farklı path'ler paralel — dual-agent edit yapmak istediğinde de skalalanır.
- Single-agent MVP'de overhead pratik olarak sıfır (acquire her zaman anında döner; lock dict'i boş).
- Observability — `currentlyLocked()` / `waiterCount()` test ve ileride UI'da "Secondary kaynağı bekliyor" göstergesi için kullanılabilir.

**Olumsuz:**
- `ToolArbiter.shared` singleton (ADR-0009 istisnası). Test'lerde her test kendi `ToolArbiter()` instance'ı kullanır (DI mümkün) — gerçek `shared` sadece üretim entegrasyonunda.
- FIFO waiter array'i çok yüksek yarış senaryolarında O(n) — tipik kullanımda <5 waiter, sorun değil. 100+ paralel waiter olursa heap-backed priority queue'ya geçiş düşünülür.

## References

- [ADR-0005 — ToolArbiter resource mutex (orijinal tasarım)](0005-toolarbiter-resource-mutex.md)
- [ADR-0009 — Dependency injection over singletons](0009-dependency-injection-over-singletons.md) (istisna gerekçesi)
- [ADR-0026 — PixelComputerUse](0026-pixel-computer-use.md) (ilk müşteri)
- [`Sources/PixelCore/ToolArbiter.swift`](../../Sources/PixelCore/ToolArbiter.swift)
- [`Sources/PixelComputerUse/PointerControl.swift`](../../Sources/PixelComputerUse/PointerControl.swift)
- [`Tests/PixelCoreTests/ToolArbiterTests.swift`](../../Tests/PixelCoreTests/ToolArbiterTests.swift)
