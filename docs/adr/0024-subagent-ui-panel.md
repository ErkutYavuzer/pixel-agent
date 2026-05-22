# ADR-0024: Subagent UI Panel & Manager — Subagent Faz 3 (Paralel Cap + Bridge Birleşimi)

**Status:** Accepted (Faz 3 landed)
**Date:** 2026-05-22
**Tags:** subagent, ui, concurrency, mcp

## Context

[ADR-0019](0019-subagent-runner.md) Faz 1'de `PixelSubagent` library landed (`Budget` + `SubagentResult` + `SubagentRunner` actor); [ADR-0020](0020-mcp-dispatch-subagent.md) Faz 2'de MCP `dispatch_subagent` tool eklendi. İki noksan kaldı:

- **UI görünmezliği**: claude-cli'den dispatch edilen subagent çalışırken kullanıcı (ve izleyici) hiçbir geri bildirim göremiyor. Portfolio için zayıf demo.
- **Stateless bridge**: `ControlSocketServer.dispatchSubagent` her request fresh `CLIDetector` + `SubagentRunner` yaratıyor; UI'la koordine değil.

Faz 3 hedefi: composer'ın hemen üstünde yatay subagent kart şeridi; aktif/biten subagent'lar burada görünür; composer'a "Subagent" butonu ile UI'dan da dispatch edilebilir; MCP path'ten gelenler de **aynı panelde** belirir (birleşik).

Streaming partial output, multi-turn workflow, settings UI, kalıcı arşivleme **Faz 4+'a ertelendi** — Faz 3 kart sadece final result + elapsed timer gösterir.

## Decision

### Sorumluluk sınırı

`SubagentManager` PixelMacApp içinde (`Sources/PixelMacApp/Subagent/` alt dizini). Ayrı library yapılmadı:

- Manager `@Published` listesi + `@MainActor` ile SwiftUI lifecycle'a sıkı bağlı. PixelSubagent library bu yüke uzak durmalı (headless test edilebilir + executable-free).
- Tek consumer PixelMacApp; cross-target reuse senaryosu yok.

4 yeni dosya: `SubagentSession.swift`, `SubagentStatus.swift`, `SubagentManager.swift`, `SubagentPanelView.swift`.

### Concurrency: `@MainActor final class`, actor değil

`@Published var sessions` SwiftUI binding'i için MainActor isolation gerekiyor. Actor olsaydı her UI binding read için `await` gerekirdi, panel state update senkron olmaz. Cap atomicity zaten MainActor reentrancy yokluğu ile garanti — `dispatch` synchronous bir slice'ta count check + append yapar.

```swift
@MainActor
final class SubagentManager: ObservableObject {
    @Published private(set) var sessions: [SubagentSession]
    let maxConcurrent: Int = 3
    private var runners: [SubagentID: Task<Void, Never>]
    private var continuations: [SubagentID: CheckedContinuation<SubagentResult, Never>]
    private let backendResolver: @MainActor (CLIKind) -> (any ChatBackend)?
}
```

`dispatchAndWait` MCP path için: `dispatch` sync döner; başarılıysa `withCheckedContinuation` ile result-channel'ı `continuations[id]`'e koyar; `finalize` çalıştığında resume eder. MainActor reentrancy yokluğu race-free.

### Session = Runner ID

`SubagentSession.id: SubagentID = SubagentRunner.id` — TaskLocal binding (`AgentContext.currentSubagentID`) ile log/tracing tek source-of-truth. Manager Session create'inde id'yi ürettir, Runner'a aynı id'yi geçirir.

### MCP path birleşimi

`ControlSocketServer` artık actor field `manager: SubagentManager?` tutar. `RootView.task` modifier'ında `await RootView.controlServer.attach(subagentManager)` çağrılır (idempotent — son attach kazanır).

`dispatchSubagent`:
- Manager varsa: `manager.dispatchAndWait(...)` — havuza ekler, UI'da kart belirir, sonucu bekler. Cap dolu / backend yok → `BridgeResponse.failure(localizedDescription)`.
- Manager nil ise: eski stateless yol korunur — test target backwards compat.

`bridgeResponse(from:backendKind:)` ortak helper iki yolun da çıktısını aynı format'a normalize eder.

### Paralel cap = 3

Konservatif default; UI clutter ve sistem kaynak dostu. Cap aşılınca:
- UI: Composer'da "Subagent" butonu disabled + tooltip "Subagent havuzu dolu (3/3 aktif)"
- MCP: `BridgeResponse.failure("Subagent havuzu dolu...")` → MCP client'ta `isError: true`

Settings UI ile override Faz 4'e ertelendi.

### Bug fix: `SubagentRunner` cancel detection

[ADR-0019](0019-subagent-runner.md)'da "stream `.done` vermeden bitti → `.completed`" davranışı kasıtlıydı (CLI subprocess graceful exit). Ancak `Task.cancel()` sonrası `AsyncSequence` iteration sessizce sonlanır — bu da "stream end" sayılıyor, `.cancelled` yerine `.completed("")` dönüyordu.

Fix: `for try await` loop'tan çıktıktan sonra `Task.isCancelled` check eklendi. Cancel olmuşsa `.cancelled`, değilse `.completed` (mevcut graceful behavior korundu). Manager'in cancel akışı bu sayede doğru status verir.

### UI tasarımı

**`SubagentPanelView`**: `sessions.isEmpty` → `EmptyView` (ChatHost-level divider'lar da gizli). Dolu state: `ScrollView(.horizontal) + LazyHStack` + sol uçta `2/3` cap badge. Yeni kart eklenince `proxy.scrollTo(latestID, anchor: .trailing)`.

**`SubagentCardView`** (`220×56`):
- *running*: `ProgressView` (mini) + `TimelineView(.periodic)` ile saniye-saniye elapsed, accent color border, sağ üst ✕ (cancel).
- *completed*: ✓ yeşil + duration + prompt preview (40 char). Tap → detail sheet.
- *budgetExceeded / failed / cancelled*: turuncu/kırmızı ikon + status label + ✕ dismiss.

**`SubagentDetailSheet`**: full prompt + result.output (mono, scrollable) + "Çıktıyı kopyala" + "Kartı sil" + "Kapat".

**Composer butonu**: TextField'in sağında küçük borderless `Image(systemName: "person.2.wave.2")`. Disabled: draft boş / `isStreaming` / `subagentDisabled`. Kısayol `⌘⇧Return` — `.return` Send ile çakışmaz.

### ChatHost re-init `.id(backendsKey)`

Manager'in `backendResolver` closure'u backends dictionary snapshot'ını yakalıyor. Backends rescan (`RootView.rescan()`) yapılırsa `backendsKey` (sorted raw values, comma-joined) değişir → ChatHost re-init → Manager fresh resolver ile yenilenir. Trade-off: rescan'da aktif subagent kartları kaybolur — rescan zaten nadir bir event (kullanıcı CLI ekledi/sildi).

## Consequences

**Olumlu:**
- `PixelSubagent` library artık görsel temsile sahip — portfolio demo'su net.
- MCP-dispatched subagent'lar UI'da kart olarak görünür → claude-cli'den orchestration izlenebilir.
- Manager DI ile test edilebilir: 8 yeni `SubagentManagerTests` (dispatch, cancel, cap-reached, dispatchAndWait, dismiss).
- `SubagentRunner` cancel davranışı bug fix — partial output doğru status'la dönüyor.
- Bridge backwards compat: Manager nil ise mevcut testler eski stateless path'ten çalışır.

**Olumsuz:**
- `backendResolver` closure init zamanı snapshot; rescan'da ChatHost re-init gerekiyor → aktif sessions kayıp. Settings/Manager seviyesinde dinamik backend güncellemesi Faz 4'e ertelendi.
- Streaming partial output yok — kart sadece elapsed timer + final output gösterir. Uzun subagent'larda kullanıcı 30s+ "no progress" sanabilir.
- Tek SubagentManager instance ChatHost'a bağlı; dual mode'da iki backend için tek panel paylaşılır (dispatch sol backend default).

## Faz 4+ — gelecek (bu ADR'de değil)

- Streaming partial output: `SubagentRunner` yeni `runStreaming` API (AsyncStream of SubagentEvent).
- Multi-turn workflow API (sıralı + paralel pipeline).
- Settings UI: max cap, default budget, auto-dismiss timer.
- Dual mode'da Subagent backend picker (şu an sol backend default).
- ConversationStore'a kalıcı subagent arşivi (ayrı dosya).

## Alternatives

- **Panel yerine ayrı window** — discoverability düşük; "background" hissi yaratıyor ama composer'la birlikte iş yapmak için iki window switch zorluyor. Reddedildi.
- **Bridge stateless kalsın** — kullanıcı kararı ile birleşik istendi. MCP-dispatched subagent UI'da görünmüyorsa demo etkisi kaybolur. Reddedildi.
- **`SubagentManager` actor** — ObservableObject + actor isolation çatışıyor; ya bridge gerek ya da view her okuma için await. MainActor class tercih edildi.
- **Cap 5 ya da configurable** — Faz 3 scope minimum tutulur; settings Faz 4'e.
- **Closure backendResolver yerine `BackendCache` observable class** — daha live ama yeni reference type + RootView refactor. ID-based ChatHost reset daha az invasive (rescan nadir).

## References

- `Sources/PixelMacApp/Subagent/SubagentSession.swift`
- `Sources/PixelMacApp/Subagent/SubagentStatus.swift`
- `Sources/PixelMacApp/Subagent/SubagentManager.swift`
- `Sources/PixelMacApp/Subagent/SubagentPanelView.swift`
- `Sources/PixelMacApp/ControlSocketServer.swift` — `attach(_:)` + `dispatchSubagent` Manager path
- `Sources/PixelMacApp/PixelMacApp.swift` — `ChatHost` `@StateObject SubagentManager` + `.id(backendsKey)`
- `Sources/PixelMacApp/ChatComposer.swift` — Subagent buton + ⌘⇧Return
- `Sources/PixelMacApp/ChatView.swift` + `DualChatHost.swift` — panel entegrasyonu
- `Sources/PixelSubagent/SubagentRunner.swift` — cancel detection bug fix
- `Tests/PixelMacAppTests/SubagentManagerTests.swift` (8 yeni test)
- `Tests/PixelMacAppTests/ControlSocketServerTests.swift` (`testDispatchSubagentReturnsCapReachedWhenManagerFull` eklendi)
- [ADR-0019](0019-subagent-runner.md) — Subagent Faz 1
- [ADR-0020](0020-mcp-dispatch-subagent.md) — MCP `dispatch_subagent` Faz 2
- [ADR-0018](0018-mcp-bridge-unix-socket.md) — Unix socket bridge altyapısı
