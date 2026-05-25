import Foundation
import PixelMemory

/// Sprint 6 (B2): Sidebar / iOS list / payload — hepsi aynı düşüş zincirini
/// kullansın diye saf helper. View'dan ayrık; doğrudan test edilebilir.
///
/// Düşüş zinciri:
/// 1. `customTitle` (kullanıcı rename'i, whitespace-trim sonrası)
/// 2. `firstUserSnippet` (otomatik preview)
/// 3. `"(başlıksız)"` (her ikisi de yoksa veya boşsa)
public enum ArchiveTitleResolver {
    public static let placeholder = "(başlıksız)"

    public static func displayTitle(for entry: ArchivedConversationEntry) -> String {
        if let custom = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        if let snippet = entry.firstUserSnippet?.trimmingCharacters(in: .whitespacesAndNewlines),
           !snippet.isEmpty {
            return snippet
        }
        return placeholder
    }
}
