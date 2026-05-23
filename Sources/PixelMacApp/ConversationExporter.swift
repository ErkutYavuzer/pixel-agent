import Foundation
import PixelCore

/// Sohbeti markdown veya JSON formatına dökme (B3).
///
/// Saf — view'dan ve dosya sisteminden bağımsız test edilebilir. UI tarafı
/// `NSSavePanel` ile dosyaya yazar; biz sadece içerik üretiriz.
enum ConversationExportFormat: String, CaseIterable, Sendable, Identifiable {
    case markdown = "md"
    case json = "json"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        }
    }

    var fileExtension: String { rawValue }
}

enum ConversationExporter {

    /// Sohbeti markdown'a çevirir. Her mesaj `## <Role>` başlığı altında.
    /// Boş listede minimal placeholder verir.
    static func markdown(
        messages: [Message],
        title: String = "pixel-agent conversation",
        now: Date = Date()
    ) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var output = "# \(title)\n\n"
        output += "_Exported: \(iso.string(from: now))_\n"
        if messages.isEmpty {
            output += "\n_No messages._\n"
            return output
        }
        for message in messages {
            output += "\n## \(heading(for: message.role))\n\n"
            output += message.text
            if !message.text.hasSuffix("\n") {
                output += "\n"
            }
        }
        return output
    }

    /// Sohbeti JSON dizisine çevirir. Message zaten Codable; pretty + sorted
    /// + iso8601 date — diff-friendly.
    static func json(messages: [Message]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(messages)
        return String(decoding: data, as: UTF8.self)
    }

    /// `pixel-agent-2026-05-24-1234.md` benzeri default dosya adı.
    static func defaultFilename(
        for format: ConversationExportFormat,
        now: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: now)
        return "pixel-agent-\(dateString).\(format.fileExtension)"
    }

    // MARK: - Internals

    private static func heading(for role: MessageRole) -> String {
        switch role {
        case .user: return "User"
        case .assistant: return "Pixel"
        case .system: return "System"
        }
    }
}
