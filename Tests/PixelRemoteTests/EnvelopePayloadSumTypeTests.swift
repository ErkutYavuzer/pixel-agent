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

    // MARK: - Sprint 10 (v0.2.35): archive mutation envelope'ları

    func testArchiveRenameWithTitleRoundTrip() throws {
        let original = RemoteEnvelope.archiveRename(archiveID: "url-1", newTitle: "Yeni Başlık")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .archiveRename)
        guard case .archiveRename(let id, let title) = decoded.payload else {
            XCTFail("expected .archiveRename")
            return
        }
        XCTAssertEqual(id, "url-1")
        XCTAssertEqual(title, "Yeni Başlık")
    }

    func testArchiveRenameWithNilTitleEncodesClearsSentinel() throws {
        let original = RemoteEnvelope.archiveRename(archiveID: "url-2", newTitle: nil)
        let data = try JSONEncoder().encode(original)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        // Encoder explicit sentinel ile nil intent'i taşır (decoder ayırt edebilsin).
        XCTAssertEqual(payload?["renameClearsTitle"] as? Bool, true)
        XCTAssertNil(payload?["renameNewTitle"])

        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        guard case .archiveRename(_, let title) = decoded.payload else {
            XCTFail("expected .archiveRename")
            return
        }
        XCTAssertNil(title)
    }

    func testArchiveSetTagsWithListRoundTrip() throws {
        let original = RemoteEnvelope.archiveSetTags(archiveID: "url-3", tags: ["work", "urgent"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .archiveSetTags)
        guard case .archiveSetTags(let id, let tags) = decoded.payload else {
            XCTFail("expected .archiveSetTags")
            return
        }
        XCTAssertEqual(id, "url-3")
        XCTAssertEqual(tags, ["work", "urgent"])
    }

    func testArchiveSetTagsWithNilRoundTrip() throws {
        let original = RemoteEnvelope.archiveSetTags(archiveID: "url-4", tags: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        guard case .archiveSetTags(_, let tags) = decoded.payload else {
            XCTFail("expected .archiveSetTags")
            return
        }
        XCTAssertNil(tags)
    }

    func testMutationArchiveIDGetterForBothCases() {
        XCTAssertEqual(
            RemoteEnvelope.archiveRename(archiveID: "rid", newTitle: "x").payload?.mutationArchiveID,
            "rid"
        )
        XCTAssertEqual(
            RemoteEnvelope.archiveSetTags(archiveID: "tid", tags: ["a"]).payload?.mutationArchiveID,
            "tid"
        )
        XCTAssertNil(RemoteEnvelope.ping().payload?.mutationArchiveID)
        XCTAssertNil(
            RemoteEnvelope.archiveLoadRequest(id: "x").payload?.mutationArchiveID
        )
    }

    func testRenameNewTitleGetterPresentWhenSet() {
        XCTAssertEqual(
            RemoteEnvelope.archiveRename(archiveID: "x", newTitle: "Yeni").payload?.renameNewTitle,
            "Yeni"
        )
        XCTAssertNil(RemoteEnvelope.archiveRename(archiveID: "x", newTitle: nil).payload?.renameNewTitle)
        // Diğer case'lerde nil.
        XCTAssertNil(RemoteEnvelope.archiveSetTags(archiveID: "x", tags: ["a"]).payload?.renameNewTitle)
    }

    func testEditedTagsGetterPresentWhenSet() {
        XCTAssertEqual(
            RemoteEnvelope.archiveSetTags(archiveID: "x", tags: ["a", "b"]).payload?.editedTags,
            ["a", "b"]
        )
        XCTAssertNil(RemoteEnvelope.archiveSetTags(archiveID: "x", tags: nil).payload?.editedTags)
        XCTAssertNil(RemoteEnvelope.archiveRename(archiveID: "x", newTitle: "y").payload?.editedTags)
    }

    // MARK: - Sprint 12 (v0.2.37): archiveDelete envelope

    func testArchiveDeleteRoundTrip() throws {
        let original = RemoteEnvelope.archiveDelete(archiveID: "file://path.jsonl")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .archiveDelete)
        guard case .archiveDelete(let id) = decoded.payload else {
            XCTFail("expected .archiveDelete")
            return
        }
        XCTAssertEqual(id, "file://path.jsonl")
    }

    func testArchiveDeleteMutationIDGetter() {
        let env = RemoteEnvelope.archiveDelete(archiveID: "url-1")
        XCTAssertEqual(env.payload?.mutationArchiveID, "url-1")
        // Diğer mutation getter'ları nil dönmeli.
        XCTAssertNil(env.payload?.renameNewTitle)
        XCTAssertNil(env.payload?.editedTags)
    }

    func testArchiveDeleteEncodesOnlyArchiveID() throws {
        let env = RemoteEnvelope.archiveDelete(archiveID: "x")
        let data = try JSONEncoder().encode(env)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["mutationArchiveID"] as? String, "x")
        XCTAssertNil(payload?["renameNewTitle"])
        XCTAssertNil(payload?["editedTags"])
        XCTAssertNil(payload?["renameClearsTitle"])
    }

    // MARK: - Sprint 15 (v0.2.40): screenshotStream envelope'ları

    func testScreenshotStreamStartRoundTrip() throws {
        let original = RemoteEnvelope.screenshotStreamStart(intervalMs: 500)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .screenshotStreamStart)
        guard case .screenshotStreamStart(let ms) = decoded.payload else {
            XCTFail("expected .screenshotStreamStart")
            return
        }
        XCTAssertEqual(ms, 500)
    }

    func testScreenshotStreamStartIntervalClampedOnDecode() throws {
        // Encoder raw değeri yazar; decoder clamp eder (250-5000).
        // Manuel JSON ile clamp testi.
        let belowMin = """
        {"v":2,"id":"x","ts":1,"type":"screenshotStreamStart","payload":{"streamIntervalMs":50}}
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(RemoteEnvelope.self, from: belowMin)
        XCTAssertEqual(env.payload?.streamIntervalMs, 250)

        let aboveMax = """
        {"v":2,"id":"x","ts":1,"type":"screenshotStreamStart","payload":{"streamIntervalMs":99999}}
        """.data(using: .utf8)!
        let env2 = try JSONDecoder().decode(RemoteEnvelope.self, from: aboveMax)
        XCTAssertEqual(env2.payload?.streamIntervalMs, 5000)
    }

    func testScreenshotStreamStartDefaultIntervalWhenMissing() throws {
        // Field hiç yoksa 1000 default.
        let raw = """
        {"v":2,"id":"x","ts":1,"type":"screenshotStreamStart","payload":{}}
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(RemoteEnvelope.self, from: raw)
        XCTAssertEqual(env.payload?.streamIntervalMs, 1000)
    }

    func testScreenshotStreamStopHasNoPayload() throws {
        let original = RemoteEnvelope.screenshotStreamStop()
        XCTAssertNil(original.payload)
        let data = try JSONEncoder().encode(original)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(dict?["payload"])

        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .screenshotStreamStop)
        XCTAssertNil(decoded.payload)
    }

    func testStreamIntervalMsGetterForUnrelatedCasesNil() {
        XCTAssertNil(RemoteEnvelope.ping().payload?.streamIntervalMs)
        XCTAssertNil(RemoteEnvelope.archiveDelete(archiveID: "x").payload?.streamIntervalMs)
    }

    // MARK: - Sprint 22 (v0.2.47): screenshotFrameAck + frameID

    func testScreenshotPayloadWithoutFrameIDRoundTrip() throws {
        // Eski wire format: frameID + wireLatencyMs yok. Wire'da yok, decode nil verir.
        let original = RemoteEnvelope.screenshotPayload(base64Image: "abc==")
        guard case .screenshotPayload(let img, let frameID, let latency) = original.payload else {
            XCTFail("expected .screenshotPayload")
            return
        }
        XCTAssertEqual(img, "abc==")
        XCTAssertNil(frameID)
        XCTAssertNil(latency)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)

        // Wire'da `screenshotFrameID` + `screenshotWireLatencyMs` hiç olmamalı.
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        XCTAssertNil(payload?["screenshotFrameID"],
            "frameID nil ise wire format'ta hiç olmamalı (encodeIfPresent)")
        XCTAssertNil(payload?["screenshotWireLatencyMs"],
            "wireLatencyMs nil ise wire format'ta hiç olmamalı (encodeIfPresent)")
    }

    func testScreenshotPayloadWithFrameIDRoundTrip() throws {
        let frameID = "F1-uuid-1234"
        let original = RemoteEnvelope.screenshotPayload(
            base64Image: "abc==",
            frameID: frameID
        )
        guard case .screenshotPayload(_, let decodedID, _) = original.payload else {
            XCTFail("expected .screenshotPayload")
            return
        }
        XCTAssertEqual(decodedID, frameID)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.payload?.screenshotFrameID, frameID)
    }

    // MARK: - Sprint 24 (v0.2.49): screenshotPayload wireLatencyMs embed

    func testScreenshotPayloadWithWireLatencyRoundTrip() throws {
        // Per-frame latency embed: Mac coordinator önceki frame'in ACK
        // round-trip ölçümünü envelope'a iliştirir; iOS Mac Paneli badge
        // her tick güncellenir (3sn hostStatus lag yerine).
        let original = RemoteEnvelope.screenshotPayload(
            base64Image: "abc==",
            frameID: "F2",
            wireLatencyMs: 142
        )
        guard case .screenshotPayload(_, _, let latency) = original.payload else {
            XCTFail("expected .screenshotPayload")
            return
        }
        XCTAssertEqual(latency, 142)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.payload?.screenshotWireLatencyMs, 142)
    }

    func testScreenshotPayloadWireLatencyGetterAcrossCases() {
        // screenshotWireLatencyMs getter artık 3 case'i kapsamalı:
        // hostStatus, hostStatusDelta, screenshotPayload.
        let withLatency = RemoteEnvelope.screenshotPayload(
            base64Image: "x", frameID: nil, wireLatencyMs: 87
        )
        XCTAssertEqual(withLatency.payload?.screenshotWireLatencyMs, 87)

        // screenshotPayload but no latency → nil.
        let withoutLatency = RemoteEnvelope.screenshotPayload(base64Image: "x")
        XCTAssertNil(withoutLatency.payload?.screenshotWireLatencyMs)

        // Unrelated case → nil.
        XCTAssertNil(RemoteEnvelope.userMessage(text: "z").payload?.screenshotWireLatencyMs)
    }

    func testScreenshotPayloadFrameIDAndLatencyIndependent() throws {
        // frameID set ama latency yok (ilk frame; ACK henüz gelmedi).
        let firstFrame = RemoteEnvelope.screenshotPayload(
            base64Image: "img",
            frameID: "F1",
            wireLatencyMs: nil
        )
        XCTAssertEqual(firstFrame.payload?.screenshotFrameID, "F1")
        XCTAssertNil(firstFrame.payload?.screenshotWireLatencyMs)

        // Tek-shot (frameID yok ama latency'i de yok — tek-shot screenshot için).
        let oneShot = RemoteEnvelope.screenshotPayload(base64Image: "img")
        XCTAssertNil(oneShot.payload?.screenshotFrameID)
        XCTAssertNil(oneShot.payload?.screenshotWireLatencyMs)
    }

    func testScreenshotFrameAckRoundTrip() throws {
        let original = RemoteEnvelope.screenshotFrameAck(frameID: "F1-uuid-1234")
        XCTAssertEqual(original.type, .screenshotFrameAck)

        guard case .screenshotFrameAck(let id) = original.payload else {
            XCTFail("expected .screenshotFrameAck")
            return
        }
        XCTAssertEqual(id, "F1-uuid-1234")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.payload?.screenshotFrameID, "F1-uuid-1234")
    }

    func testScreenshotFrameIDGetterForUnrelatedCasesNil() {
        XCTAssertNil(RemoteEnvelope.ping().payload?.screenshotFrameID)
        XCTAssertNil(RemoteEnvelope.userMessage(text: "x").payload?.screenshotFrameID)
        XCTAssertNil(RemoteEnvelope.archiveDelete(archiveID: "x").payload?.screenshotFrameID)
    }

    func testScreenshotFrameAckMissingIDDecodesEmpty() throws {
        // Defensive: wire'da `screenshotFrameID` field eksikse ack boş ID
        // ile decode olur; üst katman (RemoteHost.handle) `!id.isEmpty`
        // gate'i sayesinde callback'i çağırmaz.
        let raw = """
        {"v":2,"id":"e","ts":1,"type":"screenshotFrameAck","payload":{}}
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(RemoteEnvelope.self, from: raw)
        XCTAssertEqual(env.type, .screenshotFrameAck)
        XCTAssertEqual(env.payload?.screenshotFrameID, "")
    }
}
