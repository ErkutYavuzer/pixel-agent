import XCTest

@testable import PixelRemote

final class EnvelopeTypeForwardCompatTests: XCTestCase {

    // MARK: - Known cases decode normally

    func testKnownRawValueDecodesToKnownCase() throws {
        let json = #""hello""#.data(using: .utf8)!
        let value = try JSONDecoder().decode(EnvelopeType.self, from: json)
        XCTAssertEqual(value, .hello)
    }

    func testToolCallEventDecodesCorrectly() throws {
        let json = #""toolCallEvent""#.data(using: .utf8)!
        let value = try JSONDecoder().decode(EnvelopeType.self, from: json)
        XCTAssertEqual(value, .toolCallEvent)
    }

    // MARK: - Unknown raw value → .unknown

    func testUnknownRawValueDecodesToUnknown() throws {
        let json = #""futureCaseV3""#.data(using: .utf8)!
        let value = try JSONDecoder().decode(EnvelopeType.self, from: json)
        XCTAssertEqual(value, .unknown)
    }

    func testCompletelyArbitraryStringDecodesToUnknown() throws {
        let json = #""!@#$ random ✨""#.data(using: .utf8)!
        let value = try JSONDecoder().decode(EnvelopeType.self, from: json)
        XCTAssertEqual(value, .unknown)
    }

    func testLiteralUnknownStringDecodesToUnknown() throws {
        // Defensive: "unknown" string explicit gönderilirse de aynı yere düşer.
        let json = #""unknown""#.data(using: .utf8)!
        let value = try JSONDecoder().decode(EnvelopeType.self, from: json)
        XCTAssertEqual(value, .unknown)
    }

    // MARK: - Encode round-trip

    func testKnownCaseRoundTrip() throws {
        for known: EnvelopeType in [.hello, .ping, .toolCallEvent, .hostStatus] {
            let data = try JSONEncoder().encode(known)
            let decoded = try JSONDecoder().decode(EnvelopeType.self, from: data)
            XCTAssertEqual(decoded, known)
        }
    }

    func testUnknownEncodesAsUnknownString() throws {
        let data = try JSONEncoder().encode(EnvelopeType.unknown)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(string, #""unknown""#)
    }

    // MARK: - Envelope-level decode with unknown type

    func testEnvelopeWithUnknownTypeDecodesGracefully() throws {
        // Future client emits a new envelope type; old client gets it.
        let json = """
        {
          "v": 2,
          "id": "test-1",
          "ts": 0,
          "type": "futureSparkleEvent",
          "payload": null
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(RemoteEnvelope.self, from: json)
        XCTAssertEqual(envelope.type, .unknown)
        XCTAssertEqual(envelope.id, "test-1")
        // Eski handler `default: break` ile sessizce yutar — exception yok.
    }
}
