import XCTest
import PixelCore

@testable import PixelMacApp

final class ConversationExporterTests: XCTestCase {

    // MARK: - Markdown

    func testMarkdownEmptyMessagesProducesPlaceholder() {
        let md = ConversationExporter.markdown(messages: [])
        XCTAssertTrue(md.contains("# pixel-agent conversation"))
        XCTAssertTrue(md.contains("_No messages._"))
    }

    func testMarkdownIncludesCustomTitle() {
        let md = ConversationExporter.markdown(messages: [], title: "Test Run")
        XCTAssertTrue(md.contains("# Test Run"))
        XCTAssertFalse(md.contains("pixel-agent conversation"))
    }

    func testMarkdownUserAssistantPair() {
        let msgs = [
            Message(role: .user, text: "merhaba"),
            Message(role: .assistant, text: "selam!"),
        ]
        let md = ConversationExporter.markdown(messages: msgs)
        XCTAssertTrue(md.contains("## User\n\nmerhaba"))
        XCTAssertTrue(md.contains("## Pixel\n\nselam!"))
        // Sıra: User önce
        let userIdx = md.range(of: "## User")!
        let pixelIdx = md.range(of: "## Pixel")!
        XCTAssertLessThan(userIdx.lowerBound, pixelIdx.lowerBound)
    }

    func testMarkdownSystemMessageSection() {
        let msgs = [
            Message(role: .system, text: "[subagent gemini] sonuç: x"),
        ]
        let md = ConversationExporter.markdown(messages: msgs)
        XCTAssertTrue(md.contains("## System\n\n[subagent gemini] sonuç: x"))
    }

    func testMarkdownAddsTrailingNewlineWhenMissing() {
        let msgs = [Message(role: .user, text: "no newline")]
        let md = ConversationExporter.markdown(messages: msgs)
        // "no newline" sonrasında otomatik \n eklenmeli.
        XCTAssertTrue(md.contains("no newline\n"))
    }

    func testMarkdownPreservesExistingTrailingNewline() {
        let msgs = [Message(role: .user, text: "with newline\n")]
        let md = ConversationExporter.markdown(messages: msgs)
        // Çift \n eklemez.
        XCTAssertFalse(md.contains("with newline\n\n\n"))
    }

    // MARK: - JSON

    func testJSONRoundTripPreservesMessages() throws {
        // ISO8601 ile encode/decode saniye precision'a düşer; nanosecond'lar
        // kayboluyor — bu yüzden Date'leri açıkça tam saniyeli üretiyoruz.
        let secondDate = Date(timeIntervalSince1970: 1716508800)
        let original = [
            Message(id: UUID(), role: .user, text: "soru", createdAt: secondDate),
            Message(id: UUID(), role: .assistant, text: "cevap", createdAt: secondDate),
            Message(id: UUID(), role: .system, text: "info", createdAt: secondDate),
        ]
        let jsonString = try ConversationExporter.json(messages: original)
        let data = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Message].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONIsPrettyPrinted() throws {
        let msgs = [Message(role: .user, text: "x")]
        let jsonString = try ConversationExporter.json(messages: msgs)
        // PrettyPrinted: newline ve indentation içerir.
        XCTAssertTrue(jsonString.contains("\n"))
        XCTAssertTrue(jsonString.contains("  "))
    }

    func testJSONUsesISO8601Date() throws {
        let fixedDate = Date(timeIntervalSince1970: 1716508800) // 2024-05-24
        let msgs = [Message(id: UUID(), role: .user, text: "x", createdAt: fixedDate)]
        let jsonString = try ConversationExporter.json(messages: msgs)
        // ISO8601 substring (yıl-ay-gün'ün T ile birlikte gelmesi).
        XCTAssertTrue(
            jsonString.contains("\"createdAt\" : \"2024-05-24T"),
            "ISO8601 createdAt formatı bekleniyor; jsonString: \(jsonString)"
        )
    }

    // MARK: - Filename

    func testDefaultFilenameContainsFormatExtensionAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1716545700) // 2024-05-24 around 10:15 local
        let mdName = ConversationExporter.defaultFilename(for: .markdown, now: date)
        let jsonName = ConversationExporter.defaultFilename(for: .json, now: date)

        XCTAssertTrue(mdName.hasPrefix("pixel-agent-"))
        XCTAssertTrue(mdName.hasSuffix(".md"))
        XCTAssertTrue(jsonName.hasSuffix(".json"))
        // "2024-05-24" tarihi her iki dosya adında ortak (saat/dakika değişebilir
        // local timezone'a göre — yıl-ay-gün stable).
        XCTAssertTrue(mdName.contains("2024-05-24"))
        XCTAssertTrue(jsonName.contains("2024-05-24"))
    }

    // MARK: - Format enum

    func testFormatHasAllCases() {
        XCTAssertEqual(ConversationExportFormat.allCases.count, 2)
        XCTAssertTrue(ConversationExportFormat.allCases.contains(.markdown))
        XCTAssertTrue(ConversationExportFormat.allCases.contains(.json))
    }

    func testFormatExtensionAndDisplayName() {
        XCTAssertEqual(ConversationExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ConversationExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ConversationExportFormat.markdown.displayName, "Markdown")
        XCTAssertEqual(ConversationExportFormat.json.displayName, "JSON")
    }
}
