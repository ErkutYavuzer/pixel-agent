import Foundation
import XCTest

@testable import PixelCore
@testable import PixelRemote

/// **Sprint 8:** EnvelopePayload struct → enum refactor sonrası sum type
/// pattern matching + backward-compat computed getter'ların doğru çalıştığını
/// kanıtlar.
final class EnvelopePayloadSumTypeTests: XCTestCase {

    // MARK: - Sum type case binding

    func testUserMessageCaseBindsTextAndMessageID() {
        let env = RemoteEnvelope.userMessage(text: "merhaba", messageID: "abc")
        guard case .userMessage(let text, let id) = env.payload else {
            XCTFail("expected .userMessage")
            return
        }
        XCTAssertEqual(text, "merhaba")
        XCTAssertEqual(id, "abc")
    }

    func testClientActionCaseBindsActionAndOptionalTarget() {
        let withTarget = RemoteEnvelope.clientAction(type: "cancelSubagent", targetID: "uuid-1")
        guard case .clientAction(let action, let target) = withTarget.payload else {
            XCTFail("expected .clientAction")
            return
        }
        XCTAssertEqual(action, "cancelSubagent")
        XCTAssertEqual(target, "uuid-1")

        let noTarget = RemoteEnvelope.clientAction(type: "requestScreenshot")
        guard case .clientAction(_, let nilTarget) = noTarget.payload else {
            XCTFail("expected .clientAction")
            return
        }
        XCTAssertNil(nilTarget)
    }

    func testHostStatusCaseBindsContent() {
        let metrics = SystemMetricsPayload(cpuUsage: 5, ramUsage: 12, activeWindow: "Editor")
        let env = RemoteEnvelope.hostStatus(
            selectedBackend: "claude",
            selectedModel: "opus",
            planMode: true,
            availableBackends: ["claude", "codex"],
            availableModels: ["claude": ["opus", "sonnet"]],
            activeSubagents: [],
            systemMetrics: metrics
        )
        guard case .hostStatus(let content) = env.payload else {
            XCTFail("expected .hostStatus")
            return
        }
        XCTAssertEqual(content.selectedBackend, "claude")
        XCTAssertEqual(content.selectedModel, "opus")
        XCTAssertTrue(content.planMode)
        XCTAssertEqual(content.systemMetrics.cpuUsage, 5)
    }

    func testPingHasNilPayload() {
        XCTAssertNil(RemoteEnvelope.ping().payload)
    }

    func testArchiveListRequestHasNilPayload() {
        XCTAssertNil(RemoteEnvelope.archiveListRequest().payload)
    }

    // MARK: - Backward-compat computed getters

    func testTextGetterAcrossThreeMessageCases() {
        XCTAssertEqual(RemoteEnvelope.userMessage(text: "a").payload?.text, "a")
        XCTAssertEqual(RemoteEnvelope.assistantMessage(text: "b").payload?.text, "b")
        XCTAssertEqual(RemoteEnvelope.assistantChunk(text: "c").payload?.text, "c")
    }

    func testRoleGetterInferred() {
        XCTAssertEqual(RemoteEnvelope.userMessage(text: "x").payload?.role, "user")
        XCTAssertEqual(RemoteEnvelope.assistantMessage(text: "x").payload?.role, "assistant")
        XCTAssertEqual(RemoteEnvelope.assistantChunk(text: "x").payload?.role, "assistant")
        XCTAssertNil(RemoteEnvelope.ack(referenceID: "1").payload?.role)
    }

    func testMessageIDGetterForAckAndMessages() {
        XCTAssertEqual(RemoteEnvelope.ack(referenceID: "ref").payload?.messageID, "ref")
        XCTAssertEqual(
            RemoteEnvelope.userMessage(text: "x", messageID: "u1").payload?.messageID,
            "u1"
        )
    }

    func testHostStatusGettersForwardToContent() {
        let env = RemoteEnvelope.hostStatus(
            selectedBackend: "codex",
            selectedModel: "gpt-5.5",
            planMode: false,
            availableBackends: ["codex"],
            availableModels: ["codex": ["gpt-5.5"]],
            activeSubagents: [],
            systemMetrics: SystemMetricsPayload(cpuUsage: 1, ramUsage: 2, activeWindow: "App")
        )
        XCTAssertEqual(env.payload?.selectedBackend, "codex")
        XCTAssertEqual(env.payload?.selectedModel, "gpt-5.5")
        XCTAssertEqual(env.payload?.planMode, false)
        XCTAssertEqual(env.payload?.availableBackends, ["codex"])
        XCTAssertEqual(env.payload?.availableModels?["codex"], ["gpt-5.5"])
        XCTAssertEqual(env.payload?.systemMetrics?.cpuUsage, 1)
    }

    func testClientConfigGettersExposeAllThree() {
        let env = RemoteEnvelope.clientConfig(backend: "gemini", model: "2.5-pro", planMode: true)
        XCTAssertEqual(env.payload?.selectedBackend, "gemini")
        XCTAssertEqual(env.payload?.selectedModel, "2.5-pro")
        XCTAssertEqual(env.payload?.planMode, true)
    }

    func testActionTypeAndTargetIDGetters() {
        let env = RemoteEnvelope.clientAction(type: "load", targetID: "id-1")
        XCTAssertEqual(env.payload?.actionType, "load")
        XCTAssertEqual(env.payload?.targetID, "id-1")
    }

    func testFieldGettersReturnNilForUnrelatedCases() {
        let env = RemoteEnvelope.ping()
        XCTAssertNil(env.payload?.text)
        XCTAssertNil(env.payload?.actionType)
        XCTAssertNil(env.payload?.publicKey)
        XCTAssertNil(env.payload?.toolCallEvent)
    }

    // MARK: - Wire format backward-compat (eski JSON decoder ile)

    /// v0.2.32 öncesi format: flat dict, type ayrı. Yeni decoder bunu okuyabilmeli.
    func testDecodesPreSumTypeFlatJSON() throws {
        let json = """
        {
          "v": 2,
          "id": "fixed-id-1",
          "ts": 1700000000,
          "type": "userMessage",
          "payload": {
            "text": "v0.2.32 client'tan",
            "role": "user",
            "messageID": "m-1"
          }
        }
        """.data(using: .utf8)!

        let env = try JSONDecoder().decode(RemoteEnvelope.self, from: json)
        XCTAssertEqual(env.type, .userMessage)
        guard case .userMessage(let text, let id) = env.payload else {
            XCTFail("expected .userMessage")
            return
        }
        XCTAssertEqual(text, "v0.2.32 client'tan")
        XCTAssertEqual(id, "m-1")
    }

    func testEncodesToSameWireShape() throws {
        let env = RemoteEnvelope(
            v: 2, id: "fixed-id-2", ts: 1700000001,
            type: .clientAction,
            payload: .clientAction(actionType: "loadArchive", targetID: "file://path.jsonl")
        )
        let data = try JSONEncoder().encode(env)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["actionType"] as? String, "loadArchive")
        XCTAssertEqual(payload?["targetID"] as? String, "file://path.jsonl")
        // Diğer field'lar olmamalı (sadece case'in alanları).
        XCTAssertNil(payload?["text"])
        XCTAssertNil(payload?["selectedBackend"])
    }

    func testEmptyPayloadTypesEncodeWithoutPayloadKey() throws {
        let env = RemoteEnvelope.ping()
        let data = try JSONEncoder().encode(env)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["payload"])
    }
}
