import XCTest

@testable import PixelRemote

final class ToolCallEventTests: XCTestCase {

    // MARK: - Payload

    func testPayloadInitWithDefaults() {
        let event = ToolCallEventPayload(
            toolName: "ui_screenshot",
            status: "success"
        )
        XCTAssertEqual(event.toolName, "ui_screenshot")
        XCTAssertEqual(event.status, "success")
        XCTAssertNil(event.summary)
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertGreaterThan(event.timestamp, 0)
    }

    func testPayloadCodableRoundTrip() throws {
        let original = ToolCallEventPayload(
            id: "fixed-id",
            toolName: "dispatch_subagent",
            status: "failure",
            summary: "Cap reached",
            timestamp: 1_716_508_800
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ToolCallEventPayload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Envelope factory

    func testEnvelopeFactoryProducesToolCallEventType() {
        let envelope = RemoteEnvelope.toolCallEvent(
            toolName: "notify",
            status: "success",
            summary: "Bildirim gönderildi"
        )
        XCTAssertEqual(envelope.type, .toolCallEvent)
        XCTAssertNotNil(envelope.payload?.toolCallEvent)
        XCTAssertEqual(envelope.payload?.toolCallEvent?.toolName, "notify")
        XCTAssertEqual(envelope.payload?.toolCallEvent?.status, "success")
        XCTAssertEqual(envelope.payload?.toolCallEvent?.summary, "Bildirim gönderildi")
    }

    func testEnvelopeFactoryNoSummary() {
        let envelope = RemoteEnvelope.toolCallEvent(toolName: "ui_query", status: "success")
        XCTAssertNil(envelope.payload?.toolCallEvent?.summary)
    }

    // MARK: - Envelope round-trip

    func testEnvelopeJSONRoundTrip() throws {
        let envelope = RemoteEnvelope.toolCallEvent(
            toolName: "ui_click",
            status: "failure",
            summary: "Element bulunamadı"
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .toolCallEvent)
        XCTAssertEqual(decoded.payload?.toolCallEvent?.toolName, "ui_click")
        XCTAssertEqual(decoded.payload?.toolCallEvent?.status, "failure")
        XCTAssertEqual(decoded.payload?.toolCallEvent?.summary, "Element bulunamadı")
    }

    // MARK: - EnvelopeType case present

    func testEnvelopeTypeAllCasesContainsToolCallEvent() {
        XCTAssertTrue(EnvelopeType.allCases.contains(.toolCallEvent))
    }

    func testEnvelopeTypeRawValueStable() {
        // Wire compat — daha sonra rename'lerin aksamaması için.
        XCTAssertEqual(EnvelopeType.toolCallEvent.rawValue, "toolCallEvent")
    }
}
