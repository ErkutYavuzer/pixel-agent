# ADR-0031: Set-of-Mark Visual Annotation (PixelComputerUse Faz 4)

**Status:** Accepted (Faz 4 landed)
**Date:** 2026-05-23
**Tags:** computer-use, vision, screencapturekit, mcp

## Context

[ADR-0026](0026-pixel-computer-use.md) Faz 1+2 + [ADR-0028](0028-chained-query-and-opaque-id.md) Faz 3a + [ADR-0029](0029-modifier-flags-and-ime.md) Faz 3b + [ADR-0030](0030-window-content-crop.md) Faz 3c ile PixelComputerUse'un **AX-side** (query, click, type, screenshot) yüzeyi tamamlandı. Geriye kalan büyük UX boşluğu: **vision model + koordinat eşleştirmesi**.

Bugünkü tipik caller LLM workflow'u:
1. `ui_screenshot(target=window_content)` → PNG döndürür.
2. Vision model PNG'de "Sign In" butonunu görür, koordinatları **tahmin etmesi** gerekiyor (örn. "yaklaşık (340, 220)").
3. `ui_click({ role: 'AXButton', title: 'Sign In' })` — title biliniyorsa OK; ama hidden butona, ikon-only butona, veya generic role'lere ulaşılamıyor.

[Set-of-Mark paper'ı](https://arxiv.org/abs/2310.11441) bu boşluğu visual ID overlay'le kapatır: her UI element'i bir numaralı badge ile işaretleyip vision model'a "tıkla #5" sorduruyorsun; caller bu ID'yi gerçek element'e map ediyor. GPT-4V / Claude vision model'leri bu paradigmada 25-40 puan accuracy artışı gösterdi.

pixel-agent için ek faydası: caller LLM ekrandaki **koordinatları okumak zorunda değil** — ID → element mapping deterministik (ui_query çıktısı).

## Decision

### Yeni tip: `SoMMark`

```swift
public struct SoMMark: Sendable, Codable, Equatable, Hashable {
    public let id: String              // 1-bazlı: "1", "2", ...
    public let element: UIElement      // ui_query çıktısının birebir kopyası
    public let frameInImage: CGRectBox // annotated PNG'deki pixel rect
}
```

`UITypes.swift` içinde — diğer Set-of-Mark tipleri ileride buraya eklenebilir.

### `ScreenshotResult.marks: [SoMMark]`

Annotate yapılmadıysa boş array. JSON encode'da her zaman yazılır. Decode tarafında `decodeIfPresent ?? []` — v0.2.15 ve öncesi JSON'lar geriye uyumlu.

### Saf helper: `MarkLayout.computeMarkRect`

```swift
enum MarkLayout {
    static func computeMarkRect(
        elementFrame: CGRect,        // AX top-left screen-global, logical points
        imageScreenOrigin: CGPoint,  // image bölgesinin screen-global origin'i
        imageLogicalSize: CGSize,    // bölge logical points
        imagePixelSize: CGSize       // image fiili pixel (retina dahil)
    ) -> CGRect?
}
```

Element bölgenin **tamamen dışındaysa nil** (off-screen filter); kısmi overlap rect olduğu gibi döner (CG context clip'ler). Sıfır-boyutlu element nil. Retina scale = `imagePixelSize / imageLogicalSize`. Konvansiyon top-left.

ScreenCaptureKit ve AppKit bağımsız → 13 unit-test ile (retina 1x/2x/3x, off-screen tüm yönler, kısmi overlap, dejenere boyut) kapsanır.

### `SoMRenderer.annotate`

```swift
enum SoMRenderer {
    static func annotate(
        image: CGImage,
        elements: [UIElement],
        imageScreenOrigin: CGPoint,
        imageLogicalSize: CGSize
    ) throws -> (CGImage, [SoMMark])
}
```

Akış:
1. Her element için `MarkLayout.computeMarkRect` → off-screen filtre + pixel rect.
2. Bitmap CGContext oluştur, CTM flip (translate + scaleBy y:-1) → top-left convention.
3. Base image'i context'e çiz.
4. Her görünür element için:
   - 4pt stroke outline (palette'ten döngüsel renk)
   - Sol-üst köşede dolu daire badge (36×36)
   - Badge ortasında beyaz bold 20pt numara (NSAttributedString.draw via NSGraphicsContext flipped:true)
5. `context.makeImage()` → annotated PNG hammadde.

**Renumbering after filter:** off-screen element atlandıktan sonra kalan element'ler 1-bazlı sıralı (1, 2, 3) ID alır. Vision model'a temiz görünür; caller orijinal element'e `SoMMark.element` üzerinden erişir.

**Palette:** 5 renk × 0.9 alpha (kırmızı, mavi, yeşil, turuncu, mor). Modulo ile dönüşümlü. Mark count > 5'te tekrar başlar — vision model rengi değil **ID'yi** okur, renk sadece visual ayrıştırma için.

### `ScreenshotCapture.capture(target:annotating:)` extension

`elements` opsiyonel parametre (default `[]`). Dolu ise post-crop sonrası `SoMRenderer.annotate` çağrılır; `ScreenshotResult.marks` doldurulur. Boş ise sıfır overhead → eski caller'lar etkilenmez.

`PixelComputerUse.screenshot(of:annotating:)` aynı imzayı dışa yansıtır.

### MCP `ui_screenshot` schema extension

```json
{
  "elements": [
    { "role": "AXButton", "title": "Sign In", "frame": { ... }, "opaque_id": "..." },
    { "role": "AXLink", "title": "Cancel", "frame": { ... }, ... }
  ]
}
```

JSON shape: `ui_query` çıktısının birebir aynı. Caller önce `ui_query` çağırır, sonucu yapıştırır.

Response payload'a yeni `marks` array eklendi:

```json
{
  "format": "png", ...,
  "marks": [
    { "id": "1", "element": { ... }, "frame_in_image": { x, y, width, height } },
    ...
  ]
}
```

`ControlSocketServer.decodeUIElement` helper'ı yeni — `JSONValue → UIElement` (snake_case → camelCase otomatik).

### Caller workflow (recommended)

```
1. ui_query({ role: 'AXButton', bundle_id: 'com.app.foo' }) → [10 element]
2. ui_screenshot({
     target: 'window_content',
     bundle_id: 'com.app.foo',
     elements: <ui_query sonucu>
   }) → { png_base64, marks: [...] }
3. Vision model image + marks listesi okur → "tıkla #7"
4. ui_click({ query: { identifier: marks[6].element.identifier } })
```

Caller'ın opaqueID'yi koruması ve `ui_resolve` ile re-verify etmesi de mümkün — UI hızlı değişiyorsa Faz 3a path-walk fallback'ı devrede.

## Alternatives considered

- **Otomatik element keşfi (caller hiç bir şey vermeden).** Vision model "tüm tıklanabilir element'leri bul" deyince renderer kendisi `ui_query(role: '*')` yapar. Reddedildi: caller ne istediğini bilir; auto-discovery cluttered PNG üretir; bir Faz 5 convenience layer eklenebilir.
- **Numbered overlay yerine renkli border + role legend.** "Bütün AXButton'lar yeşil, bütün AXLink'ler mor" — vision model role'ü görebiliyor ama "şu üçüncü yeşil olan" demek 1-bazlı ID'den daha az kesin.
- **`SCStreamConfiguration.sourceRect` ile pre-crop + draw.** Reddedildi — [ADR-0030](0030-window-content-crop.md)'da açıklandığı gibi sourceRect retina davranışında belirsiz; post-process daha test edilebilir.
- **CoreText kullanmak (NSAttributedString yerine).** Daha düşük seviyeli ama AppKit bağımlılığını kaldırmaz (NSGraphicsContext zaten gerekli). Karmaşık glyph yerleşimi için Faz 5+ bakılabilir.
- **Mark frame_in_image'i atla.** Vision model "tıkla #5" deyince ID'ye bakıyor; pixel rect ham koordinat ihtiyacı sadece advanced workflow (örn. caller PNG'yi başka bir tool'a göndermek istiyor). Verilmesi ucuz, kaldırmak future-proof değil — eklendi.

## Consequences

**Olumlu:**
- Vision-based caller LLM accuracy boost (paper: GPT-4V 25-40 puan).
- ID → element mapping deterministik; vision model koordinat tahminine girmiyor.
- Off-screen element renumbering vision model'a temiz görünür.
- `MarkLayout` saf fonksiyonu 13 test'le kapsanmış; retina/coordinate matematik bug'ı önceden yakalanır.
- Schema backward-compat — `marks` eski caller için JSON'da fazlalık olarak gelir, ignore edilir.

**Olumsuz:**
- Renderer AppKit bağımlı (NSGraphicsContext + NSAttributedString). iOS no-op stub'a düşüyor — Faz 5+ Core Graphics-only text rendering düşünülebilir. Ama PixelComputerUse zaten macOS-only.
- 4pt outline + 36px badge "default retina" için iyi; küçük image'da büyük görünür, vision model sıkışma yaşayabilir. Caller şu an override edemiyor — Faz 5+ `SoMOptions` parametresi eklenebilir.
- Aynı renk farklı element'lerde tekrar — visual confusion potansiyeli (ama ID benzersiz). Vision model ID'yi okuyabildiği sürece sorun değil; deneysel doğrulanacak.

## Plan (iterative)

- **Faz 4 ✓** (bu commit, v0.2.16): `SoMMark` + `MarkLayout` + `SoMRenderer` + `ScreenshotResult.marks` + `ScreenshotCapture.capture(annotating:)` + `PixelComputerUse.screenshot(annotating:)` + MCP `ui_screenshot` schema extension + 19 yeni test (13 MarkLayout + 6 SoMRenderer).
- **Faz 5:** `SoMOptions` (badge size, outline width, palette override); AX-based otomatik element keşfi (`annotateInteractive: true`); content-aware badge yerleşimi (element küçükse dış kenar).
- **İleride:** SoM IDs `ui_click_id` tool'una; renderer'ı iOS-uyumlu hale getir (CoreText + Core Graphics-only).

## References

- [`Sources/PixelComputerUse/UITypes.swift`](../../Sources/PixelComputerUse/UITypes.swift) (`SoMMark` struct, `ScreenshotResult.marks`)
- [`Sources/PixelComputerUse/MarkLayout.swift`](../../Sources/PixelComputerUse/MarkLayout.swift) (saf helper)
- [`Sources/PixelComputerUse/SoMRenderer.swift`](../../Sources/PixelComputerUse/SoMRenderer.swift) (overlay drawing)
- [`Sources/PixelComputerUse/ScreenshotCapture.swift`](../../Sources/PixelComputerUse/ScreenshotCapture.swift) (`capture(target:annotating:)`)
- [`Sources/PixelComputerUse/PixelComputerUse.swift`](../../Sources/PixelComputerUse/PixelComputerUse.swift) (`screenshot(of:annotating:)`)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) (`uiScreenshot` schema `elements` parametresi)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (`decodeUIElement` + bridge handler)
- [`Tests/PixelComputerUseTests/MarkLayoutTests.swift`](../../Tests/PixelComputerUseTests/MarkLayoutTests.swift) (13 test)
- [`Tests/PixelComputerUseTests/SoMRendererTests.swift`](../../Tests/PixelComputerUseTests/SoMRendererTests.swift) (6 test)
- [Yang et al. 2023 — Set-of-Mark Prompting Unleashes Extraordinary Visual Grounding in GPT-4V](https://arxiv.org/abs/2310.11441)
- [ADR-0026 — PixelComputerUse Faz 1+2](0026-pixel-computer-use.md)
- [ADR-0028 — Chained Query DSL + opaqueID Re-Resolve](0028-chained-query-and-opaque-id.md)
- [ADR-0029 — Modifier Flags + IME-Aware Text](0029-modifier-flags-and-ime.md)
- [ADR-0030 — Window Content-Area Screenshot Crop](0030-window-content-crop.md)
