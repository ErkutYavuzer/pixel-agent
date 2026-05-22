# ADR-0017: Plan Mode (Read-Only Allowlist)

**Status:** Accepted
**Date:** 2026-05-22
**Tags:** ui, backend, claude-cli

## Context

pixel-agent2 v2'de "Plan Mode" benzeri bir özellik vardı: kullanıcı yazılım hazırlığı yaparken (örneğin "şu repo'yu okuyup ne yaptığını anlat") agent'ın **dosyaya yazma / kabuk çalıştırma** yapmaması istenir. v3'te bu özellik v0.2 roadmap'inde "Plan Mode (read-only tool allowlist)" başlığıyla kalmıştı.

Claude CLI native olarak Plan Mode destekliyor (`--permission-mode plan`). Codex ve Gemini CLI'ların aynı bayrağı yok — kendi auth model'leri farklı.

## Decision

### `ChatOptions` struct

`PixelCore.ChatOptions` (yeni dosya):

```swift
public struct ChatOptions: Sendable, Equatable {
    public var planMode: Bool
    public init(planMode: Bool = false)
}
```

Bu yapı ileride genişler (temperature, maxTokens, tool allowlist'ler vb.). v0.2.4'te tek alan `planMode`.

### `ChatBackend` protokol genişletme

```swift
public protocol ChatBackend: Sendable {
    var modelID: String { get }
    func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error>
}

extension ChatBackend {
    public func send(messages: [Message], system: String?) -> AsyncThrowingStream<StreamDelta, any Error> {
        send(messages: messages, system: system, options: ChatOptions())
    }
}
```

Extension overload eski 2-arg call-site'ları kırmaz (`Tests/PixelCoreTests/MockChatBackendTests`, `Tests/PixelBackendsTests/CLIBackendTests` ekspisit 3-arg'a güncellendi; bunlar `ChatBackend` impl olduğu için ekstension overload yetmez).

### `CLIBackend.arguments(for:prompt:options:)`

**Claude:**
```swift
if options.planMode {
    args.append(contentsOf: ["--permission-mode", "plan"])
}
```
Read/Glob/Grep tool'ları aktif; Edit/Write/Bash kapalı. Spec: docs.anthropic.com/claude/cli.

**Codex:** native plan flag yok — `options.planMode == true` olsa bile args değişmez. Sessizce normal flow.

**Gemini:** aynı — no-op.

### UI

`PixelMacApp` top bar'a `Toggle(.button)` eklendi (`Plan` label + `list.bullet.clipboard` icon). `@State planMode` → ChatView (single) ve DualChatHost (dual) constructor'larına `planMode: Bool` parametresi olarak geçirilir. Hem ChatView hem DualChatHost `.onAppear` + `.onChange(of: planMode)` ile child `ChatViewModel.planMode`'a propagate eder.

`ChatComposer` plan mode aktifken:
- Placeholder metni "Mesaj yaz..." → "Plan modu — sadece okuma/araştırma"
- TextField'a turuncu kontur (RoundedRectangle, 1.5px, opacity 0.55) overlay

Toggle tooltip'i selected backend Claude değilse uyarır: *"Plan modu yalnızca Claude için aktif; \(displayName) bu bayrağı yoksayar"*.

### State scope

`planMode` **per-app-launch in-memory** (UserDefaults persist YOK). Açılışta off. Gelecekte session-level persist gerekirse `@AppStorage` ile eklenir.

## Consequences

**Olumlu:**
- v2'nin Plan Mode'a denk fonksiyon. v0.2.4 release notlarına gider.
- `ChatOptions` struct ileride başka opsiyonlar için temiz extension noktası.
- Backend-agnostic UI: Codex/Gemini selectiliyken toggle hâlâ aktif ama side-effect'siz (tooltip kullanıcıyı bilgilendirir).

**Olumsuz:**
- Codex/Gemini'de "Plan Mode" toggle aktif ama hiçbir şey yapmıyor — kullanıcı kafa karışıklığı riski. Tooltip mitigation. Faz 2'de Picker veya disable yapılabilir.
- Plan Mode'da Claude `--permission-mode plan` çıktısı normal stream-json formatında — özel UI gösterimi yok (örneğin "Plan: ..." başlık satırı). Faz 2'de görsel ipucu eklenebilir.

## Alternatives

- **`ChatBackend.send(...)` overload yerine yeni method `plan(messages:)`**: tasarımı dağıtır, mevcut backend impl'ların hepsini değiştirir.
- **`PlanMode: Bool` `CLIBackend` init param**: konstrüksüyon-zamanı; her plan mode toggle yeniden backend yaratmak gerekir. Reddedildi.
- **Codex/Gemini'de plan mode'u disable**: Picker change'inde state kaybı + UI complexity. Kullanıcının tek bir global toggle'ı olması daha tutarlı.

## References

- [Claude CLI permission-mode docs](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code/permissions)
- `Sources/PixelCore/ChatOptions.swift`
- `Sources/PixelBackends/CLIBackend.swift` (`arguments(for:prompt:options:)`)
- `Sources/PixelMacApp/{PixelMacApp,ChatView,DualChatHost,ChatComposer,ChatViewModel}.swift`
- `Tests/PixelBackendsTests/CLIBackendTests.swift` (4 yeni test)
