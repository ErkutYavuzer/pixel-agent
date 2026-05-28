# ADR-0034: ProactiveEngine — Trigger-Based Passive UX

**Status:** Accepted (Sprint 38-40 landed; v0.2.65 / v0.2.66 / v0.2.67)
**Date:** 2026-05-26
**Tags:** proactive, triggers, notifications, accessibility, calendar, agent

## Context

v3'e kadar pixel tamamen **reaktif**ti: kullanıcı yazana kadar bekler. pixel-agent2'nin `ProactiveEngine`'i (idle/appChange/calendar/windowDwell/typedPause tetikleyiciler) "kişisel agent" hissinin önemli parçasıydı — kullanıcı bir süre boştaysa veya yeni bir app'e geçtiyse pixel proaktif öneri sunardı. Bu pattern v3'e modüler SPM mimarisinde indi.

İki tasarım kısıtı: (1) **spam olmamalı** (proaktif bildirim sık gelirse rahatsız edici); (2) **permission tier'ları net olmalı** (bazı tetikleyiciler Accessibility/Calendar izni ister, bazıları istemez — kullanıcı ne için izin verdiğini bilmeli).

## Decision

### Mimari — orchestrator + detector'lar + gating

`Sources/PixelMacApp/Proactive/` altında:

```
ProactiveEngine (actor) — start/stop, gating chain, delivery
  ├─ Detector'lar (her biri actor, kendi polling/observer'ı):
  │    ├─ IdleDetector        (CGEventSource secondsSinceLastEvent, 15dk)   — permission YOK
  │    ├─ AppChangeObserver   (NSWorkspace didActivate, 60s debounce)        — permission YOK
  │    ├─ TypedPauseDetector  (CGEventSource keyDown polling, 8-30s pause)   — permission YOK
  │    ├─ WindowDwellDetector (AXUIElement title polling)                    — Accessibility (yoksa downgrade)
  │    └─ CalendarEventDetector (EKEventStore, 3-10dk fire window)           — Calendar
  └─ Gating: SuppressionStore → ProactiveRateLimiter → SystemNotifications.post
```

- **`ProactiveTrigger`** (enum) + `TriggerKind` 5 case (idle / appChange / typedPause / windowDwell / upcomingEvent).
- **`PermissionRequirement`** (enum: `.none` / `.accessibility` / `.calendar`) — Settings UI badge için her trigger'ın iznini deklare eder.

### Gating chain (spam önleme)

Her tetikleyici delivery'den önce iki kapıdan geçer:
1. **`SuppressionStore`** (struct) — kind-level (kullanıcı "idle bildirimleri kapat") + bundle-level (kullanıcı "bu app'te sus") UserDefaults persist.
2. **`ProactiveRateLimiter`** (struct) — global cooldown (300s default) + per-kind override + Date injection (test edilebilir).

### Permission stratejisi (Tier 1 vs Tier 2)

- **Tier 1 (Sprint 38, permission YOK):** idle + appChange. CGEventSource ve NSWorkspace public API, izin gerektirmez → onboarding sürtünmesi sıfır, MVP hemen değerli.
- **Tier 2 (Sprint 39, permission-aware):** typedPause (yine permission YOK — CGEventSource keyDown public), windowDwell (Accessibility; yoksa per-bundle title-less downgrade), upcomingEvent (Calendar `requestAccess`). Settings "Proaktif" tab'da per-kind permission badge (✓/⚠) + System Settings deep-link.

### Notification handoff (Sprint 40)

Sprint 38-39'da notification tap'i muğlaktı (sadece app aktivasyonu). Sprint 40 trigger-spesifik hazır prompt'la ChatView composer'ını otomatik doldurur:
- **`ProactivePromptComposer`** (enum, saf) — 5 trigger için Turkish first-person user-voice prompt.
- **`ProactiveTrigger.userInfoPayload()`** + `init?(userInfoPayload:)` — `UNNotification.userInfo` Sendable dict round-trip.
- **`NotificationActionDispatcher`** (`UNUserNotificationCenterDelegate`) — didReceive tap → decode trigger → compose prompt → `ChatViewModel.injectDraft` broadcast.
- **Confirm-first UX** — prompt composer'a yazılır, **auto-send YOK**; kullanıcı kontrolünde kalır.

## Alternatives considered

- **Hepsini Tier 1'de toplamak (tüm tetikleyiciler permission'sız)** — windowDwell/calendar permission olmadan çalışamaz; ayırmak onboarding'i kademeli yapar (önce değerli no-permission MVP, sonra izin isteyen Tier 2).
- **Auto-send proaktif prompt** — kullanıcı kontrolünü elinden alır; "agent kendi kendine mesaj attı" güvensizliği. Confirm-first tercih edildi.
- **Tek mega-detector (her şeyi tek loop'ta polle)** — actor başına ayrı detector test isolation + lifecycle yönetimi için daha temiz; ADR-0009 DI ilkesiyle uyumlu.
- **Background daemon (app kapalıyken de proaktif)** — App Store sandbox + login item karmaşıklığı; MVP app-açık-iken yeterli.

## Consequences

**Olumlu:**
- pixel "kişisel agent" hissine yaklaşır; v2 paritesi (5 trigger) tamamlandı.
- Tier 1 permission-free → fresh install hemen proaktif değerli.
- Gating chain (suppression + rate limit) spam'i yapısal engeller; kullanıcı kontrolü Settings'te.
- Detector'lar actor + Date injection → hermetic test (43 + 30 + 30 test).

**Olumsuz:**
- macOS-specific kod artar (CGEventSource, NSWorkspace, AXUIElement, EKEventStore); iOS proactive Background App Refresh ile sınırlı (defer).
- Master toggle hot-reload yok — şu an değişiklik restart-required.
- CGEventSource polling enerji maliyeti (düşük ama sürekli); idle threshold ile amortize.
- Tier 2 detector'lar `MainActor` izolasyon hatasına duyarlı çıktı (v0.2.73 hot-fix: `MainActor.assumeIsolated` → `await MainActor.run` SIGTRAP).

## Plan (iterative)

- **Sprint 38 ✓** (v0.2.65): MVP — ProactiveEngine + IdleDetector + AppChangeObserver + SuppressionStore + ProactiveRateLimiter + Settings "Proaktif" tab.
- **Sprint 39 ✓** (v0.2.66): Tier 2 — TypedPauseDetector + WindowDwellDetector + CalendarEventDetector + PermissionRequirement + permission badge UI.
- **Sprint 40 ✓** (v0.2.67): Notification tap → ChatView handoff — ProactivePromptComposer + NotificationActionDispatcher + injectDraft. Confirm-first.
- **Hot-fix v0.2.73:** Tier 2 detector SIGTRAP (`MainActor.assumeIsolated` → `await MainActor.run`).
- **Defer (v0.2.68+):** Master toggle hot-reload; calendar event metadata inline (location → harita link, attendees); iOS proactive (Background App Refresh / calendar widget); dual-mode last-active sütun tracking.

## References

- [`Sources/PixelMacApp/Proactive/`](../../Sources/PixelMacApp/Proactive/) — ProactiveEngine, IdleDetector, AppChangeObserver, TypedPauseDetector, WindowDwellDetector, CalendarEventDetector, SuppressionStore, ProactiveRateLimiter, ProactiveTrigger, ProactivePromptComposer, NotificationActionDispatcher
- [ADR-0009 — Dependency Injection Over Singletons](0009-dependency-injection-over-singletons.md)
- [ADR-0011 — Native macOS Toolkit](0011-native-macos-toolkit.md) (SystemNotifications)
- [Apple — NSWorkspace notifications](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Apple — EventKit / EKEventStore](https://developer.apple.com/documentation/eventkit/ekeventstore)
