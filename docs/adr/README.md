# Architecture Decision Records (ADR)

Bu dizin pixel-agent v3'ün mimari kararlarını kayıt altında tutar. Her ADR bir kararı, **bağlamını** (neden), **alternatiflerini** ve **sonuçlarını** (olumlu/olumsuz) belgeler. Numaralar kronolojik ve kalıcıdır — bir ADR yanlışlandığında silinmez, yeni bir ADR ile "supersede" edilir.

Format şablonu: `Status` · `Date` · `Tags` → `Context` → `Decision` → `Alternatives considered` → `Consequences` → `Plan (iterative)` → `References`.

## Duruş ilkeleri (ADR'lar arası tutarlılık)

Bu kararların altında yatan ve yeni kod yazılırken korunması gereken ilkeler:

1. **Zero external dependency** — yalnızca system framework'ler (+ `swift-docc-plugin`). Yeni SPM dep eklemeden önce manuel wrap değerlendir.
2. **SwiftUI App lifecycle** ([0002](0002-swiftui-app-lifecycle.md)) — `NSApplicationDelegate` god class yok (v2 anti-pattern'i).
3. **DI over singletons** ([0009](0009-dependency-injection-over-singletons.md)) — tek istisna `ToolArbiter.shared` (gerçek fiziksel kaynak mutex).
4. **JSONL append-only** ([0006](0006-jsonl-append-only-storage.md)) — Core Data/SQLite yok; git-diff'lenebilir, debug-friendly.
5. **CLI subprocess over HTTP** ([0010](0010-cli-subprocess-backend.md)) — yeni LLM provider için önce CLI'si var mı bak.
6. **Tek noktada envelope** ([0008](0008-remote-envelope-shared-module.md)) — `PixelRemote` modülü; cross-repo sync derdini yapısal engelle.
7. **Saf helper + ince view** — SwiftUI'a bağımlı view'lar görsel parametreleri test edilebilir saf helper'lardan tüketir.

## ADR'lar (tematik)

### Temel mimari (0001-0009)
| # | Başlık | Status |
|---|---|---|
| [0001](0001-modular-spm-monorepo.md) | Modular SPM Monorepo | Accepted |
| [0002](0002-swiftui-app-lifecycle.md) | SwiftUI App Lifecycle (NSApplicationDelegate yok) | Accepted |
| [0003](0003-tasklocal-context-propagation.md) | TaskLocal Context Propagation | Accepted |
| [0004](0004-chatbackend-protocol-abstraction.md) | ChatBackend Protokol Soyutlaması | Accepted |
| [0005](0005-toolarbiter-resource-mutex.md) | ToolArbiter Resource Mutex | Accepted |
| [0006](0006-jsonl-append-only-storage.md) | JSONL Append-Only Storage | Accepted |
| [0007](0007-test-isolation-mock-tasklocal.md) | Test Isolation — MockBackend + TaskLocal | Accepted |
| [0008](0008-remote-envelope-shared-module.md) | Remote Envelope Shared Module | Accepted |
| [0009](0009-dependency-injection-over-singletons.md) | Dependency Injection Over Singletons | Accepted |

### Backend & yerel araçlar (0010-0011)
| # | Başlık | Status |
|---|---|---|
| [0010](0010-cli-subprocess-backend.md) | CLI Subprocess Backend (API yerine) | Accepted |
| [0011](0011-native-macos-toolkit.md) | Native macOS Toolkit | Accepted |

### Remote / iOS / güvenlik (0012-0015)
| # | Başlık | Status |
|---|---|---|
| [0012](0012-remote-envelope-schema.md) | Remote Envelope Schema | Accepted |
| [0013](0013-pairing-and-relay-protocol.md) | Pairing ve Relay Protokolü | Accepted |
| [0014](0014-ios-app-store-assets.md) | iOS App Store Asset + Privacy Manifest | Accepted |
| [0015](0015-ed25519-envelope-signing.md) | ed25519 Envelope Signing | Accepted |

### MCP & Subagent (0016-0020, 0024)
| # | Başlık | Status |
|---|---|---|
| [0016](0016-mcp-server-expose.md) | MCP Server Expose | Accepted |
| [0017](0017-plan-mode.md) | Plan Mode (Read-Only Allowlist) | Accepted |
| [0018](0018-mcp-bridge-unix-socket.md) | MCP Faz 2 — Unix Socket Bridge | Accepted |
| [0019](0019-subagent-runner.md) | Subagent Runner — Ephemeral Budget | Accepted |
| [0020](0020-mcp-dispatch-subagent.md) | MCP `dispatch_subagent` | Accepted |
| [0024](0024-subagent-ui-panel.md) | Subagent UI Panel & Manager | Accepted |

### LAN-only mode (0021-0023, 0025)
| # | Başlık | Status |
|---|---|---|
| [0021](0021-lan-mode-bonjour.md) | LAN-Only Mode — Bonjour + Network.framework | Accepted |
| [0022](0022-remote-transport-adapter.md) | `RemoteTransport` Protokolü + Adapter Layer | Accepted |
| [0023](0023-merge-transport-and-mac-wire-up.md) | `MergeTransport` + Mac Wire-Up | Accepted |
| [0025](0025-lan-first-ios-default.md) | iOS LAN-First Default + TXT Record | Accepted |

### Computer Use (0026-0031)
| # | Başlık | Status |
|---|---|---|
| [0026](0026-pixel-computer-use.md) | PixelComputerUse — AX-First Hybrid | Accepted |
| [0027](0027-toolarbiter-implementation.md) | ToolArbiter Implementasyonu | Accepted |
| [0028](0028-chained-query-and-opaque-id.md) | Chained Query DSL + opaqueID Re-Resolve | Accepted |
| [0029](0029-modifier-flags-and-ime.md) | Modifier Flags + IME-Aware Text Injection | Accepted |
| [0030](0030-window-content-crop.md) | Window Content-Area Screenshot Crop | Accepted |
| [0031](0031-set-of-mark-annotation.md) | Set-of-Mark Visual Annotation | Accepted |

### Remote dashboard & zeka & bağlantı (0032-0037)
| # | Başlık | Status |
|---|---|---|
| [0032](0032-ios-dashboard-control-protocol.md) | iOS Dashboard Remote Control Protocol | Accepted |
| [0033](0033-cross-session-memory.md) | Cross-Session Memory — MemoryStore + PlaybookLearner | Accepted |
| [0034](0034-proactive-engine.md) | ProactiveEngine — Trigger-Based Passive UX | Accepted |
| [0035](0035-pixel-voice.md) | PixelVoice — Realtime Voice Provider Abstraction | Accepted |
| [0036](0036-relay-launcher-url-resolver.md) | Relay Launcher + URL Resolver | Accepted · ⚠️ production Cloudflare cert ile bloke |
| [0037](0037-skill-recipe-extraction.md) | Skill / Recipe Extraction — Self-Improving Workflows | Accepted (Faz 1) |

## Yeni ADR yazarken

- Numara sıradakini al (`0038+`).
- Şablonu koru (Status/Date/Tags/Context/Decision/Alternatives/Consequences/Plan/References).
- References'ta gerçek kaynak dosya yolları + ilgili ADR linkleri ver.
- Bu README tablosuna satır ekle.
