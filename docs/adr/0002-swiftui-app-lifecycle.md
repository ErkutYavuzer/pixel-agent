# ADR-0002: SwiftUI App Lifecycle (NSApplicationDelegate yok)

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, ui, anti-pattern-prevention

## Context

macOS uygulamaları historik olarak `NSApplicationDelegate` etrafında kuruldu. Bu sınıf, uygulama yaşam döngüsünün her parçasını çekmeye eğilimli — menu setup, window management, system event handling, drop handling — hızla god class olur. SwiftUI App protocol (macOS 11+) modern, declarative bir alternatif sunar.

## Decision

`@main struct PixelMacApp: SwiftUI.App` ana giriş. `NSApplicationDelegate` yok. Lifecycle eventleri için `@Environment(\.scenePhase)` + zaruri durumlarda `NSApplicationDelegateAdaptor` (sadece SwiftUI'nin doğal olarak karşılayamadığı hook için, küçük tutulmuş bir adapter).

## Alternatives considered

- **NSApplicationDelegate-first (legacy)** — v2 pattern; 1463 satırlık god class ürettiği için kasıtlı olarak kaçınılıyor.
- **Hibrit (SwiftUI App + büyük adapter)** — adapter yine god class olabilir; disiplinli tutulmazsa aynı sonuç.
- **Pure AppKit (NSApplication.shared.run)** — Swift Concurrency entegrasyonu zayıf, modern test imkânları sınırlı.

## Consequences

**Positive**
- Modern Swift Concurrency / MainActor uyumlu.
- Lifecycle declarative; test edilebilir scene state.
- "Tüm yollar AppDelegate'e çıkıyor" anti-pattern'i yapısal olarak engellenir.

**Negative / tradeoffs**
- Bazı macOS-only API hook'ları için (örn. `applicationShouldHandleReopen`) küçük bir adapter şart.
- SwiftUI App protokol macOS 11+ — eski sürüm desteği yok (platforms zaten `.macOS(.v14)`).

## Lessons from pixel-agent2

v2'de `AppDelegate` 11 extension'a bölünmesine rağmen (AutoResume, Backend, Drop, Lifecycle, Menu, RealtimeVoice, RemoteLAN, Slash, Telegram, Windows) hâlâ navigasyon kabusudur. Extension'lar yalnızca dosya bölmesidir; gerçek bağımsızlık yoktur — aynı state'i paylaşırlar. Modüller arası temiz arayüz yerine, "AppDelegate her şeyi bilir" eğilimi.

## References

- [SwiftUI App protocol](https://developer.apple.com/documentation/swiftui/app)
- ADR-0001 (modular SPM) — App lifecycle modüler kompozisyon ile birlikte çalışır
