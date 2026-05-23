import XCTest
import PixelCore

@testable import PixelMacApp

final class RetryHelperTests: XCTestCase {

    func testEmptyMessagesReturnsNil() {
        XCTAssertNil(RetryHelper.candidateRetryText(messages: []))
    }

    func testSingleMessageReturnsNil() {
        let only = Message(role: .user, text: "yalnız")
        XCTAssertNil(RetryHelper.candidateRetryText(messages: [only]))
    }

    func testLastUserAssistantPairReturnsUserText() {
        let user = Message(role: .user, text: "merhaba")
        let assistant = Message(role: .assistant, text: "")
        let result = RetryHelper.candidateRetryText(messages: [user, assistant])
        XCTAssertEqual(result, "merhaba")
    }

    func testReturnsUserTextEvenIfAssistantHasPartialResponse() {
        // Stream yarıda kesilmiş olabilir; retry hâlâ user metnine bakar.
        let user = Message(role: .user, text: "kodu yaz")
        let assistant = Message(role: .assistant, text: "func test() {")
        let result = RetryHelper.candidateRetryText(messages: [user, assistant])
        XCTAssertEqual(result, "kodu yaz")
    }

    func testReturnsLastPairAcrossMultipleTurns() {
        let u1 = Message(role: .user, text: "ilk")
        let a1 = Message(role: .assistant, text: "ilk cevap")
        let u2 = Message(role: .user, text: "ikinci")
        let a2 = Message(role: .assistant, text: "")
        let result = RetryHelper.candidateRetryText(
            messages: [u1, a1, u2, a2]
        )
        XCTAssertEqual(result, "ikinci")
    }

    func testReversedPairReturnsNil() {
        // Asla normal akışta olmaz ama defensive: assistant→user sırasıyla
        // sondaki çift uyumsuz → nil.
        let assistant = Message(role: .assistant, text: "ben")
        let user = Message(role: .user, text: "sen")
        XCTAssertNil(RetryHelper.candidateRetryText(messages: [assistant, user]))
    }

    func testTwoAssistantsInARowReturnsNil() {
        // Defensive: sondaki [assistant, assistant] → user yok → nil.
        let a1 = Message(role: .assistant, text: "a")
        let a2 = Message(role: .assistant, text: "")
        XCTAssertNil(RetryHelper.candidateRetryText(messages: [a1, a2]))
    }

    func testWhitespaceOnlyUserTextReturnsNil() {
        // Boş/whitespace user metnini retry'a verme — send() zaten yutar
        // ama erken bail out daha temiz.
        let user = Message(role: .user, text: "   \n  ")
        let assistant = Message(role: .assistant, text: "")
        XCTAssertNil(RetryHelper.candidateRetryText(messages: [user, assistant]))
    }
}
