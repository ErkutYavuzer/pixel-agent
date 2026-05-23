import Foundation
import PixelCore

/// Quick-actions menü/buton akışında "Son yanıtı kopyala" gibi işlemler için
/// hangi mesajın hedef olduğunu hesaplayan saf yardımcı (B6).
///
/// Demo-readiness kriteri (audit B6): "Per-message actions (copy/regenerate/edit)
/// yok — en azından kopya akışı eklenmeli."
enum MessageActionsHelper {
    /// Mesaj listesinde sondan başlayarak ilk **dolu** asistan mesajını
    /// bulup metnini döner. Boş (streaming başlangıcı, errored boş) veya
    /// whitespace-only asistan mesajları atlanır — kullanıcı bunları
    /// kopyalamak istemez.
    static func lastCopyableAssistantText(in messages: [Message]) -> String? {
        for message in messages.reversed() {
            guard message.role == .assistant else { continue }
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return message.text
            }
        }
        return nil
    }
}
