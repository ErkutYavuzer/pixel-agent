# ADR-0032: iOS Dashboard Remote Control Protocol

**Status:** Accepted (Faz 1 landed)
**Date:** 2026-05-23
**Tags:** ios, remote, envelope, dashboard

## Context

[ADR-0012](0012-remote-envelope-schema.md) ile `RemoteEnvelope` 4 tip ile sınırlıydı: `hello`, `userMessage`, `assistantMessage`, `assistantChunk`. iOS uygulaması bu protokolle yalnızca **iki yönlü text relay** yapıyordu — kullanıcı iPhone'dan yazıyor, Mac'teki CLI cevap chunk'lıyor, iOS render ediyor. iOS tarafı Mac'in **state'ini bilmiyordu**: hangi backend aktif, hangi model seçili, plan modu açık mı, hangi subagent çalışıyor, sistem yükü ne, ekran ne gösteriyor.

Kullanıcı `pixel-agent` Mac'in başında değilken telefonundan **dashboard**'a ihtiyaç duyuyor:
- Mac'te hangi CLI çalışıyor, hangi modelde — uzaktan değiştirme dahil.
- Plan modunu aç/kapat — iPhone'dan toggle.
- Çalışan subagent listesi + cancel.
- Aktif uygulama + CPU/RAM (ne yaptığını "hissetmek").
- Bir ekran resmi iste (vision-based debug için).

[ADR-0021](0021-lan-mode-bonjour.md) + [ADR-0023](0023-merge-transport-and-mac-wire-up.md) ile transport zaten LAN+Relay paralel; [ADR-0015](0015-ed25519-envelope-signing.md) ile her envelope imzalı. Eksik olan **mesaj tipleri**.

## Decision

### 4 yeni `EnvelopeType` case

```swift
public enum EnvelopeType: String, Codable, Sendable, CaseIterable {
    // ... mevcut: hello, error, userMessage, assistantMessage, assistantChunk
    case clientConfig        // iOS → Mac: backend/model/planMode değiştir
    case clientAction        // iOS → Mac: cancelSubagent, requestScreenshot, ...
    case hostStatus          // Mac → iOS: 3sn aralıkla snapshot (config + subagent + metrik)
    case screenshotPayload   // Mac → iOS: requestScreenshot cevabı (base64 JPEG)
}
```

Yön sözleşmesi sınıflandırma; transport seviyesinde fark yok (her iki taraf da gönderebilir, alıcı tip'e göre dispatch eder).

### 2 yeni payload struct

```swift
public struct SubagentStatusPayload: Codable, Sendable, Equatable {
    public let id: String
    public let prompt: String
    public let status: String        // "queued" | "running" | "completed" | ...
    public let partialOutput: String // streaming chunk akışından son snapshot
    public let startedAt: Double     // unix timestamp
}

public struct SystemMetricsPayload: Codable, Sendable, Equatable {
    public let cpuUsage: Double      // 0–100
    public let ramUsage: Double      // 0–100
    public let activeWindow: String  // NSWorkspace.frontmostApplication.localizedName
}
```

`SubagentStatus` enum yerine `String` — relay protokolünde semver-friendly: iOS yeni statusları unknown göstersin, eski cihazlar boyle bilmediği değerleri "Bilinmiyor" olarak render eder.

### `EnvelopePayload` genişlemesi (+10 opsiyonel alan)

```swift
public struct EnvelopePayload: Codable, Sendable, Equatable {
    // Mevcut: text, role, errorCode, errorMessage, metadata, publicKey
    // Yeni:
    public var selectedBackend: String?      // clientConfig + hostStatus
    public var selectedModel: String?
    public var planMode: Bool?
    public var actionType: String?           // clientAction: "cancelSubagent" | "requestScreenshot"
    public var targetID: String?             // clientAction: subagent ID vb.
    public var base64Image: String?          // screenshotPayload: JPEG base64
    public var availableBackends: [String]?  // hostStatus
    public var availableModels: [String: [String]]?
    public var activeSubagents: [SubagentStatusPayload]?
    public var systemMetrics: SystemMetricsPayload?
}
```

Tüm alanlar opsiyonel — bir envelope tipinde gereksiz alanlar boş kalır. Codable, eksik alanları sessizce `nil` decode eder; backward-compat sağlam.

### Factory metodları

```swift
RemoteEnvelope.clientConfig(backend:model:planMode:)
RemoteEnvelope.clientAction(type:targetID:)
RemoteEnvelope.hostStatus(selectedBackend:selectedModel:planMode:availableBackends:availableModels:activeSubagents:systemMetrics:)
RemoteEnvelope.screenshotPayload(base64Image:)
```

Caller'ın opsiyonel field'larla uğraşmasını engeller; `init` kullanan testler için ek.

### Mac dispatch ([PixelMacApp.swift:466+](../../Sources/PixelMacApp/PixelMacApp.swift))

`RemoteHost`'a iki callback bağlandı:

```swift
remoteHost.onClientConfigReceived = { backend, model, plan in
    guard let kind = CLIKind(rawValue: backend) else { return }
    self.selectedKind = kind
    self.planMode = plan
    self.setModel(model, for: kind)
}

remoteHost.onClientActionReceived = { [weak remoteHost] action, targetID in
    switch action {
    case "cancelSubagent": subagentManager.cancel(...)
    case "requestScreenshot":
        let png = try await ScreenshotCapture.capture(target: .activeDisplay)
        let jpeg = ImageEncoding.compressPNGToJPEG(data: png.pngData, quality: 0.5)
        await remoteHost?.sendScreenshot(base64Image: jpeg.base64EncodedString())
    default: break
    }
}
```

Ayrıca **3 saniye periyodik push** loop'u (`Task { while !Task.isCancelled { sleep(3s); sendHostStatus(...) } }`):
- Aktif uygulama: `NSWorkspace.shared.frontmostApplication?.localizedName`
- CPU: `SystemStats.shared.cpuUsagePercent()` — Mach `HOST_CPU_LOAD_INFO` iki snapshot delta'sı (ADR-0032 ile birlikte landed; öncesinde sahteydi)
- RAM: `SystemStats.memoryUsagePercent()` — Mach `mach_task_basic_info` resident size / physical
- Subagent list: `subagentManager.sessions.map { SubagentStatusPayload(...) }`

### iOS render ([ChatView.swift:13](../../ios/PixelAgentRemote/ChatView.swift:13))

`TabView` 3 sekme:
1. **Sohbet** — mevcut chat.
2. **Subagent'lar** — `SubagentsListSection` kartları, cancel butonu.
3. **Mac Paneli** — `MacPanelDashboardSection`:
   - `MetricGauge` × 2 (CPU + RAM)
   - Aktif uygulama capsule
   - Backend / Model `Picker` + Plan Mode `Toggle` → `session.updateConfig(...)` → `clientConfig` envelope
   - "Resim Al" butonu → `session.requestScreenshot()` → `clientAction("requestScreenshot")`
   - `ZoomableImageView` (UIScrollView wrapper) son screenshot için

`RemoteSession` `@Published` alanlar: `selectedBackend`, `selectedModel`, `planMode`, `availableBackends`, `availableModels`, `cpuUsage`, `ramUsage`, `activeWindow`, `activeSubagents`, `lastScreenshot`. `hostStatus` envelope geldiğinde main actor üzerinde set edilir.

### Image kodlama

PNG ham (Mac retina ekranda ~3-5 MB) → JPEG quality 0.5 (~300-800 KB). Base64 ile ~%33 inflation. Tek shot için kabul edilebilir; **continuous streaming Faz 2'de** delta + WebP düşünülecek.

## Alternatives considered

- **Tek generic `dashboardEvent` tipi + JSON payload.** Type-safety kaybı; iOS/Mac iki ucu da string-key parse etmek zorunda kalırdı. Reddedildi — Swift'in `Codable` ergonomi'si optional field'larda da yeterince temiz.
- **Ayrı HTTP REST API.** Mac'te ayrı bir HTTP listener, iOS HTTP client. Reddedildi: ed25519 envelope signing + LAN+Relay merge transport altyapısı zaten kurulmuş; ikinci bir kanal sign ve pairing'i tekrarlatırdı.
- **iOS polling (Mac'ten istenince hostStatus döner).** Reddedildi: telefon battery için push avantajlı; 3sn interval Mac'in elinde ölçeklenir.
- **`hostStatus`'ta delta-only push.** Mevcut sürüm full snapshot gönderiyor. Faz 2'de delta'ya geçilebilir; şu an payload küçük (~1-2 KB JSON, periyot 3sn = ~700 B/s — relay için ihmal).
- **`SubagentStatus` enum (string yerine).** Type-safe ama relay protokolünde semver-friendly değil — iOS yeni status'ları unknown göstersin. String tercih edildi.
- **EnvelopePayload yerine type-başına ayrı payload struct'ları.** `clientConfigPayload`, `hostStatusPayload`, ... Daha temiz ama mevcut `payload` field tek tip; ya enum'a çevirme refactor'u (büyük blast radius) ya da `EnvelopePayload` opsiyonel'lerle yaşamak. İkincisi seçildi — bir Faz 2 refactor adayı.

## Consequences

**Olumlu:**
- iOS uygulaması yalnız `ChatView` değil; tam bir uzak yönetim paneli.
- Mevcut transport/signing altyapısı dokunulmadı — yeni tipler aynı pipe'tan geçiyor.
- Backward-compat: eski iOS sürümleri yeni envelope tiplerini görmezden gelir (`EnvelopeType` `unknown` decode hatası vermesin diye Faz 2'de unknown case + fallback eklenecek; şu an `CaseIterable` strict).
- Faz 1 ile birlikte landed: gerçek CPU metric (ADR-0032 commit'i `SystemStats` actor + `host_statistics` ile sahte hesabı değiştirdi).

**Olumsuz:**
- `EnvelopePayload` artık 16 opsiyonel field'a sahip — "god struct" eğilimi. Bir Faz 2 sum-type refactor adayı.
- Strict `EnvelopeType` enum decode hatası verir bilinmeyen tip için → eski iOS sürümlerinde yeni tipler crash potansiyeli (şimdilik tek versiyon var; v0.3'e geçerken `unknown` fallback eklenmeli).
- iOS picker UI çift-yönlü update — kullanıcı iOS'tan değiştirir, sonra Mac'ten değiştirir, race olabilir. Şu an "son yazan kazanır"; Faz 2'de `version` field eklenebilir.
- 3sn periyodik push ~700 B/s relay traffic'i ekliyor; LAN'da önemsiz, Cloudflare relay'inde free-tier kullanımı düşünülmeli (`MergeTransport` aktif iken her iki transport'a da yazılıyor).

## Plan (iterative)

- **Faz 1 ✓** (bu ADR, v0.2.24 sonrası commit `8cd547e` + `522cad4` ardı sıra): 4 yeni envelope tipi, 2 payload struct, EnvelopePayload genişlemesi, Mac periyodik push, iOS TabView dashboard, requestScreenshot, cancelSubagent.
- **Faz 1.1 ✓** (bu ADR commit'i ile birlikte): `SystemStats` actor + Mach `HOST_CPU_LOAD_INFO` gerçek CPU; `ImageEncoding` ayrı dosya; eski sahte `getCPUUsage(activeSubagentCount:)` API'sinin silinmesi.
- **Faz 2:**
  - `EnvelopeType` `unknown` fallback case (forward-compat protokol revizyonu için).
  - `hostStatus` delta-only push (önceki snapshot'tan diff).
  - iOS `dispatchSubagent` (şu an sadece cancel; dispatch bir `clientAction("dispatchSubagent", targetID: prompt)` ekleyerek + Mac `subagentManager.dispatch(...)`).
  - Screenshot continuous mode (`clientAction("startScreenStream", targetID: fps)` + Mac periyodik `screenshotPayload`).
- **Faz 3:**
  - Payload sum-type refactor (`enum EnvelopePayload { case clientConfig(...); case hostStatus(...); ... }`) — Codable manuel encode/decode ama type-safe.
  - LAN'da WebP/HEIF screenshot encoding (relay'de base64 inflation kaçınılmaz, LAN'da binary frame).

## References

- [`Sources/PixelRemote/RemoteEnvelope.swift`](../../Sources/PixelRemote/RemoteEnvelope.swift) (`EnvelopeType` case'leri, `SubagentStatusPayload`, `SystemMetricsPayload`, `EnvelopePayload` field'ları, factory metodları)
- [`Sources/PixelRemote/RemoteHost.swift`](../../Sources/PixelRemote/RemoteHost.swift) (`onClientConfigReceived`, `onClientActionReceived`, `sendHostStatus`, `sendScreenshot`)
- [`Sources/PixelMacApp/PixelMacApp.swift`](../../Sources/PixelMacApp/PixelMacApp.swift) (`ChatHost` callback bağlantıları + 3sn push loop)
- [`Sources/PixelMacApp/SystemStats.swift`](../../Sources/PixelMacApp/SystemStats.swift) (actor + Mach `HOST_CPU_LOAD_INFO` + `memoryUsagePercent`)
- [`Sources/PixelMacApp/ImageEncoding.swift`](../../Sources/PixelMacApp/ImageEncoding.swift) (`compressPNGToJPEG`)
- [`ios/PixelAgentRemote/ChatView.swift`](../../ios/PixelAgentRemote/ChatView.swift) (`TabView`, `MacPanelDashboardSection`, `MetricGauge`, `ZoomableImageView`)
- [`ios/PixelAgentRemote/RemoteSession.swift`](../../ios/PixelAgentRemote/RemoteSession.swift) (`updateConfig`, `requestScreenshot`, `@Published` dashboard state)
- [`Tests/PixelRemoteTests/RemoteEnvelopeTests.swift`](../../Tests/PixelRemoteTests/RemoteEnvelopeTests.swift) (yeni envelope tipleri round-trip testleri)
- [`Tests/PixelMacAppTests/SystemStatsTests.swift`](../../Tests/PixelMacAppTests/SystemStatsTests.swift) (CPU/RAM hesap testleri)
- [ADR-0012 — Remote Envelope Schema](0012-remote-envelope-schema.md)
- [ADR-0015 — ed25519 Envelope Signing](0015-ed25519-envelope-signing.md)
- [ADR-0021 — LAN-Only Mode Faz 1 (PixelLAN)](0021-lan-mode-bonjour.md)
- [ADR-0023 — MergeTransport + Mac Wire-Up](0023-merge-transport-and-mac-wire-up.md)
