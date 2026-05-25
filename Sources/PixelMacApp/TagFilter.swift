import Foundation
import PixelMemory

/// Sprint 7 (B2): Sidebar filter — saf helper, view'dan ayrık → testable.
///
/// Davranış (AND-of-OR ya da OR? Kullanıcı beklentisi: çoklu tag seçilirse
/// "bunlardan en az birini içeren" entry'ler gelsin = **OR / union**).
/// Boş set → filtre yok, tüm entry'ler döner.
public enum TagFilter {
    /// Entry'leri verilen aktif tag set'ine göre filter eder. Boş set
    /// "filtre yok" anlamına gelir (tüm entry'ler dönder).
    public static func apply(
        entries: [ArchivedConversationEntry],
        activeTags: Set<String>
    ) -> [ArchivedConversationEntry] {
        guard !activeTags.isEmpty else { return entries }
        return entries.filter { entry in
            !activeTags.isDisjoint(with: Set(entry.tags))
        }
    }
}
