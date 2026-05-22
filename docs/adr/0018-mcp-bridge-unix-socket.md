# ADR-0018: MCP Faz 2 — Unix Socket Bridge (Bundle-Bağımlı Tool'lar)

**Status:** Accepted (Faz 2 landed)
**Date:** 2026-05-22
**Tags:** mcp, ipc, unix-socket, bundle

## Context

[ADR-0016](0016-mcp-server-expose.md) Faz 1'de `pixel-mcp-server` standalone executable olarak 5 saf-data tool expose etti (clipboard, time, active app, lan ip). Bunlar bundle bağımsız çalıştı.

Bundle-bağımlı tool'lar (`DockBadge.set()`, `SystemNotifications.post()`, `SoundEffect.play()`) ise `NSApp` veya `Bundle.main.bundleIdentifier == "dev.erkutyavuzer.pixel-agent"` gerektirir. Standalone CLI bunları çalıştıramaz — bridge IPC gerekiyor.

claude-cli (veya başka MCP client) **pixel-mcp-server'ı subprocess olarak spawn eder**; PixelMacApp'ı doğrudan kullanamaz. Bu yüzden:

```
claude-cli ─stdio─→ pixel-mcp-server ─Unix socket─→ PixelMacApp ─→ DockBadge/Notify/Sound
```

## Decision

### Transport: Unix Domain Socket

POSIX `socket(AF_UNIX, SOCK_STREAM, 0)`. macOS-native, sandbox-friendly (yoluna sahip kullanıcı erişebilir).

**Yol:** `~/Library/Caches/dev.erkutyavuzer.pixel-agent/control.sock`
- `~/Library/Caches` user-local; dosya ACL'i ile başka kullanıcılar erişemez
- Dizin yoksa `BridgePaths.defaultSocketPath()` mkdir -p yapar
- `sockaddr_un.sun_path` 104 byte limit — preflight kontrol (`BridgePaths.maxSocketPathLength`)

**Protokol:** newline-delimited JSON, MCP'in stdio formatıyla aynı.

```swift
struct BridgeRequest: Codable {
    let tool: String          // "dock_badge_set" | "notify" | "play_sound"
    let arguments: JSONValue
}

struct BridgeResponse: Codable {
    let ok: Bool
    let result: JSONValue?    // success'te dolu
    let error: String?        // failure'da dolu
}
```

### Tek-atımlık (single-shot) RPC

Her tool çağrısı için:
1. `socket()` → `connect()`
2. write `BridgeRequest + \n`
3. read until `\n` veya EOF
4. parse `BridgeResponse`
5. `close()`

Long-lived bağlantı tutmadık — overhead düşük, error recovery basit. ~30k tool çağrısı/saat'in altında zaten.

### `BridgeClient` (PixelMCPServer)

`BridgeClient.call(tool:arguments:socketPath:)` async throws — POSIX socket syscalls'larını sarmalar. `BridgeError` enum:
- `socketCreateFailed(errno)`
- `pathTooLong(n)` (>104 byte)
- `connectFailed(path, errno)` — PixelAgent.app çalışmıyor demektir
- `writeFailed`, `readFailed`, `decodeFailed`

### `ControlSocketServer` (PixelMacApp)

`actor ControlSocketServer`:
- `init(socketPath:)` — DI ile test-friendly
- `start()` throws — `socket → bind → listen → accept loop` (background DispatchQueue)
- `stop()` — `close(listenFD)` + `unlink(socketPath)`
- `running` idempotency flag

Accept loop her bağlantı için `Task { await handleClient(fd:) }` çağırır; dispatch sırasında MainActor hop (DockBadge.set NSApp.dockTile gerektirir).

App lifecycle: `RootView.task` içinde `Self.controlServer.start()` — hata olursa stderr'e log, UI bloke olmaz.

### Bridge tool'lar (3 yeni, MCP `BuiltInTools`)

1. **`dock_badge_set`** — `label: String | null`. Dock badge'ini ayarla/temizle.
2. **`notify`** — `title: String` (zorunlu), `body: String` (opsiyonel). Sistem bildirimi.
3. **`play_sound`** — `name: String`. macOS sistem sesi (Glass, Basso, Tink, Ping, Pop, Funk, Submarine, Sosumi).

Her tool `BuiltInTools.callBridge(tool:arguments:)` helper'ı üzerinden `BridgeClient.call` yapar; bağlanılamazsa `ToolResultBuilder.error(...)` döner — MCP `content` shape'inde `isError: true`.

### Sandbox + güvenlik notu

- Socket path user-local (`~/Library/Caches`), başka kullanıcılar erişemez (Unix ACL).
- Aynı kullanıcının başka uygulamaları socket'e bağlanabilir — şu an authentication yok. Tehdit modeli düşük (kullanıcı kendi geliştirme makinesinde).
- Üretim sandboxed app olacaksa: socket path container içinde olmalı (`NSApplicationSupportDirectory`); Faz 3.

## Consequences

**Olumlu:**
- claude-cli pixel-agent'ın native macOS aksiyonlarını tetikleyebilir (badge, notification, ses).
- Yeni protokol değil — JSON tipleri zaten PixelMCPServer'da, lower-level transport farklı.
- `BridgeRequest`/`BridgeResponse` ileride başka bundle-bağımlı tool'lar için reuse edilir.
- E2E test yazılabilir: bind ve connect aynı process'te, başka süreç gerekmiyor.

**Olumsuz:**
- PixelAgent.app çalışmıyorsa Faz 2 tool'lar hata döner — kullanıcı UX olarak garip olabilir. Tooltip/dokümantasyon ile iyileştirilir.
- POSIX socket Swift'te dağınık API — `sockaddr_un.sun_path` C-tuple, `withUnsafeMutablePointer` zinciri. Network.framework Unix socket'i tam desteklemediği için bu yola gidildi (sonraki bir Swift sürümünde refactor edilebilir).
- `SystemNotifications.isBundledApp` tighten edildi: xctest ortamında `Bundle.main.bundleIdentifier` non-nil ama `.app` paketi olmadığı için artık `bundleURL.pathExtension == "app"` da kontrol ediliyor.

## Alternatives

- **TCP localhost (`127.0.0.1:PORT`)**: yaygın ama port allocation derdi; `lsof -i :PORT` ile başka kullanıcı görebilir. Reddedildi.
- **XPC service**: macOS-native, sandbox-friendly, code-signed; ama Info.plist + bundle setup gerektirir; pixel-mcp-server standalone CLI olarak ship edilemez. Faz 3'te değerlendirilir.
- **NSDistributedNotificationCenter**: tek-yönlü broadcast (fire-and-forget); response döndüremez. Tool API'sine uygun değil.
- **AppleScript / AppleEvents**: legacy; pixel-agent.app'in bir AppleScript dictionary'si yok; PR'lık ek iş.
- **Long-lived bağlantı + framing**: claude-cli MCP server yaşam süresince ~birkaç tool çağrısı yapar; bağlantı tutmanın overhead'i pay etmez. Single-shot RPC daha basit ve crash recovery sağlam.

## References

- [`Sources/PixelMCPServer/BridgeProtocol.swift`](../../Sources/PixelMCPServer/BridgeProtocol.swift)
- [`Sources/PixelMCPServer/BridgeClient.swift`](../../Sources/PixelMCPServer/BridgeClient.swift)
- [`Sources/PixelMacApp/ControlSocketServer.swift`](../../Sources/PixelMacApp/ControlSocketServer.swift)
- [`Sources/PixelMCPServer/ToolRegistry.swift`](../../Sources/PixelMCPServer/ToolRegistry.swift) — `dockBadgeSet`, `notify`, `playSound` tool'lar
- [ADR-0016](0016-mcp-server-expose.md) — Faz 1 (saf-data tool'lar)
