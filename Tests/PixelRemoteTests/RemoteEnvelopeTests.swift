import Foundation
import XCTest

@testable import PixelRemote

final class RemoteEnvelopeTests: XCTestCase {
    func testEnvelopeTypeRawValues() {
        XCTAssertEqual(EnvelopeType.hello.rawValue, "hello")
        XCTAssertEqual(EnvelopeType.userMessage.rawValue, "userMessage")
        XCTAssertEqual(EnvelopeType.assistantMessage.rawValue, "assistantMessage")
        XCTAssertEqual(EnvelopeType.ack.rawValue, "ack")
        XCTAssertEqual(EnvelopeType.error.rawValue, "error")
    }

    func testEnvelopeTypeContainsAllExpectedCases() {
        let expected: Set<String> = ["hello", "ready", "ping", "ack", "error", "userMessage", "assistantMessage"]
        let actual = Set(EnvelopeType.allCases.map { $0.rawValue })
        XCTAssertEqual(actual, expected)
    }

    func testUserMessageEncodeDecodeRoundTrip() throws {
        let original = RemoteEnvelope.userMessage(text: "Merhaba", messageID: "msg-1")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.type, .userMessage)
        XCTAssertEqual(decoded.payload?.text, "Merhaba")
        XCTAssertEqual(decoded.payload?.role, "user")
        XCTAssertEqual(decoded.payload?.messageID, "msg-1")
    }

    func testPingRoundTripHasNoPayload() throws {
        let original = RemoteEnvelope.ping()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertNil(decoded.payload)
        XCTAssertNil(decoded.sig)
    }

    func testAckCarriesReferenceID() throws {
        let original = RemoteEnvelope.ack(referenceID: "abc")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .ack)
        XCTAssertEqual(decoded.payload?.messageID, "abc")
    }

    func testErrorCarriesCodeAndMessage() throws {
        let original = RemoteEnvelope.error(code: "E_AUTH", message: "Yetki yok")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.errorCode, "E_AUTH")
        XCTAssertEqual(decoded.payload?.errorMessage, "Yetki yok")
    }

    func testDefaultVersionIsProtocolVersion() {
        let env = RemoteEnvelope(type: .hello)
        XCTAssertEqual(env.v, PixelRemote.protocolVersion)
    }

    func testCustomVersionPreservedInRoundTrip() throws {
        let original = RemoteEnvelope(v: 7, type: .hello)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.v, 7)
    }

    func testExtraJSONFieldsAreIgnored() throws {
        let json = #"{"v":1,"id":"x","ts":0,"type":"hello","unknown_field":"ignored"}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .hello)
        XCTAssertEqual(decoded.id, "x")
    }

    func testMissingRequiredFieldThrows() {
        let json = #"{"v":1,"id":"x","ts":0}"#  // type yok
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteEnvelope.self, from: data))
    }

    func testUnknownEnvelopeTypeThrows() {
        let json = #"{"v":1,"id":"x","ts":0,"type":"futureType"}"#
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteEnvelope.self, from: data))
    }

    func testTurkishCharsPreserved() throws {
        let original = RemoteEnvelope.userMessage(text: "Şükür çığ üşür İnşallah özgün")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.text, "Şükür çığ üşür İnşallah özgün")
    }
}
