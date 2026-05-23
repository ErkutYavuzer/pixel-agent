import Foundation

/// Menü çubuğu kısayollarının `NotificationCenter` üzerinden taşınmasını
/// type-safe yapan enum (B5).
///
/// `.commands { ... }` modifier'ında her menü öğesi karşılık gelen
/// `Notification.Name`'i post eder; ilgili view (ChatHost, ChatColumn vs.)
/// `.onReceive(NotificationCenter.default.publisher(for:))` ile dinler.
///
/// Saf değer — SwiftUI'a bağımlı değil, testten erişilebilir.
enum AppCommand: String, CaseIterable, Sendable {
    /// ⌘N — aktif ChatViewModel'in `newConversation()` metodunu çağırır.
    /// Dual mode'da her iki sütun ayrı ayrı dinler.
    case newConversation = "pixel.command.newConversation"

    /// ⌘⇧P — ChatHost'taki `planMode` toggle'ını flipler. Toolbar'daki
    /// buton ile aynı state'i değiştirir.
    case togglePlanMode = "pixel.command.togglePlanMode"

    /// ⌘⇧M — ChatHost'taki `mode`'u single ↔ dual arasında geçirir.
    case toggleChatMode = "pixel.command.toggleChatMode"

    var notificationName: Notification.Name {
        Notification.Name(rawValue)
    }

    /// Pratik post helper'ı — view kodunda `AppCommand.newConversation.post()`.
    func post() {
        NotificationCenter.default.post(name: notificationName, object: nil)
    }
}
