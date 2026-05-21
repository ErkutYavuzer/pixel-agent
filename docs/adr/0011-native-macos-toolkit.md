# ADR-0011: Native macOS Toolkit (CLI Tool Wrapper Değil)

**Status:** Accepted
**Date:** 2026-05-21
**Tags:** architecture, scope, tools

## Context

Lean MVP planında `PixelTools` modülünün başlangıç scope'u şuydu: "ToolDispatcher + ToolArbiter + 6 araç (read_file, write_file, list_dir, run_shell, screenshot, web_fetch)" — Anthropic API'sinin tool_use formatına entegre LLM tool çağrıları.

Hafta 2.5'te [ADR-0010](0010-cli-subprocess-backend.md) ile HTTP API silinip CLI subprocess'lere geçildi. Bu, tool sistemi sorusunu yeniden açtı: çünkü Claude Code, Codex ve Gemini CLI'larının **kendi tool sistemleri var** — `Bash`, `Read`, `Write`, `Edit`, `WebFetch`, `Glob`, vb. Kullanıcı "dosya oku" dediğinde Claude kendi `Read` aracını çağırır, biz hiç araya girmeyiz.

Bu durumda `PixelTools`'un eski scope'u (read_file/write_file/...) artık değer üretmiyor — CLI'nın paralelinde aynı işi yapmak olur.

## Decision

`PixelTools` modülünün scope'u **pixel-agent'ın CLI'lara değer kattığı native macOS özelliklerine** dönüştürüldü:

- **`DockBadge`** — `NSApp.dockTile.badgeLabel` wrap. Yanıt geldiğinde "1", hata olduğunda "!".
- **`SystemNotifications`** — `UNUserNotificationCenter` ile macOS bildirimi. Uygulama arka plandayken stream tamamlandığında push.
- **`SoundEffect`** — `NSSound` ile sistem sesleri (Glass = mesaj geldi, Basso = hata, Tink = nötr beep).

İlerideki adımlar: menu bar item (`NSStatusItem`), pasteboard helper, screencapture wrapper, system idle detection, NSWorkspace integration.

LLM tool çağrısı **bizim katmanımızda yok**. CLI'lar zaten kendi tool sistemlerine sahip; biz orchestration üzerinden bir şey yapmıyoruz — kullanıcının mesajını CLI'ya iletiyoruz, CLI tool'larını kendi çağırıyor.

## Alternatives considered

- **CLI'lara paralel HTTP tool sistemi** (eski plan) — duplikasyon; aynı `Read` iki yerde, hangisi authoritative belirsiz.
- **Prompt-engineering tool sistemi** — biz LLM'e "şu format'ta tool çağır" diye prompt veririz; çıktıyı parse edip biz çalıştırırız. CLI'nın native tool desteğini bypass'lar, daha kırılgan.
- **MCP server olarak çalış** — pixel-agent kendi MCP server'ı çalıştırır, CLI'lar bağlanır. MVP için ciddi overhead; ileride değerlendirilebilir (v0.2+).

## Consequences

**Positive**
- CLI'lar ile çakışma yok; iki kez tool çalıştırma riski sıfır.
- `PixelTools` modülü açıkça pixel-agent'ın UX katmanı — mascot animasyonu, sistem bildirimi gibi şeyler. CLI'nın yapamayacağı yerli özellikler.
- ChatView entegrasyonu basit: stream başlat → `MascotView` state .thinking; ilk chunk → .speaking; .done → .idle + opsiyonel `SystemNotifications.post` + `DockBadge.set`.
- `MascotView` portfolio değeri yüksek — görsel imza.

**Negative / tradeoffs**
- "Tool" kelimesi kafa karıştırıcı: PixelTools artık LLM-callable tool değil, native macOS toolkit. İsim değiştirilebilirdi (PixelKit, PixelAffordances) ama modül adı zaten Package.swift'te referans verilen; rename maliyeti var. v0.2'de düşünülür.
- Bazı kullanıcıların talep edebileceği şeyler (örn. "pixel'in kendi sandboxed Python interpreter'ı") bu scope dışı. CLI üzerinden yapılacak.

## Lessons from pixel-agent2

v2'de `PixelAgent` 87 tool'a sahipti — hepsi pixel'in kendi tool sistemi içinde. Bu büyük bir geliştirme yükü idi (tool wrap, schema render, format adapter her provider için). v3'te CLI subprocess kararı (ADR-0010) bunu sıfıra indirdi: CLI'nın kendi tool seti zaten orada, bizim tekrar yazmamıza gerek yok. Bu, MVP scope'unu önemli ölçüde küçülttü.

## References

- [ADR-0010 — CLI subprocess backend](0010-cli-subprocess-backend.md)
- [ADR-0005 — ToolArbiter resource mutex](0005-toolarbiter-resource-mutex.md) — şu an MVP'de kullanılmıyor; v0.2+'da pixel-agent kendi native tool'ları (örn. screenshot, system idle) çoğalırsa devreye girer.
