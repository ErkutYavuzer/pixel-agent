# ADR-0028: Chained Query DSL + opaqueID Re-Resolve (PixelComputerUse Faz 3a)

**Status:** Accepted (Faz 3a landed)
**Date:** 2026-05-23
**Tags:** computer-use, accessibility, mcp

## Context

[ADR-0026](0026-pixel-computer-use.md) PixelComputerUse Faz 1+2 ile temel `query / click / type / screenshot` API'sini koydu. Faz 1'de `UIQuery` tek-seviyeli AND filtresi — "AXButton, title='Save'" gibi. Pratikte iki yetersizlik:

1. **Aynı role + title farklı yerlerde tekrar ediyor.** Settings penceresinde 3 farklı "Save" butonu varsa hangisini istediğimizi söyleyemiyoruz; refine için identifier gerekli ama her UI onu vermiyor. Caller'a "şu grubun içindeki Save" demek lazım.
2. **opaqueID stale.** `query()` çağrısı bir UI snapshot döndürüyor; caller bunu cache'leyip 2 saniye sonra `click` yapmak isteyince UI değişmişse koordinat yanlış olabilir; element AXUIElement referansı da saklanmıyor (actor sınırı). Caller'a "şu element'i tekrar bul" demek lazım.

[AXorcist](https://github.com/steipete/AXorcist) ve Claude Cowork best-practices her ikisini de "fuzzy/chained queries" ve "opaque handle" pattern'leriyle çözüyor. Faz 3a aynısını minimal yüzeyle ekler.

## Decision

### `UIQuery.within: [UIQuery]` — chained ancestor constraints

Element'in her constraint için en az bir ancestor'a sahip olması gerekir (AND semantik). Multiple constraint = farklı veya aynı ancestor'a uyabilir; sıra önemsiz.

```swift
UIQuery(role: .button, title: "Save",
        within: [UIQuery(role: .group, title: "Sidebar")])
```

Recursive: `within` içindeki UIQuery'in kendi `within` constraint'i olabilir → nested zincir.

Tasarım kararları:
- **Dizi (array) vs indirect enum:** dizi seçildi. Codable + Hashable + Sendable kolay; indirect enum'a göre daha az sürpriz.
- **Sırasız AND:** "button → group → window" tam hiyerarşi sıralamasını dayatmıyor. Pratikte caller "Sidebar group'unun *altında bir yerde*" demek istiyor, exact nesting değil.
- **Recursive iterasyon limiti:** AXBridge ancestor walk 32 seviye ile sınırlı (loop guard); pratik UI hiyerarşileri 10-15 seviyeyi geçmez.

### `UIQuery.containsText: String?` — title VEYA label substring (case-insensitive)

`title` / `label` alanları belirli bir attribute'a karşı match yapar; `containsText` ikisinin birleşim kümesinde substring arar. `matchMode`'a tabi değil — her zaman `.caseInsensitive` contains.

Faydası:
- AXTitle bazen "Sign In" iken AXDescription "Sign in to your account" olabilir. Caller "sign in" yazıp ikisini de yakalar.
- Localized app'larda title varyasyonu (örn. "Save"/"Save…"/"Save File") — substring tek hamle.
- Diğer constraint'lerle AND'lenir; tek başına özellik değil.

`matchMode.fuzzy`'den farkı: `fuzzy` belirli bir attribute'a (title VEYA label) karşı substring; `containsText` ikisinin birleşim kümesine karşı. Farklı kullanım.

### `opaqueID` formatı — stable serileştirme

Faz 1'de `opaqueID = path.joined("/") + identifier/title` — debug-friendly ama parse edilemez. Faz 3a'da yeniden:

```
<bundleID>|<role>[:<discriminator>]|<role>[:<discriminator>]|...
```

- `bundleID` boş ise frontmost app.
- `discriminator`: identifier > title (varsa). Olmayanlar atlanır.
- Ayraç çakışmasını önlemek için `|` ve `:` `\u{1}` ve `\u{2}` ile escape edilir.

Örnek:
```
com.apple.Safari|AXApplication|AXWindow:Welcome|AXToolbar|AXButton:Sign In
```

`OpaqueID` enum'unda `encode(bundleID:path:discriminators:)` ve `decode(_:)` saf fonksiyonlar — AX-bağımsız, unit-test friendly.

### `PixelComputerUse.resolve(opaqueID:) -> UIElement?`

Daha önce alınmış bir opaqueID'den canlı element snapshot'ı:
1. opaqueID parse → bundleID + path
2. Root: bundleID set ise hedef app; yoksa frontmost
3. Path'i adım adım yürü; her seviyede `findChild(of:matching:)` ile role + discriminator eşleşen ilk çocuğu bul
4. Son seviye için fresh snapshot dön

Eğer herhangi bir seviyede uyan çocuk yoksa **nil** — UI değişmiş, app kapanmış, vs. Hata değil çünkü "stale" doğal bir durum.

**Cache YOK.** Her resolve fresh path-walk yapar. Faydaları:
- Stale entry'le uğraşma derdi yok
- Eski referans tutmuyoruz (memory leak yok)
- Deterministic — aynı opaqueID + aynı UI = aynı sonuç
- TTL/eviction lojiği yok = daha az kod

Maliyet: her resolve O(depth × children) AX call. Tipik UI 10-15 seviye × ~10 children = 100-150 AX call ≈ 5-20ms. Pratik.

### MCP — yeni `ui_resolve` tool + extended `ui_query` schema

- **`ui_resolve`** — `{ "opaque_id": "..." }` → element JSON veya `{ "found": false }`. Read-only, Plan modunda çalışır. Accessibility izni gerekir.
- **`ui_query` schema'sına `contains_text` + `within` eklendi** (geriye uyumlu — JSON'da yoksa default'a düşer).

`BuiltInTools.makeRegistry()` artık **14 tool** döner (5 saf-data + 4 bridge + 5 ui_*).

## Alternatives considered

- **opaqueID = stringified UUID + in-memory cache.** Faz 3a için reddedildi: cache eviction politikası gerek (TTL veya LRU); actor sınırları arası AXUIElement geçemediği için cache her zaman AXBridge actor'ında olmak zorunda → resolve sadece o actor'da çalışır. Şu anki path-walk yaklaşımı stateless ve daha basit.
- **`UIQuery.within` tek (non-array) UIQuery + indirect enum.** Codable + Hashable + Sendable kombinasyonu için boilerplate fazla; dizi her iki AND'i temsil eder ve diziye genelleştirme zaten daha esnek.
- **Strict path matching (exact role hierarchy).** Reddedildi: caller her zaman exact hierarchy'i bilmez ("button anywhere inside Sidebar group" yeterli).
- **`containsText` `matchMode`'a tabi olsun.** Reddedildi: `containsText` semantiği zaten substring; mode katmak karışıklık yaratır. `fuzzy`/`regex` ihtiyacında caller `title` veya `label` kullanır.

## Consequences

**Olumlu:**
- Caller LLM "şu grup içindeki şu buton" gibi pratik query'ler yazabilir — ambiguousMatch hatası azalır.
- `ui_resolve` workflow: query → snapshot al → ekran değişir → resolve → click. Stale koordinat problemi yapısal çözüldü.
- AX-bağımsız `OpaqueID` enum saf testlenir; serileştirme bug'ları unit test'te yakalanır.
- Schema geriye uyumlu — eski Codable JSON'lar (v0.2.12 ve önce) decode edilebilir (`decodeIfPresent` + custom CodingKeys).

**Olumsuz:**
- `UIQuery` Codable artık manuel — `decodeIfPresent` yazmak zorunda. Yeni alan eklerken hata yapma riski.
- Ancestor walk her aday match için ekstra AX call'lar — derin hiyerarşi + çok match senaryosunda yavaş olabilir (BFS tüm tree'yi tarıyor; ancestor walk her match'te 32 seviye). Faz 3b'de path field'ını snapshot'a daha zengin yerleştirerek (`path: [PathEntry]` role + title) ancestor walk AX call'sız yapılabilir.
- `opaqueID` formatı değişti — v0.2.12 client'ları yeni format'ı parse edemez (ama v0.2.12'de opaqueID resolve yoktu, sadece debug string). Pratikte breaking yok.

## Plan (iterative)

- **Faz 3a ✓** (bu commit, v0.2.13): `UIQuery.within` + `containsText`, `OpaqueID` encode/decode, `AXBridge.resolve(opaqueID:)`, `PixelComputerUse.resolve(_:)`, MCP `ui_resolve` tool + `ui_query` schema extension, 23 yeni test (13 ChainedQueryTests + 10 OpaqueIDTests).
- **Faz 3b:** `PointerControl.click(modifiers: ModifierFlags)` (cmd/opt/shift/ctrl); IME-aware text injection verification (Türkçe, emoji, diakritik); `ScreenshotCapture` window content-area opsiyonu.
- **Faz 4:** Set-of-Mark visual annotation (ADR-0026'da yazıldığı gibi).

## References

- [`Sources/PixelComputerUse/UITypes.swift`](../../Sources/PixelComputerUse/UITypes.swift) (`UIQuery.within`, `UIQuery.containsText`, Codable backward-compat)
- [`Sources/PixelComputerUse/OpaqueID.swift`](../../Sources/PixelComputerUse/OpaqueID.swift) (encoder/decoder)
- [`Sources/PixelComputerUse/AXBridge.swift`](../../Sources/PixelComputerUse/AXBridge.swift) (`checkAncestorConstraints`, `resolve(opaqueID:)`, `findChild`)
- [`Sources/PixelComputerUse/PixelComputerUse.swift`](../../Sources/PixelComputerUse/PixelComputerUse.swift) (`resolve(_:)` actor metodu)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) (`uiResolve` ToolDefinition + extended `uiQuerySchema`)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (`uiResolve` bridge handler)
- [`Tests/PixelComputerUseTests/ChainedQueryTests.swift`](../../Tests/PixelComputerUseTests/ChainedQueryTests.swift)
- [`Tests/PixelComputerUseTests/OpaqueIDTests.swift`](../../Tests/PixelComputerUseTests/OpaqueIDTests.swift)
- [ADR-0026 — PixelComputerUse Faz 1+2](0026-pixel-computer-use.md)
- [AXorcist (referans)](https://github.com/steipete/AXorcist)
