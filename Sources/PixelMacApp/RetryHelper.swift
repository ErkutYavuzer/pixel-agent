import Foundation
import PixelCore

/// Stream hata sonrasında "Tekrar dene" butonunun hangi user metnini yeniden
/// göndereceğine karar veren saf yardımcı (A7).
///
/// Send mantığı `messages` listesine `[user, emptyAssistant]` çifti append eder.
/// Hata gelirse bu çift listenin sonunda kalır. Retry:
///   1. Bu çifti listeden çıkar (chat history "başarısız tur" görüntüsü taşımasın).
///   2. user.text'i tekrar `send(text:)`'e ver.
///
/// Saf — SwiftUI ve ChatViewModel'den bağımsız test edilebilir.
enum RetryHelper {
    /// Mesaj listesinde son `[user, assistant]` çiftini bulursa user metnini
    /// döner; aksi halde nil (tutarsız state, henüz hiç tur yok, vb.).
    static func candidateRetryText(messages: [Message]) -> String? {
        guard messages.count >= 2 else { return nil }
        let last = messages[messages.count - 1]
        let prev = messages[messages.count - 2]
        guard last.role == .assistant, prev.role == .user else { return nil }
        let trimmed = prev.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : prev.text
    }
}
