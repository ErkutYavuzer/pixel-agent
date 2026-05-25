import Foundation
import PixelRemote

/// **Sprint 9 (v0.2.34):** Mac'in `ArchiveTitleResolver` (PixelMemory'i
/// kullanır) iOS karşılığı. iOS `PixelMemory`'i bağımlı değil; yalnız
/// `PixelRemote.ArchiveEntryPayload`'a erişimi var. Saf helper, View'dan
/// ayrık — gelecekte iOS test target eklenirse doğrudan test edilebilir.
enum IOSArchiveTitleResolver {
    static let placeholder = "(başlıksız)"

    /// Düşüş zinciri: `customTitle` (trim) > `firstUserSnippet` (trim) >
    /// `"(başlıksız)"`. Mac tarafı (v0.2.31 rename) ile birebir aynı kural.
    static func displayTitle(for entry: ArchiveEntryPayload) -> String {
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

    /// Row'da gösterilen kısa tag özeti — ilk 3 tag `#x #y #z` + fazlası
    /// `+N`. Boş listede boş string. Mac'in `tagInlineSummary` paralelliği.
    static func tagInlineSummary(_ tags: [String]?) -> String {
        guard let tags, !tags.isEmpty else { return "" }
        let visible = tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        if tags.count > 3 {
            return "\(visible) +\(tags.count - 3)"
        }
        return visible
    }
}
