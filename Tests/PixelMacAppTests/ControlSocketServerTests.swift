import XCTest
import PixelBackends
import PixelCore
import PixelSubagent
@testable import PixelMacApp
@testable import PixelMCPServer

/// Hiç bitmeyecek mock — `cap reached` testi için havuzu doldurmaya yarar.
private struct StallBackend: ChatBackend {
    let modelID = "stall"
    func send(messages: [Message], system: String?, options: ChatOptions) -> AsyncThrowingStream<StreamDelta, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s — testler içinde asla yetişmez
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

final class ControlSocketServerTests: XCTestCase {
    private var socketPath: String!

    override func setUpWithError() throws {
        // Test başına benzersiz socket path (/tmp altında, kısa)
        socketPath = "/tmp/pixel-agent-test-\(UUID().uuidString.prefix(12)).sock"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    /// E2E: bind → BridgeClient.call (bilinmeyen tool) → "Bilinmeyen bridge tool" error response.
    /// Bu test DockBadge/Notification gibi sistem servislerine dokunmaz — sadece transport
    /// + dispatch yolunu doğrular.
    func testServerHandlesUnknownToolWithFailureResponse() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        // accept loop'un kurulmasına izin ver (kısa)
        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "this_tool_does_not_exist",
            arguments: .object([:]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
        XCTAssertNotNil(response.error)
        XCTAssertTrue(response.error?.contains("Bilinmeyen bridge tool") ?? false)
    }

    /// E2E: bind → BridgeClient.call (notify, body eksik ama title var) → mock-friendly path.
    /// notify SystemNotifications.post çağırır; test ortamında bundle nil olduğu için
    /// no-op. Yine de response success dönmeli.
    func testServerHandlesNotifyWithEmptyBundle() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "notify",
            arguments: .object(["title": .string("Test bildirim")]),
            socketPath: socketPath
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result?.stringValue, "Bildirim gönderildi: Test bildirim")
    }

    func testServerRejectsNotifyWithoutTitle() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "notify",
            arguments: .object([:]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.error?.contains("title") ?? false)
    }

    func testStartStopIsIdempotent() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        try await server.start()  // ikinci çağrı no-op
        await server.stop()
        await server.stop()  // ikinci çağrı no-op
    }

    // MARK: - dispatch_subagent edge cases (real backend e2e atlandı)

    func testDispatchSubagentRejectsMissingPrompt() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "dispatch_subagent",
            arguments: .object(["backend": .string("claude")]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.error?.contains("prompt") ?? false)
    }

    func testDispatchSubagentRejectsInvalidBackend() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "dispatch_subagent",
            arguments: .object([
                "prompt": .string("test"),
                "backend": .string("gpt-4"),
            ]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
        XCTAssertTrue(response.error?.contains("claude/codex/gemini") ?? false)
    }

    func testDispatchSubagentRejectsEmptyPrompt() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        let response = try await BridgeClient.call(
            tool: "dispatch_subagent",
            arguments: .object([
                "prompt": .string(""),
                "backend": .string("claude"),
            ]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
    }

    /// Manager attach edilmiş ve havuz dolu — MCP bridge yeni `dispatch_subagent`
    /// çağrısına `havuzu dolu` hatası döndürmeli.
    func testDispatchSubagentReturnsCapReachedWhenManagerFull() async throws {
        let server = ControlSocketServer(socketPath: socketPath)
        try await server.start()
        defer { Task { await server.stop() } }

        try await Task.sleep(nanoseconds: 50_000_000)

        // MainActor'da max=1 manager + havuzu dolduran ilk dispatch
        let manager = await MainActor.run {
            SubagentManager(maxConcurrent: 1) { _ in StallBackend() }
        }
        await server.attach(manager)

        await MainActor.run {
            _ = manager.dispatch(prompt: "fill the slot", backend: .claude)
        }
        try await Task.sleep(nanoseconds: 80_000_000)

        let response = try await BridgeClient.call(
            tool: "dispatch_subagent",
            arguments: .object([
                "prompt": .string("second"),
                "backend": .string("claude"),
            ]),
            socketPath: socketPath
        )

        XCTAssertFalse(response.ok)
        XCTAssertTrue(
            response.error?.contains("havuzu dolu") ?? false,
            "Beklenen 'havuzu dolu' mesajı, gelen: \(response.error ?? "nil")"
        )

        // Cleanup — bekleyen StallBackend Task'lerini cancel et
        await MainActor.run {
            manager.sessions.forEach { manager.cancel($0.id) }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}
