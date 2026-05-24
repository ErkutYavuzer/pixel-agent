import Foundation
import PixelCore

/// Arşivlenmiş bir conversation dosyasının metadata'sı (B2).
///
/// `ConversationStore.newConversation()` mevcut JSONL'i
/// `archive/conversation-<kind>-<ISO timestamp>.jsonl` formatında taşır.
/// Bu struct o dosya hakkında kullanıcı görünür bilgiyi taşır.
public struct ArchivedConversationEntry: Identifiable, Equatable, Sendable {
    /// Dosya URL'i — Identifiable id olarak yeterince stable.
    public let id: URL
    /// Backend kind raw string (`"claude"`, `"codex"`, `"gemini"`).
    public let backendKind: String
    /// Arşivleme zamanı — filename'den parse edilir.
    public let archivedAt: Date
    /// Dosyadaki mesaj satırı sayısı.
    public let messageCount: Int
    /// İlk user mesajının ilk 60 karakteri — sidebar'da hızlı tanıma için.
    public let firstUserSnippet: String?

    public init(
        id: URL,
        backendKind: String,
        archivedAt: Date,
        messageCount: Int,
        firstUserSnippet: String?
    ) {
        self.id = id
        self.backendKind = backendKind
        self.archivedAt = archivedAt
        self.messageCount = messageCount
        self.firstUserSnippet = firstUserSnippet
    }
}

/// Saf yardımcı — `conversation-<kind>-<ISO timestamp>.jsonl` filename'ini
/// parse eder. `ConversationStore.newConversation()` filename'i bu formatta
/// üretir; iki taraf da bu helper'ı share eder.
public enum ArchivedConversationParser {

    /// Filename'i `(kind, date)` çiftine parse eder; format uymuyorsa nil.
    ///
    /// İki desteklenen stamp formatı:
    /// - **Sprint 4+ (ms precision):** `YYYY-MM-DDTHH-MM-SS.sssZ` — 24 char
    /// - **Eski (sec precision):** `YYYY-MM-DDTHH-MM-SSZ` — 20 char (geriye uyum)
    ///
    /// Naïve "ilk T'den geri ilk -" yaklaşımı işe yaramıyor çünkü tarih
    /// kısmının kendi içinde '-' var (`YYYY-MM-DD`). Bu yüzden sabit
    /// uzunluk yaklaşımı: her iki uzunluğu sırayla dene.
    public static func parseFilename(_ filename: String) -> (kind: String, date: Date)? {
        guard let dotRange = filename.range(of: ".jsonl", options: .backwards) else {
            return nil
        }
        let base = String(filename[..<dotRange.lowerBound])

        let prefix = "conversation-"
        guard base.hasPrefix(prefix) else { return nil }

        // ms precision önce dene (yeni format); olmazsa sec precision'a düş.
        for stampLength in [24, 20] {
            guard base.count >= prefix.count + 1 + 1 + stampLength else { continue }
            let stampStart = base.index(base.endIndex, offsetBy: -stampLength)
            let stampPart = String(base[stampStart...])

            let dashIdx = base.index(before: stampStart)
            guard base[dashIdx] == "-" else { continue }

            let kindStart = base.index(base.startIndex, offsetBy: prefix.count)
            let kind = String(base[kindStart..<dashIdx])
            guard !kind.isEmpty else { continue }

            let restored = restoreColons(in: stampPart)
            let formatter = ISO8601DateFormatter()
            // Hem ms hem sec precision'ı kabul edebilecek format set.
            formatter.formatOptions = [
                .withInternetDateTime,
                .withColonSeparatorInTime,
                .withFractionalSeconds,
            ]
            if let date = formatter.date(from: restored) {
                return (kind, date)
            }
            // Fractional seconds opsiyonel — sec precision için de dene.
            formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
            if let date = formatter.date(from: restored) {
                return (kind, date)
            }
        }
        return nil
    }

    /// Stamp'teki T sonrası 3 `-` karakterini `:` ile değiştir (tarih kısmı
    /// dokunulmaz).
    private static func restoreColons(in stamp: String) -> String {
        guard let tIdx = stamp.firstIndex(of: "T") else { return stamp }
        let head = stamp[...tIdx]
        let tail = stamp[stamp.index(after: tIdx)...].replacingOccurrences(of: "-", with: ":")
        return String(head) + tail
    }

    /// Mesaj listesinden ilk **user** mesajının kısa preview'ı (60 char).
    public static func firstUserSnippet(messages: [Message]) -> String? {
        for message in messages where message.role == .user {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count <= 60 { return trimmed }
            return String(trimmed.prefix(60)) + "…"
        }
        return nil
    }
}
