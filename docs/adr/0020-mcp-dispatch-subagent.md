# ADR-0020: MCP `dispatch_subagent` — Subagent Faz 2 (Headless Orchestration)

**Status:** Accepted (Faz 2 landed)
**Date:** 2026-05-22
**Tags:** mcp, subagent, orchestration

## Context

[ADR-0019](0019-subagent-runner.md) Faz 1'de `PixelSubagent` library landed: `Budget` + `SubagentResult` + `SubagentRunner` actor. Standalone testlerle 15 case kapsandı ama hiçbir caller bağlı değildi — library "wired" değildi.

Subagent Faz 2 için iki olası caller:
1. **UI integration** — chat composer'dan dispatch, background panel.
2. **MCP tool** — `dispatch_subagent` ile claude-cli ve uyumlu istemcilerden orchestration.

İki seçenek arasında MCP tool seçildi çünkü:
- v0.2.4'te eklenen MCP Faz 2 bridge'i ([ADR-0018](0018-mcp-bridge-unix-socket.md)) hazır — dispatch tek bir yeni `case` ile entegre.
- Headless / scriptable — UI olmadan da çalışır; CI / batch job için kullanılır.
- Multi-backend orchestration: claude-cli, kendisi MCP üzerinden Codex'i veya Gemini'i çağırabilir. Cross-model workflow için temel.
- UI integration ileride bunu kullanabilir (Faz 3) — temel API zaten orada olur.

## Decision

### MCP tool

`dispatch_subagent` bridge tool (`BuiltInTools` registry'sine eklendi, 8 → 9 tool):

```json
{
  "name": "dispatch_subagent",
  "inputSchema": {
    "type": "object",
    "properties": {
      "prompt":                {"type": "string"},
      "backend":               {"type": "string", "enum": ["claude", "codex", "gemini"]},
      "max_duration_seconds":  {"type": "number"},
      "max_output_bytes":      {"type": "integer"}
    },
    "required": ["prompt", "backend"]
  }
}
```

Response payload (JSON içinde structured):

```json
{
  "status": "completed" | "budget_exceeded" | "cancelled" | "failed",
  "output": "...",
  "duration_seconds": 3.4,
  "backend": "claude"
}
```

`ToolResultBuilder` `content[0].text` alanına pretty-printed JSON koyar — claude-cli bunu parse edebilir.

### Bridge handler (`ControlSocketServer`)

`execute(request:)` switch'ine yeni `"dispatch_subagent"` case:

1. Parse: `prompt` (zorunlu, boş değil), `backend` (`CLIKind` raw value), opsiyonel `max_duration_seconds` (default 60), opsiyonel `max_output_bytes`.
2. Backend resolve: her request'te fresh `CLIDetector` — kullanıcı CLI'larını ekleyebilir/kaldırabilir, cache YOK.
3. `CLIBackend(kind:, executablePath:)` construct.
4. `Budget(maxDuration:, maxOutputBytes:)`; minimum 1s clamp.
5. `SubagentRunner(backend:, budget:).run(prompt:)`.
6. `SubagentResult` → `BridgeResponse`: `.completed` success, diğerleri `ok: false` ama `result` structured payload doluyla.

### Long-running RPC limitation

Bridge tasarımı (ADR-0018) **single-shot blocking RPC**. Subagent uzun sürüyorsa bağlantı süresince bridge açık kalır. Etkileri:

- MCP client (claude-cli vs.) kendi timeout'u ile sınırlı.
- `max_duration_seconds`'ı MCP client'ın timeout'unun **altında** tutmak kullanıcı sorumluluğu.
- Aynı anda birden çok subagent çağrısı: accept loop yeni bağlantıyı her zaman kabul eder (her bağlantı Task içinde dispatch); paralel SubagentRunner'lar çalışabilir.

Streaming protocol (sub-result chunks) v3 scope'unda değil. Faz 3+'ta partial output progress notification eklenebilir.

### Backend resolution

Her request'te fresh `CLIDetector` çağırılır. PixelMacApp'in `RootView.backends` state'i ile koordine değil — bunlar bağımsız state'ler. Avantaj: kullanıcı CLI yüklerse rescan gerektirmez. Maliyet: file system check her request'te tekrar.

## Consequences

**Olumlu:**
- `PixelSubagent` library artık caller'a sahip — sadece Faz 1 test'lerle değil, gerçek MCP transport üzerinden de exercise oldu.
- `claude-cli` üzerinden Codex/Gemini orchestration mümkün — örnek workflow: "claude bu repoyu okusun, sonra `dispatch_subagent(backend: codex, prompt: ...)` ile Codex'e refactor yaptırsın".
- Test ve docs maliyeti düşük (3 yeni edge-case test + 1 ADR + tool schema docstring).

**Olumsuz:**
- Long-running bağlantı: 60s+ subagent'larda MCP client timeout riski. Mitigation: kullanıcı budget'ı küçük tutar.
- "Status" payload structured ama MCP `content[0].text`'e JSON string olarak gömülüyor — caller parse etmeli. claude-cli için OK; daha eski client'lar plain text bekleyebilir.
- ControlSocketServer artık `PixelBackends` + `PixelSubagent` + `PixelCore` import ediyor — dependency surface büyüdü. Acceptable çünkü PixelMacApp zaten hepsini import ediyor.

## Faz 3+ — gelecek (bu ADR'de değil)

- UI integration: PixelMacApp chat composer'ında "Background subagent" butonu; sidebar/sheet'te aktif subagent listesi (status indicator + cancel + result toast).
- Multi-turn `Workflow` API: birden çok `SubagentRunner.run` çağrısını seri/paralel bağlama.
- Streaming progress: bridge'te long-living connection + chunked partial output. Veya HTTP server-sent events.
- Subagent çıktısının `ConversationStore`'a ayrı dosyada arşivlenmesi.

## Alternatives

- **UI Faz 2'yi önce yap, MCP'yi Faz 3'e ertele**: portfolio için görsel demo etkisi UI'nın. Ama MCP entegrasyonu daha düşük scope ve test edilebilir. Reddedildi (sıra: MCP → UI).
- **Synchronous yerine async pattern (`dispatch_subagent_start` + `dispatch_subagent_poll`)**: client'ın poll loop yazması gerekir; MCP tool kullanımı pratik değil. Reddedildi.
- **Backend instance'ları cache'le**: her request'te fresh detect var. Cache eklersek kullanıcı CLI değişikliğine cevap vermez. Şu an cache yok; gerekirse ileride opt-in eklenebilir.

## References

- `Sources/PixelMacApp/ControlSocketServer.swift` — `dispatchSubagent(_:)`
- `Sources/PixelMCPServer/ToolRegistry.swift` — `BuiltInTools.dispatchSubagent`
- `Sources/PixelSubagent/SubagentRunner.swift` (ADR-0019)
- `Tests/PixelMacAppTests/ControlSocketServerTests.swift` (3 yeni edge-case test)
- [ADR-0018](0018-mcp-bridge-unix-socket.md) — MCP Faz 2 bridge
- [ADR-0019](0019-subagent-runner.md) — Subagent Faz 1
