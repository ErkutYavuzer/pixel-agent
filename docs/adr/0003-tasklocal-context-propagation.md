# ADR-0003: TaskLocal Context Propagation

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** concurrency, architecture

## Context

Tool dispatch zincirinde context bilgisi taşımak gerekir: hangi agent çalışıyor (primary/secondary), subagent context'i var mı (UUID + depth), plan mode aktif mi, tool allowlist nedir. Bu bilgi çağrı ağacı boyunca yayılmalı ama her fonksiyon imzasına parametre olarak eklenmemeli.

## Decision

Swift `@TaskLocal` static property'ler kullanılır:

```swift
enum ToolDispatcher {
    @TaskLocal static var currentAgent: AgentID = .primary
    @TaskLocal static var currentSubagentID: UUID?
    @TaskLocal static var currentSubagentDepth: Int = 0
}

enum ToolSchemas {
    @TaskLocal static var planModeAllowlist: Set<String>?
    @TaskLocal static var subagentToolAllowlist: Set<String>?
}
```

Context değişimi yalnızca `withValue(_:operation:)` scope'unda gerçekleşir. Global mutable state veya manuel parameter chain yok.

## Alternatives considered

- **Global dictionary + lock** — thread-safe wrap gerekir, race condition riski, test izolasyonu zayıf.
- **Dependency injection parameter chain** — her tool fonksiyonu `Context` parametresi alır; boilerplate yoğun, refactor zor.
- **SwiftUI Environment / ObservableObject** — Sadece SwiftUI çağrı zinciri için çalışır; tool dispatch SwiftUI dışında.

## Consequences

**Positive**
- Concurrency-native: `Task` ağacında otomatik propagate.
- Test izolasyonu: her test kendi `withValue` scope'unda; global state'e dokunma yok.
- Task cancellation → context otomatik temizlenir.
- MainActor sınırı ile uyumlu.

**Negative / tradeoffs**
- Pattern öğrenme eğrisi (Swift Concurrency'ye yeni gelenler için).
- Debugging: stack trace'te TaskLocal değerleri görünmez; `print(ToolDispatcher.currentAgent)` ile kontrol gerek.

## Lessons from pixel-agent2

v2'de TaskLocal scoping ile dual-agent (primary + secondary peer) stack izolasyonu temiz oldu. Paralel iki agent kendi konteyniyle aynı tool fonksiyonunu çağırabildi, birbirinin context'ini etkilemedi. Subagent depth limiti de aynı mekanizmayla enforced edildi.

## References

- [SE-0311 TaskLocal](https://github.com/apple/swift-evolution/blob/main/proposals/0311-task-locals.md)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-1)
