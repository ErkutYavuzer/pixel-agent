import Foundation
import XCTest

@testable import PixelCore

final class MessageTests: XCTestCase {
    func testMessageRoleRawValues() {
        XCTAssertEqual(MessageRole.system.rawValue, "system")
        XCTAssertEqual(MessageRole.user.rawValue, "user")
        XCTAssertEqual(MessageRole.assistant.rawValue, "assistant")
    }

    func testMessageCodableRoundTrip() throws {
        let original = Message(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            role: .user,
            text: "Merhaba",
            createdAt: Date(timeIntervalSince1970: 1_716_296_400)
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testMessageTextIsMutable() {
        var msg = Message(role: .assistant, text: "")
        msg.text = "stream chunk 1"
        msg.text += " chunk 2"
        XCTAssertEqual(msg.text, "stream chunk 1 chunk 2")
    }
}
