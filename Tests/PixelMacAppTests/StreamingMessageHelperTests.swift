import XCTest
import PixelCore

@testable import PixelMacApp

final class StreamingMessageHelperTests: XCTestCase {

    // MARK: - isStreaming gate

    func testReturnsFalseWhenIsStreamingFlagIsFalse() {
        let assistant = Message(role: .assistant, text: "")
        let result = StreamingMessageHelper.isStreamingTail(
            message: assistant,
            in: [assistant],
            isStreaming: false
        )
        XCTAssertFalse(result)
    }

    // MARK: - role gate

    func testReturnsFalseForUserMessage() {
        let user = Message(role: .user, text: "hi")
        let result = StreamingMessageHelper.isStreamingTail(
            message: user,
            in: [user],
            isStreaming: true
        )
        XCTAssertFalse(result)
    }

    func testReturnsFalseForSystemMessage() {
        let sys = Message(role: .system, text: "sys")
        let result = StreamingMessageHelper.isStreamingTail(
            message: sys,
            in: [sys],
            isStreaming: true
        )
        XCTAssertFalse(result)
    }

    // MARK: - tail position

    func testReturnsTrueForLastAssistantWhenStreaming() {
        let user = Message(role: .user, text: "soru")
        let assistant = Message(role: .assistant, text: "")
        let messages = [user, assistant]
        let result = StreamingMessageHelper.isStreamingTail(
            message: assistant,
            in: messages,
            isStreaming: true
        )
        XCTAssertTrue(result)
    }

    func testReturnsFalseForEarlierAssistantEvenWhenStreaming() {
        // Önceki tamamlanmış assistant turu — sadece son mesaj streaming
        // sayılmalı. Önceki turlar görünür olsa da typing indicator yansıtmaz.
        let user1 = Message(role: .user, text: "ilk")
        let assistant1 = Message(role: .assistant, text: "ilk cevap")
        let user2 = Message(role: .user, text: "ikinci")
        let assistant2 = Message(role: .assistant, text: "")
        let messages = [user1, assistant1, user2, assistant2]
        let result = StreamingMessageHelper.isStreamingTail(
            message: assistant1,
            in: messages,
            isStreaming: true
        )
        XCTAssertFalse(result)
    }

    func testReturnsTrueOnlyForActualTail() {
        let user1 = Message(role: .user, text: "ilk")
        let assistant1 = Message(role: .assistant, text: "ilk cevap")
        let user2 = Message(role: .user, text: "ikinci")
        let assistant2 = Message(role: .assistant, text: "")
        let messages = [user1, assistant1, user2, assistant2]
        let result = StreamingMessageHelper.isStreamingTail(
            message: assistant2,
            in: messages,
            isStreaming: true
        )
        XCTAssertTrue(result)
    }

    // MARK: - edge cases

    func testReturnsFalseWhenMessagesEmpty() {
        // Tutarsız state — message listesi boşken bir mesajla çağrılırsa
        // false dönmeli (id eşleşmeyi).
        let orphan = Message(role: .assistant, text: "")
        let result = StreamingMessageHelper.isStreamingTail(
            message: orphan,
            in: [],
            isStreaming: true
        )
        XCTAssertFalse(result)
    }

    func testReturnsTrueForTailEvenIfTextIsNonEmpty() {
        // Helper sadece "tail + streaming" koşuluna bakar — text doluyken de
        // streaming devam ediyor olabilir (yeni chunk'lar geliyor).
        // TypingIndicator'ın gösterilip gösterilmemesi View tarafında
        // `text.isEmpty` ek koşuluyla karar verilir.
        let user = Message(role: .user, text: "x")
        let assistant = Message(role: .assistant, text: "kısmen geldi")
        let result = StreamingMessageHelper.isStreamingTail(
            message: assistant,
            in: [user, assistant],
            isStreaming: true
        )
        XCTAssertTrue(result)
    }
}
