# ADR-0010: CLI Subprocess Backend (API yerine)

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, multi-provider, anti-pattern-prevention

## Context

`PixelBackends` modülü ilk olarak `AnthropicBackend` ile başladı — doğrudan HTTP API çağrısı (URLSession + SSE streaming). Bu basit ve hızlıydı, ancak birkaç pratik dezavantaj ortaya çıktı:

1. **API key yönetimi**: Kullanıcının ayrıca `ANTHROPIC_API_KEY` ENV var set etmesi gerekti; halbuki CLI'larda OAuth/login zaten yapılı (Claude Code, Codex, Gemini CLI hepsi kendi kimlik doğrulama state'ini tutuyor).
2. **Model seçimi yükü**: Her provider için Settings'te ayrı model dropdown gerekirdi; CLI'lar `--model` flag'iyle kendi model katalogunu yönetiyor zaten.
3. **Fatura tek yerde**: Kullanıcı zaten Claude Code, Codex, Gemini CLI'larını kuruyorsa hesap kullanım/fatura orada görünüyor. App'in ayrı API key'i ek fatura kaynağı.
4. **Çoklu provider sade**: Aynı pattern (subprocess + stdout streaming) tüm provider'lar için uygulanır. HTTP API ise her provider için ayrı endpoint/auth/format demektir.

## Decision

`PixelBackends` doğrudan HTTP API çağrısı yapmaz. `CLIBackend` struct'ı üç CLI'yi subprocess olarak çağırır:

- `claude` (Claude Code CLI) — `claude -p "<prompt>"`
- `codex` (OpenAI Codex CLI) — `codex -p "<prompt>"`
- `gemini` (Google Gemini CLI) — `gemini -p "<prompt>"`

`CLIDetector` yüklü CLI'ları bilinen path'lerden (`/usr/local/bin`, `/opt/homebrew/bin`, `$HOME/.local/bin`, `$HOME/bin`) ve fallback `which` arama ile tespit eder. `CLIProcessRunner` ortak `Process` wrapper'ı stdin/stdout/stderr'i `AsyncThrowingStream<String, Error>` olarak satır satır yayar.

Composition root (`RootView`) açılışta detector çalıştırır; en az bir CLI yüklü değilse `ErrorView` gösterir. Kullanıcı `ChatHost` üstündeki segmented Picker ile anlık olarak backend değiştirebilir; mesaj history korunur.

## Alternatives considered

- **HTTP API ile devam (Anthropic + diğerleri)** — her provider için ayrı auth/endpoint/format kodu gerekir; API key kullanıcıya ek yük; faturalar dağılır.
- **MCP server olarak çalış** — CLI'lar Model Context Protocol destekliyor; teorik olarak MCP server kurup içinden iletişim. MVP için aşırı overhead.
- **Provider SDK'sı (Anthropic/OpenAI/Google Swift SDK)** — Anthropic'in resmi Swift SDK'sı yok (Mayıs 2026); Python/JS var. Subprocess en pratik.

## Consequences

**Positive**
- Sıfır API key yönetimi — kullanıcının var olan login/OAuth state'i reuse edilir.
- Yeni provider eklemek = yeni `CLIKind` case + (gerekirse) farklı argüman builder.
- Test'lerde gerçek subprocess kullanılır (`echo`, `printf`, `cat`); mock framework gerekmez.
- Her CLI'nın native özelliklerini (tool use, MCP, skills, agents) ileride aktarmak kolay — sadece CLI flag'leri yeter.

**Negative / tradeoffs**
- Streaming granülaritesi CLI çıktısına bağlı; `claude -p` text mode'da tek block döner (stream görünmez). İleride `--output-format stream-json` parser eklenebilir.
- Cross-platform değil: Linux/Windows'ta path detection farklı. macOS-only MVP için sorun yok.
- Her mesajda yeni subprocess spawn maliyeti var; HTTP keepalive'a göre marjinal daha yavaş ama chat use-case'inde fark edilmez.

## Lessons from pixel-agent2

v2'de `ClaudeCLIClient` + `CodexCLIClient` zaten subprocess wrapper'larıydı. HTTP `ClaudeClient` (REST API) onlarla paralel duruyordu, ama pratik kullanımda CLI wrapper'lar çok daha sık tercih edildi — çünkü kullanıcının OAuth/quota'sı CLI'da. v3'te bu öğrenme baştan uygulandı: HTTP API geçici olarak Hafta 2'de vardı, bu ADR ile temiz silindi.

## References

- ADR-0004 (ChatBackend protocol)
- ADR-0005 (ToolArbiter — subprocess shell çağrıları için mutex)
- ADR-0009 (DI over singletons — backend `CLIDetector` ile composition root'ta resolve edilir)
- [docs/architecture-decisions-from-v2.md](../architecture-decisions-from-v2.md) — v2'nin CLI wrapper deseni
