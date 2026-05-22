# ADR-0016: MCP Server Expose (Faz 1: Standalone Pure-Data Tools)

**Status:** Accepted (Faz 1 landed)
**Date:** 2026-05-22
**Tags:** mcp, ipc, tools, json-rpc

## Context

v0.2 yol haritasında "MCP server expose" başlığı vardı: pixel-agent kendi tool'larını [Model Context Protocol](https://modelcontextprotocol.io) standardı üzerinden başka LLM client'larına (claude-cli, codex-cli, vb.) sunsun. Böylece:

1. claude-cli'ın pixel-agent'ın yardımcı fonksiyonlarına erişimi olur (clipboard, LAN IP, vb.).
2. pixel-agent kendi içinde claude'u CLI subprocess olarak çalıştırırken aynı tool'ları enjekte edebilir (Faz 2/3).

MCP yapısı:
- JSON-RPC 2.0 transport (genelde stdio, newline-delimited JSON)
- Server'ın expose ettiği: tools, resources, prompts
- Client (claude-cli) `initialize` → `tools/list` → `tools/call` akışıyla kullanır

## Decision

### Standalone executable + library ayrımı

```
Sources/
├── PixelMCPServer/         # library — JSON-RPC + protocol + tool registry
│   ├── JSONValue.swift     # tip-güvenli JSON ağacı
│   ├── JSONRPCMessage.swift
│   ├── ToolRegistry.swift  # ToolDefinition + BuiltInTools
│   ├── MCPServer.swift     # actor: handle/processLine/runStdio
│   └── LANInterfaceAddress.swift  # getifaddrs wrapper (PixelMacApp'tan kopya)
└── pixel-mcp-server/       # executable — main.swift, sadece runStdio çağırır
    └── main.swift
```

Library: tüm logic, test-friendly (`processLine(_:)` saf string→string).
Executable: 3 satır main.swift, sadece IO.

### Tool stratejisi: Faz 1 = saf-data, Faz 2 = bundle-bağımlı

**Sorun:** `DockBadge`, `SystemNotifications`, `SoundEffect` — bunlar `NSApp` veya `Bundle.main.bundleIdentifier` gerektiriyor. Standalone CLI binary'sinin bundle'ı yok, dolayısıyla bu tool'lar çalışmaz.

**Faz 1 (landed):** sadece **bundle bağımsız** tool'lar:
- `get_clipboard` / `set_clipboard` — `NSPasteboard.general`
- `get_current_time` — ISO 8601 timestamp
- `get_active_app` — `NSWorkspace.shared.frontmostApplication`
- `get_lan_ip` — `getifaddrs` ile en0/en1 IPv4

**Faz 2 (gelecek):** bundle-bağımlı tool'lar IPC ile PixelMacApp'a delegated:
- `dock_badge_set` → PixelMacApp Unix socket'ine forward
- `notify` → aynı
- Veya: PixelMacApp kendi içinde MCPServer instance'ı host eder, claude-cli'a stdio yerine ayrı transport (Unix socket / TCP localhost) ile bağlanır

### Transport: stdio (Faz 1)

claude-cli MCP server config'i `~/.claude.json` veya `--mcp-config` ile:

```json
{
  "mcpServers": {
    "pixel-agent": {
      "command": "/path/to/pixel-mcp-server",
      "args": []
    }
  }
}
```

Server stdin'den newline-delimited JSON okur, stdout'a yanıt yazar. `fflush(stdout)` her response sonrası kritik (line buffering otherwise gerekli olmayacak ama subprocess context'inde tetikler).

### Protocol versiyon

`MCPServer.protocolVersion = "2024-11-05"` — MCP spec'in mevcut sürümü.

### Hata yönetimi

- Bilinmeyen method → JSON-RPC `-32601` (method not found)
- Bilinmeyen tool → aynı kod, mesajda tool adı
- Eksik `name` parametresi → `-32602` (invalid params)
- Decode hatası → `-32700` (parse error), id `null`
- Notification (id yok) → response yok, hata bile

### Test stratejisi

`processLine(_:)` saf string→string olduğu için hermetic test-friendly. Stdio I/O olmadan tüm dispatch yolları test edilir. Built-in tool'lardan `get_current_time` ve `get_lan_ip` ortamdan bağımsız sanity test edilir; clipboard tool'ları test'te dokunulmaz (sistem panosu global state).

## Consequences

**Olumlu:**
- claude-cli (ve uyumlu diğer client'lar) pixel-agent tool'larını kullanabilir.
- Sıfır bağımlılık eklendi — CryptoKit/Security gibi sistem framework'leri ile sınırlı.
- 30 yeni test (5 JSONValue + 6 JSONRPCMessage + 11 MCPServer + 8 ToolRegistry); toplam 162.
- Transport-bağımsız mimari: stdio Faz 1, Unix socket veya TCP Faz 2'de kolay eklenir (yeni `MCPServer.run*()` overload).

**Olumsuz:**
- Tool sayısı sınırlı (5). Daha zengin tool seti Faz 2'de bundle/IPC ile gelecek.
- `LANInterfaceAddress` kodu PixelMacApp'tan kopyalandı (ortak modüle taşıma TODO).
- AppKit import → library macOS-only. iOS'ta `#if canImport(AppKit)` fallback ile build geçer ama tool'lar çalışmaz; iOS hedef değil zaten.

## Faz 2 — bundle-bağımlı tool'lar (gelecek commit)

İki tasarım seçeneği:
1. **Unix domain socket bridge**: PixelMacApp `~/Library/Caches/dev.erkutyavuzer.pixel-agent.sock` üzerinde dinler; pixel-mcp-server bundle-bağımlı tool çağrısında bu socket'e forward eder. PixelMacApp NSApp ile gerçek aksiyonu yapar, sonucu döner.
2. **PixelMacApp embeds MCPServer**: PixelMacApp kendi içinde MCPServer instance'ı tutar, TCP localhost veya Unix socket dinler. claude-cli direkt PixelMacApp'a bağlanır. Pixel-mcp-server'a ihtiyaç kalmaz (veya o sadece PixelMacApp varsa forward eder).

Tercih edilen: 1 (server'ı simple tutar, bridge ayrı). Faz 2'de ele alınacak.

## Alternatives

- **HTTP / SSE transport**: MCP spec destekler ama localhost binding gerektirir, daha karmaşık. stdio default ve yeterli.
- **gRPC**: ekstra dependency (.proto, runtime). Yapısal olarak overkill.
- **AppleScript / AppleEvents**: macOS-only ekosistemde mantıklı ama platform-agnostic MCP spec ile uyumsuz.

## References

- [Model Context Protocol spec](https://spec.modelcontextprotocol.io/)
- [MCP example servers](https://github.com/modelcontextprotocol/servers)
- `Sources/PixelMCPServer/`
- `Sources/pixel-mcp-server/main.swift`
