# ADR-0007: Test Isolation — MockBackend + TaskLocal Scoping

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** testing, concurrency

## Context

LLM API'lar test ortamında flaky (network), pahalı (token cost) ve yavaştır. Integration test'ler yine de orchestration mantığını kanıtlamalı. Aynı zamanda test'ler birbirinden izole olmalı — bir test'in TaskLocal değişimi sonraki test'i etkilememeli.

## Decision

İki ayağı olan strateji:

1. **`MockChatBackend`** — `ChatBackend` protokolünün test implementasyonu. Canned response veya programmable behavior (`whenAsked("...").respond("...")`). Network çağırmaz.
2. **TaskLocal scoping test'te explicit** — Test'ler `withValue` block'u içinde çalışır:

```swift
func testPlanModeBlocksWriteTools() async {
    await ToolSchemas.$planModeAllowlist.withValue(["read_file"]) {
        // test body — write_file çağrısı throws
    }
}
```

## Alternatives considered

- **Real API + recording (VCR-style)** — fixture maintenance büyük; provider response formatı değiştiğinde tüm recording güncellenmeli.
- **Real API + skip-on-CI** — local'de geçer CI'da geçmez; flaky güven azaltır.
- **Constructor injection (her test'e backend pass et)** — boilerplate yoğun; tool dispatch zaten TaskLocal kullanıyor, simetri bozulur.

## Consequences

**Positive**
- Hermetic: network yok, paralel test güvenli.
- Deterministic: mock response sabit, seed gerektiren randomness yok.
- Hızlı: 7 test 0.003 saniyede geçti (foundation seviyesinde).
- Coverage gerçek: orchestration mantığı (dispatch, arbiter, allowlist) test ediliyor.

**Negative / tradeoffs**
- Mock invariant'ları manuel maintain (gerçek API davranışından sapabilir).
- Integration smoke test (real API, az sayıda, manual veya scheduled CI job) yine de gerekli.

## Lessons from pixel-agent2

v2'de 441 test çoğunlukla `MockChatBackend` + TaskLocal scoping üzerine kuruldu. Test suite ~7.5 saniyede geçti — hızlı feedback döngüsü TDD'ye fiilen olanak sağladı. 2 pre-existing live-voice fail vardı; bunlar gerçek API gerektiren testlerdi ve flakiness sebebi oldu.

## References

- [Swift Testing](https://developer.apple.com/xcode/swift-testing/) (gelecekte XCTest yerine geçebilir)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#karar-10)
