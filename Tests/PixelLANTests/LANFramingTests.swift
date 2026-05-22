import XCTest
import PixelRemote
@testable import PixelLAN

final class LANFramingTests: XCTestCase {
    func testEncodeAppendsNewline() throws {
        let env = RemoteEnvelope.userMessage(text: "selam")
        let data = try LANFraming.encode(env)
        XCTAssertEqual(data.last, 0x0a)
        XCTAssertGreaterThan(data.count, 1)
    }

    func testDecodeSingleLine() throws {
        let env = RemoteEnvelope.userMessage(text: "merhaba", messageID: "id-1")
        let data = try LANFraming.encode(env)
        let (envelopes, leftover) = try LANFraming.decode(buffer: data)
        XCTAssertEqual(envelopes.count, 1)
        XCTAssertEqual(envelopes[0].payload?.text, "merhaba")
        XCTAssertTrue(leftover.isEmpty)
    }

    func testDecodeMultipleLines() throws {
        let e1 = RemoteEnvelope.userMessage(text: "ilk")
        let e2 = RemoteEnvelope.ping()
        var buffer = try LANFraming.encode(e1)
        buffer.append(try LANFraming.encode(e2))
        let (envelopes, leftover) = try LANFraming.decode(buffer: buffer)
        XCTAssertEqual(envelopes.count, 2)
        XCTAssertEqual(envelopes[0].payload?.text, "ilk")
        XCTAssertEqual(envelopes[1].type, .ping)
        XCTAssertTrue(leftover.isEmpty)
    }

    func testDecodePartialKeepsLeftover() throws {
        let e1 = RemoteEnvelope.userMessage(text: "tam")
        var buffer = try LANFraming.encode(e1)
        // Yarım envelope ekle (newline yok)
        buffer.append(Data(#"{"v":2,"id":"x","#.utf8))
        let (envelopes, leftover) = try LANFraming.decode(buffer: buffer)
        XCTAssertEqual(envelopes.count, 1)
        XCTAssertFalse(leftover.isEmpty)
        XCTAssertEqual(String(data: leftover, encoding: .utf8), #"{"v":2,"id":"x","#)
    }

    func testDecodeEmptyBufferReturnsEmpty() throws {
        let (envelopes, leftover) = try LANFraming.decode(buffer: Data())
        XCTAssertTrue(envelopes.isEmpty)
        XCTAssertTrue(leftover.isEmpty)
    }

    func testDecodeInvalidJSONThrows() {
        let bad = Data("{not json\n".utf8)
        XCTAssertThrowsError(try LANFraming.decode(buffer: bad))
    }

    func testDecodeIgnoresBlankLines() throws {
        let env = RemoteEnvelope.ping()
        var buffer = try LANFraming.encode(env)
        buffer.append(0x0a)  // ekstra boş satır
        buffer.append(try LANFraming.encode(env))
        let (envelopes, _) = try LANFraming.decode(buffer: buffer)
        XCTAssertEqual(envelopes.count, 2)
    }

    func testTurkishCharsSurviveFraming() throws {
        let env = RemoteEnvelope.userMessage(text: "şükür ÇIĞ üzgünüm İnşallah")
        let data = try LANFraming.encode(env)
        let (envelopes, _) = try LANFraming.decode(buffer: data)
        XCTAssertEqual(envelopes[0].payload?.text, "şükür ÇIĞ üzgünüm İnşallah")
    }
}
