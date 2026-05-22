import XCTest
@testable import PixelMacApp
@testable import PixelMCPServer

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
}
