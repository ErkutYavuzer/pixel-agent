# ADR-0001: Modular SPM Monorepo

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, build-system

## Context

`pixel-agent` birden çok bağımsız alt-sistem barındırıyor: chat orchestration, tool dispatch, memory storage, mascot rendering, remote control, UI. Tek bir target altında yığılırsa hızla "god class" eğilimi ortaya çıkar; ayrı repolar ise kontrat senkronizasyonunu zorlaştırır (v2'den bilinen acı).

## Decision

Swift Package Manager kullanan tek bir monorepo. 6 library + 1 executable target:

- `PixelCore` — protokol, envelope, TaskLocal primitives
- `PixelBackends` — LLM provider implementasyonları
- `PixelTools` — ToolDispatcher + ToolArbiter
- `PixelMemory` — JSONL store
- `PixelMascot` — sprite render
- `PixelRemote` — WebSocket envelope (Mac+iOS paylaşır)
- `PixelMacApp` (executable) — composition root

Her modülün kendi `XCTest` target'ı vardır. Bağımlılıklar tek yönlüdür: hepsi `PixelCore`'a doğru.

## Alternatives considered

- **Tek hedefli monolithic SPM** — kısa vadede daha basit ama bağımlılık disiplinini zorlamaz; v2'de yapılmış ve "AppDelegate god class" üretmiştir.
- **Cocoa framework projeleri** — ağır Xcode project setup, modül başına `.xcodeproj`, CI'da yavaş.
- **Birden çok repo (multi-repo)** — kontrat değişiminde cross-repo sync borcu (v2 → v2-remote arası 1100 satır kod beklemek zorunda kaldı).

## Consequences

**Positive**
- Modül arası bağımlılık döngüsü compile-time bloklanır.
- Test izolasyonu: her modülün test target'ı kendi sembollerine erişir.
- iOS app ileride aynı SPM modüllerini (`PixelCore`, `PixelRemote`) import edebilir.

**Negative / tradeoffs**
- İlk hafta için fazla iskelet hissi verir.
- `Package.swift` büyüdükçe okunması zorlaşır (ileride `Package@swift-6.0.swift` segmentasyonu düşünülebilir).

## Lessons from pixel-agent2

v2'de 246 dosya tek target altında toplandı; `AppDelegate.swift` 1463 satıra çıktı + 10 extension. Refactor borcu sprint 4'e ertelendi ve henüz ödenmedi. Bu modüler yapı, o borca yapısal olarak izin vermiyor.

## References

- [Swift Package Manager docs](https://www.swift.org/documentation/package-manager/)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md) — v2 öğrenmeleri
