# pixel-agent Architecture

## Modül grafiği

```mermaid
graph TD
    App[PixelMacApp executable]
    Core[PixelCore]
    Backends[PixelBackends]
    Tools[PixelTools]
    Memory[PixelMemory]
    Mascot[PixelMascot]
    Remote[PixelRemote]

    App --> Core
    App --> Backends
    App --> Tools
    App --> Memory
    App --> Mascot
    App --> Remote
    Backends --> Core
    Tools --> Core
    Memory --> Core
    Remote --> Core
```

**Bağımlılık disiplini:** Tüm oklar `PixelCore`'a doğru. Hiçbir modül `PixelMacApp`'i import etmez. Modüller arası bağımlılık döngüsü SPM tarafından compile-time bloklanır.

## Sohbet akışı (planned, Hafta 2)

```mermaid
sequenceDiagram
    participant User
    participant ChatView as ChatView (SwiftUI)
    participant Backend as AnthropicBackend
    participant Memory as MemoryStore

    User->>ChatView: "Bana yardım et"
    ChatView->>Memory: append(userMessage)
    ChatView->>Backend: stream(messages)
    Backend-->>ChatView: StreamDelta(token)
    Backend-->>ChatView: StreamDelta(token)
    Backend-->>ChatView: StreamDelta(done)
    ChatView->>Memory: append(assistantMessage)
```

## Tool dispatch akışı (planned, Hafta 3)

```mermaid
sequenceDiagram
    participant Backend
    participant Dispatcher as ToolDispatcher
    participant Arbiter as ToolArbiter
    participant Tool as ReadFileTool

    Backend->>Dispatcher: dispatch(name: "read_file", args)
    Dispatcher->>Arbiter: acquire([.fileWrite("/path")])
    Arbiter-->>Dispatcher: granted
    Dispatcher->>Tool: execute(args)
    Tool-->>Dispatcher: result
    Dispatcher->>Arbiter: release([.fileWrite("/path")])
    Dispatcher-->>Backend: toolResult
```

TaskLocal context (`currentAgent`, `currentSubagentID`) tüm zincir boyunca propagate olur (ADR-0003).

## Future: Mac ↔ iOS akışı (planned, Hafta 5)

```mermaid
sequenceDiagram
    participant iOS as iOS App
    participant Relay as Cloudflare Worker
    participant Mac as PixelMacApp

    iOS->>Relay: WS connect /listen/{macID}
    Mac->>Relay: WS connect /connect/{macID}
    Relay-->>iOS: ready
    Relay-->>Mac: ready

    iOS->>Relay: Envelope(type=userMessage)
    Relay->>Mac: Envelope(type=userMessage)
    Mac->>Mac: handle message
    Mac->>Relay: Envelope(type=assistantMessage, final=false)
    Relay->>iOS: Envelope(type=assistantMessage, final=false)
    Mac->>Relay: Envelope(type=assistantMessage, final=true)
    Relay->>iOS: Envelope(type=assistantMessage, final=true)
```

Envelope tipleri `PixelRemote` modülünde tanımlı; her iki tarafta aynı Swift kodu (ADR-0008).

## Katman dağılımı

| Katman | Sorumluluk | Modüller |
|---|---|---|
| **UI** | SwiftUI view'lar, scene lifecycle | `PixelMacApp` |
| **Orchestration** | Sohbet akışı, agent state, scenedeki business logic | `PixelMacApp` (composition root) |
| **Domain protocols** | `ChatBackend`, `Envelope`, TaskLocal primitives | `PixelCore` |
| **Implementations** | Provider, tool, storage somut sınıflar | `PixelBackends`, `PixelTools`, `PixelMemory` |
| **Cross-cutting** | Mascot render, remote protocol | `PixelMascot`, `PixelRemote` |

## Tasarım prensipleri

1. **Dependency injection over singletons** (ADR-0009) — `ToolArbiter.shared` istisna, kalan her şey injected.
2. **TaskLocal scoping over global state** (ADR-0003) — context çağrı ağacında propagate olur.
3. **Protocol-driven abstraction** (ADR-0004) — yeni provider eklemek tek dosya yazımı.
4. **Hermetic testing** (ADR-0007) — network'siz, deterministic test suite.
5. **Append-only storage** (ADR-0006) — durability + portability.
