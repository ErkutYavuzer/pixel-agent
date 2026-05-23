import XCTest
import PixelCore

@testable import PixelMacApp

final class MessageActionsHelperTests: XCTestCase {

    // MARK: - Empty / single role

    func testEmptyMessagesReturnsNil() {
        XCTAssertNil(MessageActionsHelper.lastCopyableAssistantText(in: []))
    }

    func testOnlyUserMessagesReturnsNil() {
        let msgs = [
            Message(role: .user, text: "soru 1"),
            Message(role: .user, text: "soru 2"),
        ]
        XCTAssertNil(MessageActionsHelper.lastCopyableAssistantText(in: msgs))
    }

    func testOnlySystemMessagesReturnsNil() {
        let msgs = [Message(role: .system, text: "[subagent gemini] sonuç: x")]
        XCTAssertNil(MessageActionsHelper.lastCopyableAssistantText(in: msgs))
    }

    // MARK: - Last assistant selection

    func testSingleAssistantReturnsItsText() {
        let msgs = [
            Message(role: .user, text: "soru"),
            Message(role: .assistant, text: "cevap"),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), "cevap")
    }

    func testReturnsLastAssistantWhenMultiplePresent() {
        let msgs = [
            Message(role: .user, text: "1"),
            Message(role: .assistant, text: "ilk cevap"),
            Message(role: .user, text: "2"),
            Message(role: .assistant, text: "ikinci cevap"),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), "ikinci cevap")
    }

    func testSkipsTrailingEmptyAssistantAndReturnsPreviousFull() {
        // Streaming başladı ama henüz token gelmedi → son assistant empty.
        // Kullanıcı "son yanıtı kopyala" derken bir önceki tamamlanmış
        // yanıtı kasteder.
        let msgs = [
            Message(role: .user, text: "1"),
            Message(role: .assistant, text: "ilk cevap"),
            Message(role: .user, text: "2"),
            Message(role: .assistant, text: ""),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), "ilk cevap")
    }

    func testSkipsWhitespaceOnlyAssistant() {
        let msgs = [
            Message(role: .user, text: "1"),
            Message(role: .assistant, text: "geçerli cevap"),
            Message(role: .user, text: "2"),
            Message(role: .assistant, text: "   \n\t  "),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), "geçerli cevap")
    }

    // MARK: - System messages skipped over

    func testSystemMessagesDoNotCount() {
        // Subagent çıktısı .system olarak düşer; quick-copy bunu hedeflemez —
        // assistant'ın direkt sözleri istenmektedir.
        let msgs = [
            Message(role: .user, text: "soru"),
            Message(role: .assistant, text: "cevap"),
            Message(role: .system, text: "[subagent gemini] sonuç: x"),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), "cevap")
    }

    // MARK: - Text fidelity

    func testReturnsOriginalTextNotTrimmed() {
        // Kopyalanan metin sondaki newline'ları korumalı — kod yapıştırırken
        // yararlı (markdown segmenter zaten boş satırları tutuyor).
        let original = "kod:\n```swift\nlet x = 1\n```\n"
        let msgs = [
            Message(role: .user, text: "yaz"),
            Message(role: .assistant, text: original),
        ]
        XCTAssertEqual(MessageActionsHelper.lastCopyableAssistantText(in: msgs), original)
    }
}
