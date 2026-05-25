import XCTest

@testable import PixelRemote

final class HostStatusDeltaCalculatorTests: XCTestCase {

    private func snapshot(
        backend: String = "claude",
        model: String = "opus",
        plan: Bool = false,
        backends: [String] = ["claude", "codex"],
        models: [String: [String]] = ["claude": ["opus"]],
        subagents: [SubagentStatusPayload] = [],
        cpu: Double = 5,
        ram: Double = 30,
        window: String = "PixelAgent"
    ) -> HostStatusContent {
        HostStatusContent(
            selectedBackend: backend,
            selectedModel: model,
            planMode: plan,
            availableBackends: backends,
            availableModels: models,
            activeSubagents: subagents,
            systemMetrics: SystemMetricsPayload(cpuUsage: cpu, ramUsage: ram, activeWindow: window)
        )
    }

    // MARK: - First frame (bootstrap)

    func testNilOldReturnsFullBootstrapDelta() {
        let new = snapshot()
        let delta = HostStatusDeltaCalculator.delta(from: nil, to: new)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.selectedBackend, "claude")
        XCTAssertEqual(delta?.selectedModel, "opus")
        XCTAssertEqual(delta?.planMode, false)
        XCTAssertEqual(delta?.availableBackends, ["claude", "codex"])
        XCTAssertEqual(delta?.availableModels, ["claude": ["opus"]])
        XCTAssertEqual(delta?.activeSubagents, [])
        XCTAssertNotNil(delta?.systemMetrics)
    }

    // MARK: - No diff (skip push)

    func testIdenticalSnapshotsReturnNil() {
        let s = snapshot()
        XCTAssertNil(HostStatusDeltaCalculator.delta(from: s, to: s))
    }

    func testIdenticalDifferentInstancesReturnNil() {
        let a = snapshot()
        let b = snapshot()  // Equatable via auto-synth — değerler eşit
        XCTAssertNil(HostStatusDeltaCalculator.delta(from: a, to: b))
    }

    // MARK: - Single-field changes

    func testBackendChangeOnlyBackendDelta() {
        let old = snapshot(backend: "claude")
        let new = snapshot(backend: "codex")
        let delta = HostStatusDeltaCalculator.delta(from: old, to: new)
        XCTAssertEqual(delta?.selectedBackend, "codex")
        XCTAssertNil(delta?.selectedModel)
        XCTAssertNil(delta?.planMode)
        XCTAssertNil(delta?.availableBackends)
        XCTAssertNil(delta?.availableModels)
        XCTAssertNil(delta?.activeSubagents)
        XCTAssertNil(delta?.systemMetrics)
    }

    func testPlanModeChangeOnlyPlanDelta() {
        let delta = HostStatusDeltaCalculator.delta(
            from: snapshot(plan: false),
            to: snapshot(plan: true)
        )
        XCTAssertEqual(delta?.planMode, true)
        XCTAssertNil(delta?.selectedBackend)
    }

    func testMetricsChangeOnlyMetricsDelta() {
        let delta = HostStatusDeltaCalculator.delta(
            from: snapshot(cpu: 5),
            to: snapshot(cpu: 50)
        )
        XCTAssertNotNil(delta?.systemMetrics)
        XCTAssertEqual(delta?.systemMetrics?.cpuUsage, 50)
        XCTAssertNil(delta?.selectedBackend)
        XCTAssertNil(delta?.activeSubagents)
    }

    // MARK: - Multi-field changes

    func testMultipleFieldChangesAllInDelta() {
        let old = snapshot(backend: "claude", plan: false, cpu: 5)
        let new = snapshot(backend: "codex", plan: true, cpu: 50)
        let delta = HostStatusDeltaCalculator.delta(from: old, to: new)
        XCTAssertEqual(delta?.selectedBackend, "codex")
        XCTAssertEqual(delta?.planMode, true)
        XCTAssertEqual(delta?.systemMetrics?.cpuUsage, 50)
        // Diğer field'lar değişmedi.
        XCTAssertNil(delta?.selectedModel)
        XCTAssertNil(delta?.availableBackends)
    }

    // MARK: - HostStatusDeltaContent.isEmpty

    func testIsEmptyTrueForAllNilFields() {
        let empty = HostStatusDeltaContent()
        XCTAssertTrue(empty.isEmpty)
    }

    func testIsEmptyFalseWhenAnyFieldSet() {
        XCTAssertFalse(HostStatusDeltaContent(selectedBackend: "x").isEmpty)
        XCTAssertFalse(HostStatusDeltaContent(planMode: true).isEmpty)
        XCTAssertFalse(HostStatusDeltaContent(activeSubagents: []).isEmpty)
    }

    // MARK: - Envelope round-trip

    func testHostStatusDeltaEnvelopeRoundTripPartial() throws {
        let content = HostStatusDeltaContent(
            selectedBackend: "claude",
            systemMetrics: SystemMetricsPayload(cpuUsage: 42, ramUsage: 80, activeWindow: "Test")
        )
        let original = RemoteEnvelope.hostStatusDelta(content)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.type, .hostStatusDelta)
        guard case .hostStatusDelta(let decodedContent) = decoded.payload else {
            XCTFail("expected .hostStatusDelta")
            return
        }
        XCTAssertEqual(decodedContent.selectedBackend, "claude")
        XCTAssertEqual(decodedContent.systemMetrics?.cpuUsage, 42)
        XCTAssertNil(decodedContent.selectedModel)
        XCTAssertNil(decodedContent.planMode)
    }

    func testHostStatusDeltaEncodesOnlyNonNilFields() throws {
        let content = HostStatusDeltaContent(planMode: true)
        let original = RemoteEnvelope.hostStatusDelta(content)
        let data = try JSONEncoder().encode(original)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        XCTAssertEqual(payload?["planMode"] as? Bool, true)
        // Diğer field'lar omit edilmeli (bandwidth optimization'ın kalbi).
        XCTAssertNil(payload?["selectedBackend"])
        XCTAssertNil(payload?["selectedModel"])
        XCTAssertNil(payload?["availableBackends"])
        XCTAssertNil(payload?["activeSubagents"])
        XCTAssertNil(payload?["systemMetrics"])
    }

    func testHostStatusDeltaGettersForwardToContent() {
        let env = RemoteEnvelope.hostStatusDelta(
            HostStatusDeltaContent(
                selectedBackend: "gemini",
                availableBackends: ["gemini"]
            )
        )
        XCTAssertEqual(env.payload?.selectedBackend, "gemini")
        XCTAssertEqual(env.payload?.availableBackends, ["gemini"])
        XCTAssertNil(env.payload?.selectedModel)
    }

    // MARK: - Sprint 23 (v0.2.48): screenshotWireLatencyMs

    func testDeltaIncludesWireLatencyOnChange() {
        // Eski snapshot'ta latency yok, yeni snapshot'ta var → delta'da set.
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let old = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: nil
        )
        let new = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 87
        )
        let delta = HostStatusDeltaCalculator.delta(from: old, to: new)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.screenshotWireLatencyMs, 87)
    }

    func testDeltaUnchangedLatencyOmitted() {
        // Aynı latency iki snapshot'ta → delta nil (push skip).
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let old = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 87
        )
        let new = old
        let delta = HostStatusDeltaCalculator.delta(from: old, to: new)
        XCTAssertNil(delta, "Hiçbir field değişmemişse delta skip edilmeli")
    }

    func testDeltaLatencyChangedFromValueToNil() {
        // Stream stop edildi → Mac latency'i nil set'liyor. Delta semantiği
        // gereği "nil = değişmedi" olsa da, calculator field eşitliğini
        // kontrol ettiği için 87 != nil → yeni nil değer set'lenir.
        // (iOS handler nil değeri görmezden gelir — guard `if let`; UI
        // gate'i isStreamingScreenshots ile zaten badge'i gizler.)
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let old = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 87
        )
        let new = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: nil
        )
        let delta = HostStatusDeltaCalculator.delta(from: old, to: new)
        // Calculator: old(87) != new(nil) → delta.screenshotWireLatencyMs = nil
        // (yeni değer; ama new nil olduğu için delta da nil olur — sonuç:
        // isEmpty true, calculator nil döner). Bu kabul edilebilir: stream
        // stop'tan sonra başka değişiklik yoksa push yapılmaz, iOS UI gate'i
        // badge'i gizler.
        XCTAssertNil(delta)
    }

    func testDeltaFullBootstrapIncludesWireLatency() {
        // İlk frame (from nil): tüm field'lar new'den kopyalanır.
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let new = HostStatusContent(
            selectedBackend: "claude", selectedModel: "opus", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 42
        )
        let delta = HostStatusDeltaCalculator.delta(from: nil, to: new)
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.screenshotWireLatencyMs, 42)
    }

    func testHostStatusEnvelopeRoundTripWithWireLatency() throws {
        let metrics = SystemMetricsPayload(cpuUsage: 5, ramUsage: 12, activeWindow: "Editor")
        let env = RemoteEnvelope.hostStatus(
            selectedBackend: "claude",
            selectedModel: "opus",
            planMode: true,
            availableBackends: ["claude"],
            availableModels: [:],
            activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 156
        )
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.screenshotWireLatencyMs, 156)
    }

    func testHostStatusEnvelopeOmitsWireLatencyWhenNil() throws {
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let env = RemoteEnvelope.hostStatus(
            selectedBackend: "claude",
            selectedModel: "opus",
            planMode: false,
            availableBackends: [],
            availableModels: [:],
            activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: nil
        )
        let data = try JSONEncoder().encode(env)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = dict?["payload"] as? [String: Any]
        XCTAssertNil(payload?["screenshotWireLatencyMs"],
            "nil latency wire format'ta omit edilmeli")
    }

    func testHostStatusDeltaEnvelopeWireLatencyRoundTrip() throws {
        let content = HostStatusDeltaContent(screenshotWireLatencyMs: 220)
        let env = RemoteEnvelope.hostStatusDelta(content)
        let data = try JSONEncoder().encode(env)
        let decoded = try JSONDecoder().decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.payload?.screenshotWireLatencyMs, 220)

        // isEmpty: sadece wireLatency set ise isEmpty false (push edilebilir).
        XCTAssertFalse(content.isEmpty)
    }

    func testDeltaIsEmptyOnlyWhenAllFieldsNil() {
        XCTAssertTrue(HostStatusDeltaContent().isEmpty)
        XCTAssertFalse(HostStatusDeltaContent(screenshotWireLatencyMs: 50).isEmpty)
    }

    func testWireLatencyGetterFromHostStatusAndDelta() {
        let metrics = SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
        let fullEnv = RemoteEnvelope.hostStatus(
            selectedBackend: "x", selectedModel: "y", planMode: false,
            availableBackends: [], availableModels: [:], activeSubagents: [],
            systemMetrics: metrics,
            screenshotWireLatencyMs: 99
        )
        XCTAssertEqual(fullEnv.payload?.screenshotWireLatencyMs, 99)

        let deltaEnv = RemoteEnvelope.hostStatusDelta(screenshotWireLatencyMs: 33)
        XCTAssertEqual(deltaEnv.payload?.screenshotWireLatencyMs, 33)

        // Unrelated case → nil.
        XCTAssertNil(RemoteEnvelope.ping().payload?.screenshotWireLatencyMs)
    }
}
