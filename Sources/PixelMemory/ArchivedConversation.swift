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
    /// Beklenen pattern:
    ///   `conversation-<kind>-<YYYY-MM-DDTHH-MM-SSZ>.jsonl`
    /// `<stamp>` `ConversationStore`'un ürettiği — orijinal ISO8601'in
    /// ':'leri '-' ile değiştirilmiş hali, **20 char sabit uzunluk**.
    ///
    /// Naïve "ilk T'den geri ilk -" yaklaşımı işe yaramıyor çünkü tarih
    /// kısmının kendi içinde '-' var (`YYYY-MM-DD`). Bu yüzden sabit
    /// uzunluk yaklaşımı: stamp tam 20 char, hemen öncesinde bir '-' var,
    /// öncesi `conversation-<kind>`.
    public static func parseFilename(_ filename: String) -> (kind: String, date: Date)? {
        // Strip extension
        guard let dotRange = filename.range(of: ".jsonl", options: .backwards) else {
            return nil
        }
        let base = String(filename[..<dotRange.lowerBound])

        let prefix = "conversation-"
        guard base.hasPrefix(prefix) else { return nil }

        let stampLength = 20  // "2026-05-24T10-30-15Z" = 20 char
        // Yeterli uzunluk: prefix + en az 1 char kind + 1 '-' + 20 char stamp
        guard base.count >= prefix.count + 1 + 1 + stampLength else { return nil }

        let stampStart = base.index(base.endIndex, offsetBy: -stampLength)
        let stampPart = String(base[stampStart...])

        // Stamp'ten hemen önce '-' olmalı (kind ile ayraç).
        let dashIdx = base.index(before: stampStart)
        guard base[dashIdx] == "-" else { return nil }

        let kindStart = base.index(base.startIndex, offsetBy: prefix.count)
        let kind = String(base[kindStart..<dashIdx])
        guard !kind.isEmpty else { return nil }

        let restored = restoreColons(in: stampPart)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        guard let date = formatter.date(from: restored) else { return nil }

        return (kind, date)
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
