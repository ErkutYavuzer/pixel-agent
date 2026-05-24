import Foundation
import XCTest

@testable import PixelRemote

final class RemoteEnvelopeTests: XCTestCase {
    func testEnvelopeTypeRawValues() {
        XCTAssertEqual(EnvelopeType.hello.rawValue, "hello")
        XCTAssertEqual(EnvelopeType.userMessage.rawValue, "userMessage")
        XCTAssertEqual(EnvelopeType.assistantMessage.rawValue, "assistantMessage")
        XCTAssertEqual(EnvelopeType.assistantChunk.rawValue, "assistantChunk")
        XCTAssertEqual(EnvelopeType.clientConfig.rawValue, "clientConfig")
        XCTAssertEqual(EnvelopeType.clientAction.rawValue, "clientAction")
        XCTAssertEqual(EnvelopeType.hostStatus.rawValue, "hostStatus")
        XCTAssertEqual(EnvelopeType.screenshotPayload.rawValue, "screenshotPayload")
        XCTAssertEqual(EnvelopeType.ack.rawValue, "ack")
        XCTAssertEqual(EnvelopeType.error.rawValue, "error")
    }

    func testEnvelopeTypeContainsAllExpectedCases() {
        let expected: Set<String> = [
            "hello", "ready", "ping", "ack", "error",
            "userMessage", "assistantMessage", "assistantChunk",
            "clientConfig", "clientAction", "hostStatus", "screenshotPayload",
            "toolCallEvent",  // C12 (Sprint 3) — Mac MCP bridge tool aktivitesi
            "unknown",        // Sprint 4 — forward-compat decode fallback
        ]
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

    func testUnknownEnvelopeTypeDecodesToUnknownCase() throws {
        // **Sprint 4 (forward-compat):** önceki davranış throw idi; artık
        // bilinmeyen tip `.unknown` sentinel'ine düşer. Bu sayede ileride
        // yeni envelope tipleri eski client'ları kırmaz.
        let json = #"{"v":1,"id":"x","ts":0,"type":"futureType"}"#
        let data = json.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(envelope.type, .unknown)
    }

    func testTurkishCharsPreserved() throws {
        let original = RemoteEnvelope.userMessage(text: "Şükür çığ üşür İnşallah özgün")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.text, "Şükür çığ üşür İnşallah özgün")
    }

    func testHelloFactoryCarriesPublicKey() throws {
        let env = RemoteEnvelope.hello(publicKey: "AAAA-pubkey-base64")
        XCTAssertEqual(env.type, .hello)
        XCTAssertEqual(env.payload?.publicKey, "AAAA-pubkey-base64")
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.publicKey, "AAAA-pubkey-base64")
    }

    func testProtocolVersionIsV2() {
        XCTAssertEqual(PixelRemote.protocolVersion, 2)
    }

    func testAssistantChunkFactoryRoundTrip() throws {
        let original = RemoteEnvelope.assistantChunk(text: "chunk text", messageID: "msg-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.v, original.v)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.ts, original.ts)
        XCTAssertEqual(decoded.type, .assistantChunk)
        XCTAssertEqual(decoded.payload?.text, "chunk text")
        XCTAssertEqual(decoded.payload?.messageID, "msg-123")
        XCTAssertEqual(decoded.payload?.role, "assistant")
    }

    func testClientConfigRoundTrip() throws {
        print("--- [debug] START testClientConfigRoundTrip ---")
        let original = RemoteEnvelope.clientConfig(backend: "claude", model: "claude-3-5-sonnet", planMode: true)
        print("--- [debug] Original created ---")
        let data = try JSONEncoder().encode(original)
        print("--- [debug] Encoded ---")
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        print("--- [debug] Decoded ---")
        XCTAssertEqual(decoded.v, original.v)
        print("--- [debug] v checked ---")
        XCTAssertEqual(decoded.id, original.id)
        print("--- [debug] id checked ---")
        XCTAssertEqual(decoded.ts, original.ts)
        print("--- [debug] ts checked ---")
        XCTAssertEqual(decoded.type, .clientConfig)
        print("--- [debug] type checked ---")
        XCTAssertEqual(decoded.payload?.selectedBackend, "claude")
        print("--- [debug] backend checked ---")
        XCTAssertEqual(decoded.payload?.selectedModel, "claude-3-5-sonnet")
        print("--- [debug] model checked ---")
        XCTAssertEqual(decoded.payload?.planMode, true)
        print("--- [debug] planMode checked ---")
    }

    func testClientActionRoundTrip() throws {
        let original = RemoteEnvelope.clientAction(type: "cancelSubagent", targetID: "sub-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.v, original.v)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.ts, original.ts)
        XCTAssertEqual(decoded.type, .clientAction)
        XCTAssertEqual(decoded.payload?.actionType, "cancelSubagent")
        XCTAssertEqual(decoded.payload?.targetID, "sub-123")
    }

    func testHostStatusRoundTrip() throws {
        let metrics = SystemMetricsPayload(cpuUsage: 12.5, ramUsage: 45.2, activeWindow: "Xcode")
        let subagent = SubagentStatusPayload(id: "sub-1", prompt: "build app", status: "running", partialOutput: "compiling...", startedAt: 1234567.0)
        let original = RemoteEnvelope.hostStatus(
            selectedBackend: "gemini",
            selectedModel: "gemini-3-flash-preview",
            planMode: false,
            availableBackends: ["claude", "gemini"],
            availableModels: ["gemini": ["gemini-3-flash-preview"]],
            activeSubagents: [subagent],
            systemMetrics: metrics
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.v, original.v)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.ts, original.ts)
        XCTAssertEqual(decoded.type, .hostStatus)
        XCTAssertEqual(decoded.payload?.selectedBackend, "gemini")
        XCTAssertEqual(decoded.payload?.selectedModel, "gemini-3-flash-preview")
        XCTAssertEqual(decoded.payload?.planMode, false)
        XCTAssertEqual(decoded.payload?.availableBackends, ["claude", "gemini"])
        XCTAssertEqual(decoded.payload?.availableModels?["gemini"], ["gemini-3-flash-preview"])
        XCTAssertEqual(decoded.payload?.systemMetrics?.activeWindow, "Xcode")
        XCTAssertEqual(decoded.payload?.activeSubagents?.first?.prompt, "build app")
    }
}
