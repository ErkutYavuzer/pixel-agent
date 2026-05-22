import Foundation

/// Bir sohbet turunda backend'e geçilen ek seçenekler.
///
/// İleride genişler (temperature, maxTokens, tool allowlist, vs.). Varsayılan
/// `ChatOptions()` v0.1.x davranışına eşdeğer — backward-compat extension
/// overload'u bu varsayılanı kullanır.
public struct ChatOptions: Sendable, Equatable {
    /// `true` ise backend "plan mode"da çalışır: sadece read-only tool'lar
    /// (Claude CLI'da `--permission-mode plan`). Codex/Gemini için no-op.
    public var planMode: Bool

    public init(planMode: Bool = false) {
        self.planMode = planMode
    }
}
