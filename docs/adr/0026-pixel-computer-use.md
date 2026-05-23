# ADR-0026: PixelComputerUse — AX-First Hybrid Computer Use

**Status:** Accepted (Faz 1 + Faz 2 landed)
**Date:** 2026-05-22 (Faz 1) · 2026-05-22 (Faz 2)
**Tags:** computer-use, accessibility, screenshot, mcp, agent

## Context

v0.2.11 ([ADR-0025](0025-lan-first-ios-default.md)) ile LAN-only mode roadmap'i kapandı. Pixel artık iOS↔Mac güvenli mesajlaşma, MCP bridge, subagent, Plan Mode, dual-agent CLI ile **chat + 8 native tool** sunan bir agent. Eksik olan şey: **"iş yapan agent"** iddiası. Şu an pixel UI'yi *görmüyor*, fareyi/klavyeyi *tutmuyor*. Kullanıcının dediği "Safari'yi aç, Maps'i tıkla, X ara" istekleri CLI'nın kendi `Bash` tool'una düşüyor → o da AppleScript yazmaya çalışıyor → kırılgan.

2026 manzarasında "computer-use" 3 yaklaşımdan birinde yapılıyor (bkz. araştırma raporu, oturum başı):

| Yaklaşım | Hız | Doğruluk | Maliyet | Çapraz-OS |
|---|---|---|---|---|
| Pure screenshot + VLM (OpenAI Operator) | Yavaş | Orta | Yüksek (her tıkta vision) | ✓ |
| AX-only (eski AppleScript GUI scripting) | Hızlı | Yüksek (label varsa) | Düşük | ✗ macOS-specific |
| **Hybrid (AX-first → screenshot fallback)** (Claude Cowork, [Fazm](https://earezki.com/ai-news/2026-03-17-what-we-learned-building-a-macos-ai-agent-in-swift-screencapturekit-accessibility-apis-async-pipelines/), [AXorcist](https://github.com/steipete/AXorcist)) | Orta | Yüksek | Orta | ~ macOS-only (şimdilik) |

pixel-agent2'de Sprint 2 ([PR #9](https://github.com/ErkutYavuzer/pixel-agent2/pull/9), 20 May 2026) `ui_click AX-first hybrid` denenmişti. Mantığı kanıtlandı; v3'te skeleton'dan inşa edilecek.

## Decision

### Yeni library: `PixelComputerUse`

Sıfır harici bağımlılık (sadece system framework'ler: `ApplicationServices`, `CoreGraphics`, `ScreenCaptureKit`, `AppKit`). PixelTools'tan ayrı: PixelTools = UX katmanı (mascot, dock badge, ses, bildirim); PixelComputerUse = **gerçek desktop control**.

### Mimari 3 katman

```
┌──────────────────────────────────────────────────────┐
│  Algı (Perception)                                   │
│  ├─ AXBridge: ApplicationServices C API wrap (actor) │
│  ├─ AXQueryEngine: tree traversal + match            │
│  └─ ScreenshotCapture: SCScreenshotManager           │
├──────────────────────────────────────────────────────┤
│  Karar (Decision) — bu kütüphane dışında (LLM)       │
├──────────────────────────────────────────────────────┤
│  Kontrol (Control)                                   │
│  ├─ PointerControl: CGEvent mouse/key inject         │
│  └─ ToolArbiter: pointer hardware mutex (ADR-0005)   │
└──────────────────────────────────────────────────────┘
```

### Public façade: `actor PixelComputerUse`

```swift
public actor PixelComputerUse {
    public init(arbiter: ToolArbiter? = nil)

    public func query(_ q: UIQuery) async throws -> [UIElement]
    public func click(_ q: UIQuery, count: Int = 1) async throws -> UIElement
    public func type(_ text: String, into q: UIQuery? = nil) async throws
    public func screenshot(of target: ScreenshotTarget = .activeDisplay) async throws -> ScreenshotResult
}
```

`UIQuery` value-type, Sendable, Codable — MCP üzerinden JSON ile alınabilir, in-process'te de aynı API.

### Hybrid akış (`click` örneği)

```
ui_click(query) call
  │
  ▼
PixelComputerUse.click(q)
  │
  ├─ AXQueryEngine.find(q) → [UIElement]
  │    ├─ 0 match → throw .noMatch (caller LLM screenshot fallback'a karar verir)
  │    ├─ 1 match → tıkla
  │    └─ ≥2 match → throw .ambiguousMatch (caller refine etmeli)
  │
  └─ PointerControl.click(at: element.frame.center, count: count)
       └─ ToolArbiter.shared.withPointer { CGEvent.post }
```

Kütüphane saf-screenshot path'i karar **vermez** — caller LLM `ui_query` çağırır, sonuç boş gelirse `ui_screenshot` çağırır, VLM ile inceler, koordinat verir, sonra `pointer_click_at` (Faz 2 tool) çağırır. Bu ayırma:
1. Kütüphane VLM kullanmıyor → hiçbir LLM dependency yok, deterministic, test-friendly.
2. Caller'a kontrol bırakılıyor → Claude Sonnet 4.6 vs daha küçük model tercihi caller'da.

### Permissions

İki ayrı izin:
- **Accessibility** (`AXIsProcessTrustedWithOptions`): UI query + click + type için
- **Screen Recording** (`CGPreflightScreenCaptureAccess` + `SCShareableContent.current`): screenshot için

`ComputerUsePermissions.preflight()` her ikisini kontrol eder, eksikse `ComputerUseError.accessibilityNotAuthorized` / `.screenRecordingNotAuthorized` fırlatır. UX akışı: ilk `ui_*` çağrısında PixelMacApp `NSAlert` ile kullanıcıyı System Settings'e yönlendirir (Faz 2 UI iş — Faz 1'de error message yeterli).

### MCP exposure (4 yeni bridge tool)

| Tool | Permission | Plan Mode | Açıklama |
|---|---|---|---|
| `ui_query` | Accessibility | ✓ (read-only) | UIQuery → [UIElement] |
| `ui_click` | Accessibility | ✗ (destructive) | Element üzerine tıkla |
| `ui_type` | Accessibility | ✗ (destructive) | Aktif veya hedef element'e yaz |
| `ui_screenshot` | Screen Recording | ✓ (read-only) | PNG + base64 metadata |

Hepsi bundle-bağımlı → `ControlSocketServer` üzerinden bridge (ADR-0018). pixel-mcp-server standalone'da bu tool'lar "PixelAgent.app çalışıyor mu?" hatası döner.

### Plan Mode entegrasyonu

`pixel-mcp-server` startup'ta `PIXEL_PLAN_MODE` env var'ı okur (Faz 2). Set ise `ui_click`/`ui_type` tool dispatch'i `ToolResultBuilder.error("plan modunda destructive UI tool çağrılamaz")` döner. `ui_query`/`ui_screenshot` her durumda çalışır.

Faz 1'de bu enforcement YOK — sadece tool description'larına "Plan modunda kullanılmamalı" notu konur. Kullanıcı plan modunda Claude CLI `--permission-mode plan` kullandığı için `ui_click` çağrısı için zaten manuel onay isteyecek.

### ToolArbiter (ADR-0005) ilk pratik kullanım

Pointer fiziksel olarak tek kaynak. İki paralel subagent aynı anda `ui_click` yapamaz. `ToolArbiter.shared.acquire(.pointer)` mutex. Subagent cap=3 (ADR-0024) ile teorik olarak 3 paralel computer-use; mutex serialize eder.

### Çapraz-platform

- macOS: tam destek (target 14+).
- iOS: `PixelComputerUse` API yüzeyi compile eder ama tüm metodlar `ComputerUseError.unsupported("iOS")` fırlatır. iOS app'i `ui_*` bridge tool'larını **çağırmaz** — relay üzerinden Mac'e ileterek Mac'in çalıştırması iOS UX'i için yeterli.

## Alternatives considered

- **[AXorcist](https://github.com/steipete/AXorcist)'i SPM dep olarak ekle** — v3 zero-dep ilkesi (sadece `swift-docc-plugin` var). Manuel wrap tercih edildi; AXorcist tasarımı referans alındı.
- **`computer_use(prompt:)` tek mega-tool (Operator-style)** — caller LLM granular orchestration tercih ediyor (subagent + Plan Mode + screenshot inspect döngüsü için). Fine-grained tool'lar daha esnek.
- **CGEvent yerine `osascript` ile AppleScript GUI scripting** — yavaş (subprocess başlatma + AS parse), kırılgan. AXorcist/Fazm yaklaşımı + CGEvent doğrudan + AX API çok daha hızlı.
- **Sandbox + microVM** (v2 önerisinde atlandı) — yüksek çaba, Faz N ileri sprint.
- **Set-of-Mark visual marking** ([SoM](https://arxiv.org/abs/2310.11441)) — VLM accuracy artırır ama Faz 1'de overhead. Faz 4'e ertelendi.

## Consequences

**Olumlu:**
- pixel "iş yapan agent" tier'ına çıkar.
- Subagent + Plan Mode + `ui_*` = "research subagent" yapısı çalışır: `dispatch_subagent("App Store'da X uygulamasını ara, ekran görüntüsü al, özetle")`.
- Sıfır external dep — v3 architectural ilkesine sadık.
- iOS↔Mac forward (ADR-0013): kullanıcı iPhone'dan "Mac'inde Safari'yi aç X yap" diyebilir; relay → Mac PixelAgent.app → `ui_click`.

**Olumsuz:**
- macOS-specific kod artar; iOS no-op stub'lar bakım yükü.
- Accessibility + Screen Recording iki izin daha. Onboarding UX karmaşıklaşır.
- CGEvent injection App Store sandbox'ında kısıtlı — App Store sürümünde `ui_*` tool'lar devre dışı kalabilir; ADR-0014 (iOS App Store assets) bunun macOS versiyonu için Faz 2'de gözden geçirilmeli.
- ToolArbiter.shared singleton kullanımı ADR-0009 istisnası — gerçek fiziksel kaynak mutex; ADR-0005'te zaten istisna sayılmıştı.

## Plan (iterative)

- **Faz 1 ✓** (Faz 1 commit): library skeleton + types + AX traversal (role/title/identifier match) + CGEvent click/type + SCScreenshotManager wrap + permission preflight + 4 MCP tool + ControlSocketServer dispatch + 43 unit test.
- **Faz 2 ✓** (Faz 2 commit): `ToolArbiter.shared` integration aktive (PointerControl.click/typeText `with([.pointer])` ile sarıldı, [ADR-0027](0027-toolarbiter-implementation.md)); PIXEL_PLAN_MODE env enforcement (`planModeGuard` ui_click/ui_type'ı bloklar); `PermissionsView` SwiftUI sheet (System Settings deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility|ScreenCapture`); PixelMacApp top bar `lock.shield` badge (allGranted → yeşil).
- **Faz 3:** AXorcist seviyesinde fuzzy/chained query DSL; `UIElement.opaqueID` ile re-resolve; window-level screenshot crop iyileştirme; CGEvent flag combinations (modifier keys); IME-aware text injection.
- **Faz 4:** Set-of-Mark visual annotation (`ui_screenshot(annotate: true)` → coordinate grid + per-element ID overlay).

## References

- [`Sources/PixelComputerUse/`](../../Sources/PixelComputerUse/) (Faz 1)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) (ui_* tool registration)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift) (ui_* bridge handlers)
- [ADR-0005 — ToolArbiter resource mutex](0005-toolarbiter-resource-mutex.md)
- [ADR-0011 — Native macOS toolkit](0011-native-macos-toolkit.md)
- [ADR-0017 — Plan Mode](0017-plan-mode.md)
- [ADR-0018 — MCP Unix socket bridge](0018-mcp-bridge-unix-socket.md)
- [Apple — AXUIElement Reference](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Apple — ScreenCaptureKit / SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
- [AXorcist (referans)](https://github.com/steipete/AXorcist)
- [Fazm engineering notes (referans)](https://earezki.com/ai-news/2026-03-17-what-we-learned-building-a-macos-ai-agent-in-swift-screencapturekit-accessibility-apis-async-pipelines/)
- [Claude Cowork best practices (referans)](https://claude.com/blog/best-practices-for-computer-and-browser-use-with-claude)
