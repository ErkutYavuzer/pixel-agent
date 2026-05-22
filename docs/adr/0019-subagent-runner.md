# ADR-0019: Subagent Runner — Ephemeral Budget'lı Tek-Turlu Çalıştırıcı

**Status:** Accepted (Faz 1 landed)
**Date:** 2026-05-22
**Tags:** orchestration, concurrency, budget

## Context

[v2'nin Sprint 3 işi](../architecture-decisions-from-v2.md) (13 dosya, "ephemeral runtime + budget actor + UI bridge") çoğunlukla iç tool dispatcher etrafında dönüyordu — claude'un Read/Edit/Bash tool'larını pixel-agent içinde execute etmek için. v3'te bu bağlamı kasıtlı bıraktık (ADR-0010, CLI subprocess'lere delegated).

Yine de "subagent dispatching" konsepti v3'te de değerli:
- Background fire-and-forget LLM job'ları (örn. "claude'a bu repo'yu özetlet, ben başka iş yaparken")
- v0.2.4'te eklenen MCP server tool olarak başka client'lara expose edilebilir orchestration ("claude-cli pixel-agent'a delegated bir Codex run'ı yaptırabilsin")
- Budget enforcement (kaçak runaway agent yok)
- TaskLocal context ile log/tracing tutarlılığı

Çözüm: standalone `PixelSubagent` library + `SubagentRunner` actor.

## Decision

### Sorumluluk sınırı

`SubagentRunner` **tek-turlu** çalıştırıcı: bir prompt → bir result. Multi-turn workflow chain'leri, MCP integration, UI background list **v0.3+ scope** olarak ertelendi. Faz 1 yalnızca library + tests.

### Budget modeli

İki sınır:
- `maxDuration: TimeInterval` — wallclock saniye. Aşıldığında stream cancel + `budgetExceeded(.duration, ...)`.
- `maxOutputBytes: Int?` — UTF-8 byte sayımı. Aşıldığında `budgetExceeded(.outputBytes, ...)`.

**Token sayma kasıtlı yok**: CLI subprocess'lerin token quota'sına bizim erişimimiz yok; her CLI kendi billing'ini yönetiyor. Wallclock + byte cap pratikte yeterli (deneyim: v2'de aynıydı).

Preset'ler: `Budget.default` (60s, sınırsız byte), `Budget.exploratory` (10s, 8 KB).

### Sonuç tipi

`SubagentResult` enum, 4 vaka:
- `completed(output:, durationSeconds:)`
- `budgetExceeded(reason:.duration|.outputBytes, partialOutput:, durationSeconds:)`
- `cancelled(partialOutput:, durationSeconds:)` — `Task.cancel()` ile
- `failed(error:, partialOutput:, durationSeconds:)` — backend exception

Her vaka `output` ve `durationSeconds` accessor'larıyla — partial çıktıyı her zaman erişilebilir kıldık (debugging için).

### Concurrency tasarımı

`withTaskGroup(of: SubagentResult.self)` ile **iki child task yarışır**:

1. **Worker**: backend stream'i tüketir, chunk'ları `OutputBuffer` actor'ında biriktirir, `done` ya da byte cap'te döner.
2. **Watchdog**: `Task.sleep(budget.maxDuration)` sonra `OutputBuffer.snapshot()` alıp `budgetExceeded(.duration, ...)` döner.

`group.next()` ilk biteni döner; `group.cancelAll()` diğerini durdurur. Worker cancel olunca `AsyncThrowingStream.onTermination` triggerlanır → backend Process subprocess kill (CLIBackend impl detail).

`OutputBuffer` shared mutable state için **actor** (data race yok). Hem worker hem watchdog `snapshot()` çağırabilir.

### TaskLocal propagation

`AgentContext.currentSubagentID` (PixelCore'a eklenen yeni TaskLocal) `SubagentRunner.run(...)` boyunca binding ile set edilir:

```swift
AgentContext.$currentSubagentID.withValue(id) { ... }
```

Backend / tool zincirinde kim sorgularsa öğrenir — log/tracing için root agent ile subagent ayrımı.

ADR-0003 (TaskLocal context propagation) bu kullanımın blueprint'i.

### Test stratejisi

`MockBackend` (test target-only) chunk array + chunk delay + endWithoutDone + throwAfter parametreleriyle aşağıdaki path'leri kapsar:
- `testCompletedHappyPath`
- `testBudgetExceededByDuration` (slow chunks)
- `testBudgetExceededByOutputBytes` (cap aşımı)
- `testFailedWhenBackendThrows`
- `testCompletesWhenStreamEndsWithoutDone` (CLI exit without .done)
- `testSubagentIDIsTaskLocalDuringRun` (TaskLocal binding doğrulaması)
- `testSubagentIDIsNilOutsideRun` (binding kapsamı)

Plus `BudgetTests` (4 test), `SubagentResultTests` (4 test) → toplam 15 yeni test.

## Consequences

**Olumlu:**
- Test edilebilir, izole library (`PixelSubagent` 4 dosya, 4 public type).
- v2'nin "ephemeral runtime" mantığı sadeleştirilmiş halde restored.
- Wallclock budget runaway agent koruması.
- TaskLocal subagentID — log/tracing context'i tutarlı.
- `withTaskGroup` ile worker + watchdog deterministic; race condition yok.
- v0.3'te MCP tool / UI integration için temel hazır.

**Olumsuz:**
- Token-level budget yok — sadece byte/duration. CLI provider'ın quota'sı bizim için opak.
- Stream "silent stuck" senaryosu (backend uzun süre tek chunk vermez): watchdog devreye girer, doğru davranır. Ama partial output watchdog snapshot'ı alındığında ne kadar geldiyse o kadar — race condition yok ama "tam o anda" değer döner.
- Multi-turn / chain workflow yok — sonraki ADR'de.

## Faz 2+ — gelecek (bu ADR'de değil)

- MCP tool: `dispatch_subagent(prompt, backend_kind, budget_seconds)` — claude-cli üzerinden orkestre etme.
- PixelMacApp UI: background subagent listesi (status indicator, cancel butonu, sonuç toast).
- Multi-turn `Workflow` API: birden çok `SubagentRunner.run` çağrısını seri/paralel bağlama, ara state geçişi.
- Subagent çıktısının `ConversationStore`'a ayrı dosyada arşivlenmesi.

## Alternatives

- **Token budget yerine wallclock**: CLI provider'ın token sayacına erişimimiz yok; wallclock pratikte yeterli (v2 deneyimi). Reddedildi.
- **`async let` ile worker + watchdog**: TaskGroup'tan basit ama `OutputBuffer` shared state için aynı actor gerekir; ek tasarım kazancı yok. TaskGroup tercih edildi (cancellation API'si daha açık).
- **Backend.send'i wraplayan generic timeout**: `withThrowingTaskGroup` + sleep yarışı genel pattern ama her tool için tekrar yazmak gerekir; `SubagentRunner` bu pattern'i tek noktada toplar.
- **Multi-turn'u Faz 1'e dahil et**: scope patlar. Single-turn → workflow chain Faz 2'de eklendiği zaman ABI break yok (yeni API method).

## References

- `Sources/PixelSubagent/Budget.swift`
- `Sources/PixelSubagent/SubagentResult.swift`
- `Sources/PixelSubagent/SubagentRunner.swift`
- `Sources/PixelCore/AgentContext.swift` (`currentSubagentID` TaskLocal)
- `Tests/PixelSubagentTests/` (15 test)
- [ADR-0003 TaskLocal context propagation](0003-tasklocal-context-propagation.md)
- [ADR-0010 CLI subprocess backend](0010-cli-subprocess-backend.md)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md) — v2'nin Sprint 3 referansı
