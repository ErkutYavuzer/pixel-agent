# ADR-0030: Window Content-Area Screenshot Crop (Faz 3c)

**Status:** Accepted (Faz 3c landed)
**Date:** 2026-05-23
**Tags:** computer-use, screenshot, screencapturekit

## Context

[ADR-0026](0026-pixel-computer-use.md) Faz 1+2'de `ScreenshotTarget.window(bundleID:)` ile bir uygulamanın frontmost penceresini yakalayabiliyorduk. Eksiklik: capture **titlebar dahil**. Caller LLM bir text alanı veya buton aramak için `ui_screenshot` çekiyor ama görüntünün ilk 28-72pt'sinde her zaman aynı pencere chrome'u var (titlebar + opsiyonel toolbar). Vision model bunu her seferinde "boş gürültü" olarak süzmek zorunda — token israfı + dikkat dağılması.

[ADR-0029](0029-modifier-flags-and-ime.md) Faz 3b'de control side'ı (modifier-click + IME) tamamlandık. Faz 3c capture side'ında küçük ama pratik bir iyileştirme yapar.

## Decision

### Yeni case: `ScreenshotTarget.windowContent(bundleID:titlebarOffset:)`

```swift
public enum ScreenshotTarget: Sendable, Codable, Equatable {
    case allDisplays
    case activeDisplay
    case window(bundleID: String)
    /// Faz 3c: titlebar kesilmiş pencere.
    case windowContent(bundleID: String, titlebarOffset: Double)

    public static let defaultTitlebarOffset: Double = 28
}
```

`titlebarOffset` **logical points** cinsinden. Standart macOS titlebar 28pt; toolbar varsa caller 64-72pt verir; tab bar dahil edilecekse daha yüksek.

### Crop yaklaşımı — post-process `CGImage.cropping(to:)`

İki seçenek vardı:

1. **`SCStreamConfiguration.sourceRect`** — SCScreenshotManager'a sub-region söyle, capture dar gelsin. Daha az piksel; daha az memory.
2. **Full window capture + `CGImage.cropping(to:)` post-process** — yakalanan görüntüden bottom portion'ı kes.

**Seçim: (2).** Gerekçe:
- `sourceRect` retina display'lerde davranış zaman zaman beklenmedik (logical vs pixel space karışıklığı, gpu pipeline'ın çıktısı her macOS sürümünde aynı kalmıyor).
- `CGImage.cropping` deterministic: input bilinen, output bilinen.
- 28pt × 1600px = 56px crop'tan kazandığımız memory ihmal edilebilir (~50KB).
- Test edilebilir: `WindowCrop.computeCropRect(...)` saf fonksiyon — retina scale + offset matematiğini birim-testleyebiliriz; gerçek SCScreenshotManager çağrısına gerek yok.

### Saf helper: `WindowCrop`

```swift
enum WindowCrop {
    static func computeCropRect(
        imageWidth: Int,
        imageHeight: Int,
        windowWidth: Double,
        windowHeight: Double,
        titlebarOffsetPoints: Double
    ) -> CGRect?

    static func computeLogicalFrame(
        windowFrame: CGRect,
        titlebarOffsetPoints: Double
    ) -> CGRect
}
```

`computeCropRect` retina scale'ı `imageHeight / windowHeight` ile türetir; pixel offset = `titlebarOffsetPoints * scale`. Offset < 0 veya ≥ window height ise `nil` döner (caller fail-out yapar). `rounded()` ile pixel-tam değer.

`computeLogicalFrame` `ScreenshotResult.logicalFrame` metadata'sını günceller — caller "ekran koordinatlarıyla 200,228..." mantığıyla devam edebilir.

### `ScreenshotCapture.resolve` imzası güncellendi

Tuple artık 4-li: `(SCContentFilter, CGRect, String?, Double?)`. 4. eleman `titlebarOffset` — `.windowContent` dalında set; diğer durumlarda `nil` ve crop atlanır. `capture` fonksiyonu offset varsa post-process crop yapar; yoksa full image'i geçirir.

### MCP `ui_screenshot` schema extension

- `target` enum'una `window_content` eklendi (`active_display | all_displays | window | window_content`).
- `titlebar_offset: number` opsiyonel parametre (default 28).
- Description'a kullanım rehberi: "toolbar varsa 64-72 deneyin".

ControlSocketServer.uiScreenshot bridge'i string switch'ine `"window_content"` dalı eklendi. `titlebar_offset` JSON'da yoksa `ScreenshotTarget.defaultTitlebarOffset` (28) kullanılır.

### `ScreenshotCapture` resolve doğrulama

`.windowContent` dalı `titlebarOffset >= 0 && < window.frame.height` invariantı kontrol eder; ihlal varsa `screenshotFailed` fırlatır. Hata mesajı window yüksekliğini içerir → caller LLM hata diagnosing yapabilir.

## Alternatives considered

- **AX query ile gerçek content area frame'i.** Window'un AX children'ında AXToolbar / AXTabGroup gibi role'leri bulup content area'nın gerçek frame'ini hesaplamak mümkün. Reddedildi — uygulamadan uygulamaya değişken (SwiftUI vs AppKit vs Catalyst farkları), brittle. Hardcoded offset caller'a açık + override edilebilir → pragmatik.
- **`cropTop: Double` flag'i tüm target'lere ekle.** `.allDisplays` veya `.activeDisplay` için "ilk 28pt'yi at" pratik değil (menu bar zaten farklı koordinatta). Specific `.windowContent` case daha temiz.
- **`SCStreamConfiguration.sourceRect` kullan.** Yukarıda açıklandı — retina davranış belirsizliği + test edilebilirlik avantajı kaybı.
- **NSWindow.contentLayoutRect.** Sadece kendi process'imizin pencereleri için çalışıyor; başka app'ın penceresine erişim yok.
- **Set-of-Mark görsel annotation (Faz 4) ile birleştir.** Reddedildi: Faz 4 vision pipeline değişikliği gerektirir, ayrı tutmak commit'i odaklı yapar.

## Consequences

**Olumlu:**
- Vision-based LLM caller'lar titlebar token'larından kurtuluyor → daha az dikkat dağılması + daha düşük cost.
- Saf `WindowCrop` helper'ı 13 unit test'le kapsanır; retina + edge case'ler (0 offset, > height offset, negatif) deterministic.
- ScreenshotTarget Codable round-trip korundu — auto-derived encoding yeni case'i otomatik destekledi (Swift 5.5+ Codable enum).
- MCP `ui_screenshot` schema geriye uyumlu — eski caller'lar `window_content`'i bilmiyor olabilir; `window` halen çalışır.

**Olumsuz:**
- Hardcoded 28pt default — Apple titlebar yüksekliğini gelecekte değiştirebilir. Override parametresi olduğu için caller LLM uyum sağlar; OS bump'larında dokümantasyon güncelleme gerekebilir.
- Caller toolbar varlığını bilmiyorsa default 28pt yetersiz kalır (toolbar görünür kalır). UX: caller önce `ui_query` ile AXToolbar var mı bak, varsa offset'i yükselt. Faz 4'te otomatik AX-based offset hesabı düşünülecek.

## Plan (iterative)

- **Faz 3c ✓** (bu commit, v0.2.15): `ScreenshotTarget.windowContent`, `WindowCrop` saf helper, `ScreenshotCapture` post-process crop, MCP schema extension, 20 yeni test (13 WindowCrop + 7 ScreenshotTarget).
- **Faz 4:** Set-of-Mark visual annotation (`ui_screenshot(annotate: true)` → grid + per-element ID overlay; vision model "tıkla #12" diyebilir).
- **Faz 5 (ileride):** AX-based otomatik titlebar/toolbar offset (`windowContentAuto(bundleID:)`).

## References

- [`Sources/PixelComputerUse/UITypes.swift`](../../Sources/PixelComputerUse/UITypes.swift) (`ScreenshotTarget.windowContent`, `defaultTitlebarOffset`)
- [`Sources/PixelComputerUse/WindowCrop.swift`](../../Sources/PixelComputerUse/WindowCrop.swift) (saf helper)
- [`Sources/PixelComputerUse/ScreenshotCapture.swift`](../../Sources/PixelComputerUse/ScreenshotCapture.swift) (`resolve` + capture pipeline)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) (`uiScreenshot` schema)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (`uiScreenshot` bridge handler)
- [`Tests/PixelComputerUseTests/WindowCropTests.swift`](../../Tests/PixelComputerUseTests/WindowCropTests.swift) (13 test)
- [`Tests/PixelComputerUseTests/ScreenshotTargetTests.swift`](../../Tests/PixelComputerUseTests/ScreenshotTargetTests.swift) (7 test)
- [ADR-0026 — PixelComputerUse Faz 1+2](0026-pixel-computer-use.md)
- [ADR-0028 — Chained Query DSL + opaqueID Re-Resolve (Faz 3a)](0028-chained-query-and-opaque-id.md)
- [ADR-0029 — Modifier Flags + IME-Aware Text Injection (Faz 3b)](0029-modifier-flags-and-ime.md)
- [Apple — SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
- [Apple — CGImage.cropping(to:)](https://developer.apple.com/documentation/coregraphics/cgimage/1454683-cropping)
