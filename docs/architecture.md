# pixel-agent Architecture

> Son güncelleme: v0.2.13 (23 May 2026). 10 library + 2 executable target, 338 test, 28 ADR.

## Modül grafiği

```mermaid
graph TD
    App[PixelMacApp<br/>SwiftUI App]
    MCP[pixel-mcp-server<br/>stdio exe]
    Core[PixelCore]
    Backends[PixelBackends]
    Tools[PixelTools]
    Memory[PixelMemory]
    Mascot[PixelMascot]
    Remote[PixelRemote]
    MCPLib[PixelMCPServer]

    App --> Core
    App --> Backends
    App --> Tools
    App --> Memory
    App --> Mascot
    App --> Remote
    App --> MCPLib
    MCP --> MCPLib
    Backends --> Core
    Tools --> Core
    Memory --> Core
    Remote --> Core

    style App fill:#5b3fab,color:#fff
    style MCP fill:#5b3fab,color:#fff
    style Core fill:#734cd9,color:#fff
```

**Bağımlılık disiplini:** Tüm oklar `PixelCore` ya da yan modüllere doğru. Hiçbir library `PixelMacApp`'i import etmez (compile-time bloklanır). İki executable target var: `PixelMacApp` (GUI) ve `pixel-mcp-server` (CLI); ikincisi PixelMCPServer dışında hiçbir şeye bağımlı değildir, böylece minimum binary size + standalone deploy.

## Sohbet akışı

```mermaid
sequenceDiagram
    participant User
    participant ChatView as ChatView (SwiftUI)
    participant VM as ChatViewModel
    participant CLI as CLIBackend
    participant Subproc as claude/codex/gemini<br/>subprocess
    participant Memory as ConversationStore

    User->>ChatView: "Bana yardım et"
    ChatView->>VM: send(text)
    VM->>Memory: append(userMessage)
    VM->>CLI: send(messages, options: ChatOptions(planMode: false))
    CLI->>Subproc: Process(stdout: pipe)<br/>--output-format stream-json
    Subproc-->>CLI: stream-json events
    CLI->>CLI: StreamJSONParser.parse(line)
    CLI-->>VM: StreamDelta(textChunk)
    CLI-->>VM: StreamDelta(textChunk)
    CLI-->>VM: StreamDelta(done)
    VM->>Memory: append(assistantMessage)
    VM->>ChatView: finishStream(success: true)
```

**Plan Mode** (ADR-0017): `ChatOptions(planMode: true)` Claude için `--permission-mode plan` flag'i ekler — read-only tool allowlist. Codex/Gemini'de no-op.

**Dual mode**: `DualChatHost` aynı user prompt'unu iki ChatViewModel'a paralel gönderir; her birinin ayrı `conversation-{kind}.jsonl` dosyası vardır.

## Tool dispatch akışı (planned, henüz aktif değil)

v3 MVP'sinde dahili tool dispatch henüz yok — CLI subprocess'lerin kendi tool çalıştırma akışı (claude'un Read/Edit/Bash tool'ları) bizim sorumluluğumuz dışında. `ToolArbiter` (ADR-0005) tasarımı v0.3+ için reserve:

```mermaid
sequenceDiagram
    participant Backend
    participant Dispatcher as ToolDispatcher (planned)
    participant Arbiter as ToolArbiter (planned)
    participant Tool

    Backend->>Dispatcher: dispatch(name, args)
    Dispatcher->>Arbiter: acquire([.fileWrite("/path")])
    Arbiter-->>Dispatcher: granted
    Dispatcher->>Tool: execute(args)
    Tool-->>Dispatcher: result
    Dispatcher->>Arbiter: release([.fileWrite("/path")])
    Dispatcher-->>Backend: toolResult
```

TaskLocal context (`currentAgent`, `currentSubagentID`) tüm zincir boyunca propagate olur (ADR-0003). Şu an `AgentContext` PixelCore'da hazır, ancak dispatch zinciri henüz inşa edilmedi.

## Mac ↔ iOS imzalı kanal (landed v0.2.3 + v0.2.4)

```mermaid
sequenceDiagram
    participant iOSApp as PixelAgentRemote<br/>(iOS)
    participant Relay as Cloudflare Worker<br/>Durable Object
    participant Mac as PixelMacApp<br/>RemoteHost

    Note over iOSApp,Mac: QR'da: code + relayURL + pk=<mac-pubkey-b64>
    iOSApp->>iOSApp: QR scan → PairingInfo<br/>(macPublicKey, code, relayURL)
    iOSApp->>Relay: WS /listen/{code}
    Mac->>Relay: WS /connect/{code}
    Relay-->>iOSApp: ready
    Relay-->>Mac: ready

    Note over iOSApp,Mac: Handshake (chicken-and-egg)
    iOSApp->>Relay: hello(publicKey=ios-pk) [unsigned]
    Relay->>Mac: hello(publicKey=ios-pk) [unsigned]
    Mac->>Mac: peerPublicKey = ios-pk<br/>isPaired = true

    Note over iOSApp,Mac: Bundan sonra her envelope imzalı
    iOSApp->>iOSApp: EnvelopeSigner.sign(userMessage, with: ios-key)
    iOSApp->>Relay: userMessage + sig
    Relay->>Mac: userMessage + sig
    Mac->>Mac: EnvelopeSigner.verify(env, with: ios-pk) ✓
    Mac->>Mac: ChatView.send(text)

    Mac->>Mac: stream complete
    Mac->>Mac: EnvelopeSigner.sign(assistantMessage, with: mac-key)
    Mac->>Relay: assistantMessage + sig
    Relay->>iOSApp: assistantMessage + sig
    iOSApp->>iOSApp: EnvelopeSigner.verify(env, with: mac-pk) ✓
```

Relay payload'ları görür ama imzalayamaz — relay compromise olsa MITM mümkün değil. Anahtar yönetimi: `KeychainKeyStore` (`kSecAttrAccessibleAfterFirstUnlock`); test'lerde `InMemoryKeyStore`. Detay: [ADR-0015](adr/0015-ed25519-envelope-signing.md).

## MCP server akışı (Faz 1 + Faz 2)

```mermaid
sequenceDiagram
    participant Cli as claude-cli
    participant Mcp as pixel-mcp-server<br/>(stdio exe)
    participant Sock as Unix socket<br/>~/Library/Caches/.../control.sock
    participant App as PixelMacApp<br/>ControlSocketServer
    participant PT as PixelTools

    Cli->>Mcp: spawn subprocess<br/>(stdio piped)
    Cli->>Mcp: {"method":"initialize",...}
    Mcp-->>Cli: serverInfo + protocolVersion
    Cli->>Mcp: {"method":"tools/list"}
    Mcp-->>Cli: [get_clipboard, ..., dock_badge_set, notify, play_sound]

    Note over Cli,Mcp: Saf-data tool — bundle gerektirmez
    Cli->>Mcp: tools/call get_clipboard
    Mcp->>Mcp: NSPasteboard.general.string()
    Mcp-->>Cli: content: text

    Note over Cli,App: Bridge tool — PixelMacApp gerektirir
    Cli->>Mcp: tools/call dock_badge_set {label:"3"}
    Mcp->>Sock: BridgeRequest JSON + \n
    Sock->>App: accept → handleClient
    App->>App: MainActor hop
    App->>PT: DockBadge.set("3")
    App->>Sock: BridgeResponse {ok:true} + \n
    Sock->>Mcp: read until \n
    Mcp-->>Cli: content: "Badge: 3"
```

PixelMacApp çalışmıyorsa bridge tool'lar `connect()` ECONNREFUSED → `isError: true` content. Saf-data tool'lar her durumda çalışır. Detay: [ADR-0016](adr/0016-mcp-server-expose.md) + [ADR-0018](adr/0018-mcp-bridge-unix-socket.md).

## Katman dağılımı

| Katman | Sorumluluk | Modüller |
|---|---|---|
| **UI** | SwiftUI view'lar, scene lifecycle, toolbar | `PixelMacApp` |
| **Orchestration** | Sohbet akışı, agent state, composition root | `PixelMacApp` (`ChatViewModel`, `DualChatHost`, `ChatHost`) |
| **Domain protocols** | `ChatBackend`, `Envelope`, `ChatOptions`, TaskLocal | `PixelCore` |
| **Implementations** | CLI subprocess, JSONL store, mascot render | `PixelBackends`, `PixelMemory`, `PixelMascot` |
| **Native services** | macOS bundle-bağımlı toolkit | `PixelTools` |
| **Remote / IPC** | WebSocket envelope + ed25519 imza; Unix socket bridge | `PixelRemote`, `PixelMCPServer` (`BridgeProtocol`) |
| **External transport** | MCP stdio executable | `pixel-mcp-server` |

## Tasarım prensipleri

1. **Modüler SPM monorepo** (ADR-0001) — her sorumluluk kendi library target'ında; cross-module bağımlılık döngüsü compile-time bloklanır.
2. **SwiftUI App lifecycle** (ADR-0002) — `NSApplicationDelegate` god class anti-pattern'i (v2'de 5.277 satır) yapısal olarak engellenmiş.
3. **TaskLocal context propagation** (ADR-0003) — agent/subagent kimliği çağrı ağacında otomatik geçer; explicit param yok.
4. **Protocol-driven abstraction** (ADR-0004) — yeni LLM provider eklemek tek dosya yazımı; tek koşul: bir CLI binary'si olsun (ADR-0010).
5. **DI over singletons** (ADR-0009) — composition root'ta resolve; `ToolArbiter.shared` istisna (gerçek fiziksel kaynak mutex'i).
6. **Append-only storage** (ADR-0006) — durability + portability; Core Data/SQLite yok.
7. **Hermetic testing** (ADR-0007) — `MockBackend` + `TaskLocal` scoping; network'siz, deterministic, paralel-safe.
8. **Cross-platform shared module** (ADR-0008) — `RemoteEnvelope` Mac + iOS arasında tek noktadan tanımlı; cross-repo sync derdi yok.
9. **Signed transport** (ADR-0015) — Mac ↔ iOS arasında her envelope ed25519 imzalı; relay compromise immune.
10. **No backwards-compatibility hacks** — protocol break gerekiyorsa kırılır (v0.2.3'te `protocolVersion 1 → 2`); kod temiz kalır.

## v2'den çıkarılan dersler

Tüm liste: [docs/architecture-decisions-from-v2.md](architecture-decisions-from-v2.md).

Üç kritik anti-pattern v3'te yapısal olarak engellendi:
- **AppDelegate god class** (v2: 5.277 satır, 11 extension dosyası) → SwiftUI App lifecycle (ADR-0002)
- **Global backend singleton** → DI ile composition root'tan resolve (ADR-0009)
- **Cross-repo envelope sync derdi** (v2: 1100 satır iOS kodu Mac receiver yokken commit edilemedi) → `PixelRemote` paylaşılan modül (ADR-0008)
