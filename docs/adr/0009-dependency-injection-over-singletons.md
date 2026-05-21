# ADR-0009: Dependency Injection Over Singletons

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, testing, anti-pattern-prevention

## Context

`ChatBackend`, `ToolDispatcher`, `MemoryStore`, `RemoteRouter` gibi servisler birden çok yerden çağrılır. Klasik macOS pattern bunları `static let shared` singleton yapar — kolay erişim, ama test'te swap edilemez ve global mutable state üretir.

## Decision

`shared` singleton pattern yok. Composition root `PixelMacApp` servisleri instantiate eder ve child'a init parametresi veya `@Environment` ile geçirir:

```swift
@main
struct PixelMacApp: App {
    @State private var backend: any ChatBackend = AnthropicBackend()
    @State private var memory: MemoryStore = .init()

    var body: some Scene {
        WindowGroup {
            ChatView(backend: backend, memory: memory)
        }
    }
}
```

Tek istisna: `ToolArbiter.shared` (actor) — gerçek anlamda paylaşılan fiziksel kaynak mutex'i; bu özelde tek instance gerek (ADR-0005). Diğer her şey injected.

## Alternatives considered

- **Global singleton (`static let shared`)** — kolay ama testte swap edilemez; v2'nin erken versiyonlarında yapıldı, sonra refactor edildi.
- **Service locator pattern** — runtime lookup, type-safety zayıf.
- **Mass mock framework** — Swift'te Mockito-benzeri yok; manual mock zaten temiz.

## Consequences

**Positive**
- Test'te servis swap tek satır (`MockChatBackend()` inject).
- Lifecycle controlled — kim oluşturdu, kim temizliyor net.
- Composition root tek yerde — tüm bağımlılık grafiği tek dosyadan okunur.

**Negative / tradeoffs**
- Composition root büyüyebilir (8-12 servis × dependency).
- SwiftUI `@Environment` propagation ezbere bilgi gerektirir.

## Lessons from pixel-agent2

v2 erken sürümünde global backend = test imkânsızdı. Sonra `AppDelegate.backend` property'ye taşındı, ama AppDelegate kendisi singleton-benzeri kaldı (NSApplication.shared.delegate). v3'te bu zincir tamamen kırılıyor: SwiftUI App + injection.

## References

- [SwiftUI Environment](https://developer.apple.com/documentation/swiftui/environment)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md#anti-pattern-2)
