# ADR-0029: Modifier Flag Combinations + IME-Aware Text Injection (Faz 3b)

**Status:** Accepted (Faz 3b landed)
**Date:** 2026-05-23
**Tags:** computer-use, cgevent, ime, accessibility

## Context

[ADR-0026](0026-pixel-computer-use.md) PixelComputerUse Faz 1+2'de `PointerControl` minimum yüzeyle geldi: tek-buton sol-tıklama + per-scalar text injection. İki pratik eksik:

1. **Modifier-click yok.** ⌘-click yeni sekme açar (Safari), ⇧-click range select yapar (Finder), ⌃-click context menu çağırır. Caller LLM bu workflow'lara hâlâ ulaşamıyor.
2. **Multi-scalar grapheme bozuk.** "👋🏼" (wave + medium-light skin tone) **iki** Unicode scalar; eski kod her scalar için ayrı CGEvent keypress üretiyordu. Hedef text field iki ayrı emoji görüyor: 👋 ve 🏼. Aynı sorun aile emoji'leri (`👨‍👩‍👧`, ZWJ sequence) ve birleşik diakritik (`e\u{0301}` = "é") için de geçerli.

Faz 3b bu iki başlığı dar yüzeyle kapatır. ADR-0026'da listelenen "window-level screenshot crop (content-area)" maddesi titlebar height ölçümü AX query gerektirdiği için Faz 3c veya Faz 4 (Set-of-Mark) ile birlikte ele alınacak.

## Decision

### `ModifierFlags` OptionSet

`Sources/PixelComputerUse/PointerControl.swift`'te public OptionSet:

```swift
public struct ModifierFlags: OptionSet, Sendable, Codable, Hashable {
    public static let command = ModifierFlags(rawValue: 1 << 0)
    public static let option  = ModifierFlags(rawValue: 1 << 1)
    public static let shift   = ModifierFlags(rawValue: 1 << 2)
    public static let control = ModifierFlags(rawValue: 1 << 3)
}
```

`parse(_ names: [String])` static fonksiyonu **kanonik isim, alias ve glyph**'leri kabul eder:
- `command` / `cmd` / `⌘`
- `option` / `opt` / `alt` / `⌥`
- `shift` / `⇧`
- `control` / `ctrl` / `⌃`

Bilinmeyen anahtarlar **silently atlanır** — caller LLM "fn" gibi desteklenmeyen tuş yazarsa hata vermek yerine boş flag set'i dönülür. (fn ToolArbiter scope dışı; ayrı bir konu.)

`cgEventFlags: CGEventFlags` computed property `CGEvent.flags` set etmek için.

### `PointerControl.click(at:count:modifiers:)` extension

`modifiers` default `[]`; geriye uyumlu. Set ise `event.flags = modifiers.cgEventFlags` her mouseDown ve mouseUp için. Tek arbiter acquire altında — partial state yok.

### `PixelComputerUse.click(_ q:, count:, modifiers:)` façade extension

Yeni parametre downstream'e iletilir.

### IME-aware text injection — grapheme cluster grouping

`PointerControl.typeText` artık per-Character iterasyon yapar:

```swift
nonisolated static func unicodeChunks(for text: String) -> [[UInt16]] {
    text.map { Array(String($0).utf16) }
}
```

Her grapheme cluster tek `keyboardSetUnicodeString` çağrısı ile gönderilir. UTF-16 code unit dizisi olduğu gibi geçirilir; emoji surrogate pair, ZWJ sequence, skin-tone modifier, birleşik diakritik **tek keypress** olarak görünür.

`unicodeChunks(for:)` **nonisolated saf fonksiyon** — `@MainActor` enum içinde olmasına rağmen testlerden senkron çağrılabilir.

### MCP `ui_click` schema extension

`modifiers: [string]` opsiyonel parametre — enum: `command`, `option`, `shift`, `control`. ControlSocketServer.uiClick handler'ı `ModifierFlags.parse(names)` ile çevirir.

`ui_click` description'a "modifiers" kullanımı eklendi. Backward-compat — JSON'da `modifiers` yoksa boş set.

## Alternatives considered

- **`PointerControl.click(at:count:flags: CGEventFlags)` doğrudan CGEventFlags.** Reddedildi: `CGEventFlags` raw bit mask, caller'ın kafası karışır; OptionSet wrapper hem MCP serialize edilir hem test-friendly.
- **fn key dahil etmek.** fn modifier macOS'ta media keys için kullanılır; `CGEventFlags.maskSecondaryFn` mevcut ama tıklamada uygulamalar çoğunlukla beklemez. Reddedildi — gerek olunca eklenir.
- **Per-scalar typeText (eski davranış).** Reddedildi: emoji ve ZWJ üzerinde bozuk, kullanıcı görünür hatası var.
- **Compose text + tek `keyboardSetUnicodeString` çağrısı (tüm metni birleştir).** Reddedildi: çok uzun metinde tek pair MacOS'un IME pipeline'ında olağandışı davranabilir; ayrıca cancel logic'i (Task.isCancelled) per-character daha responsive. Mevcut grapheme-by-grapheme iyi denge.
- **Window content-area screenshot crop bu Faz'da.** Reddedildi: titlebar height için ya AX query (`AXContentArea` veya children frame analysis) ya da Cocoa private API gerek. Tek başına ufak değer; Set-of-Mark Faz 4 ile birlikte yapılır.

## Consequences

**Olumlu:**
- Caller LLM ⌘-click (yeni sekme), ⇧-click (range select), ⌃-click (context menu) yapabilir.
- Türkçe karakter, emoji (skin-tone + ZWJ + flag combinations), birleşik diakritik tek keypress — IME pipeline doğru görür.
- `ModifierFlags.parse` esnek input kabul ediyor — LLM "cmd" yazsa, glyph yazsa, lowercase/uppercase mix etse de aynı sonuç.
- Saf `unicodeChunks(for:)` helper'ı 13 grapheme cluster sınır test'iyle kapsanır; CGEvent enjeksiyonunu CI'da çalıştırmaya gerek yok.

**Olumsuz:**
- `ModifierFlags.parse` bilinmeyen anahtarları silent atlıyor — caller "ctrl" yerine "control_key" yazarsa hiç modifier basılmaz, hata da görmez. Trade-off: caller LLM çıktısının küçük varyasyonlarına dayanıklı olmak vs. fail-loud davranış. Şu an esneklik tercih edildi.
- IME path artık per-grapheme; çok uzun metinde (>1000 char) ufak overhead. Pratik MCP tool kullanımında metin ≤200 char tipik — sorun yok.

## Plan (iterative)

- **Faz 3b ✓** (bu commit, v0.2.14): `ModifierFlags` OptionSet + `PointerControl.click(modifiers:)` + `unicodeChunks(for:)` grapheme grouping + MCP `ui_click` `modifiers` parametresi + 24 yeni test (13 IME + 11 ModifierFlags).
- **Faz 3c:** Window content-area screenshot crop (titlebar exclude); CGEvent flag combinations daha detaylı (capslock state, function-keys).
- **Faz 4:** Set-of-Mark visual annotation.

## References

- [`Sources/PixelComputerUse/PointerControl.swift`](../../Sources/PixelComputerUse/PointerControl.swift)
- [`Sources/PixelComputerUse/PixelComputerUse.swift`](../../Sources/PixelComputerUse/PixelComputerUse.swift) (`click(_:count:modifiers:)` façade)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) (`uiClick` schema modifiers param)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (`uiClick` bridge handler modifiers parse)
- [`Tests/PixelComputerUseTests/ModifierFlagsTests.swift`](../../Tests/PixelComputerUseTests/ModifierFlagsTests.swift) (11 test)
- [`Tests/PixelComputerUseTests/IMEChunkingTests.swift`](../../Tests/PixelComputerUseTests/IMEChunkingTests.swift) (13 test)
- [ADR-0026 — PixelComputerUse Faz 1+2](0026-pixel-computer-use.md)
- [ADR-0028 — Chained Query DSL + opaqueID Re-Resolve (Faz 3a)](0028-chained-query-and-opaque-id.md)
- [Apple — CGEventFlags](https://developer.apple.com/documentation/coregraphics/cgeventflags)
- [Apple — CGEventKeyboardSetUnicodeString](https://developer.apple.com/documentation/coregraphics/1456564-cgeventkeyboardsetunicodestring)
- [Unicode UAX #29 — Text Segmentation (Grapheme Clusters)](https://unicode.org/reports/tr29/)
