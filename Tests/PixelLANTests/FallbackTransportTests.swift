import XCTest
import PixelRemote
@testable import PixelLAN

/// Test-only stub transport — connect başarısı/başarısızlığını kontrol eder.
private actor StubTransport: RemoteTransport {
    enum Behavior {
        case succeed
        case fail
    }

    let behavior: Behavior
    var connectCallCount = 0
    var sendCallCount = 0
    var disconnectCallCount = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func connect() async throws -> AsyncThrowingStream<RemoteEnvelope, any Error> {
        connectCallCount += 1
        switch behavior {
        case .succeed:
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        case .fail:
            throw NSError(domain: "Stub", code: 1, userInfo: [NSLocalizedDescriptionKey: "stub fail"])
        }
    }

    func send(_ envelope: RemoteEnvelope) async throws {
        sendCallCount += 1
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func counts() -> (connect: Int, send: Int, disconnect: Int) {
        (connectCallCount, sendCallCount, disconnectCallCount)
    }
}

final class FallbackTransportTests: XCTestCase {
    func testPrimarySuccessPicksPrimary() async throws {
        let primary = StubTransport(behavior: .succeed)
        let fallback = StubTransport(behavior: .succeed)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        _ = try await composite.connect()
        let selection = await composite.currentSelection
        XCTAssertEqual(selection, .primary)

        let pCounts = await primary.counts()
        let fCounts = await fallback.counts()
        XCTAssertEqual(pCounts.connect, 1)
        XCTAssertEqual(fCounts.connect, 0)  // fallback denemedi
    }

    func testPrimaryFailureSwitchesToFallback() async throws {
        let primary = StubTransport(behavior: .fail)
        let fallback = StubTransport(behavior: .succeed)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        _ = try await composite.connect()
        let selection = await composite.currentSelection
        XCTAssertEqual(selection, .fallback)

        let pCounts = await primary.counts()
        let fCounts = await fallback.counts()
        XCTAssertEqual(pCounts.connect, 1)
        XCTAssertEqual(fCounts.connect, 1)
        XCTAssertEqual(pCounts.disconnect, 1)  // primary'nin partial state'i temizlendi
    }

    func testBothFailuresPropagateError() async {
        let primary = StubTransport(behavior: .fail)
        let fallback = StubTransport(behavior: .fail)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        do {
            _ = try await composite.connect()
            XCTFail("connect should throw when both fail")
        } catch {
            // Beklenen — fallback'in hatası
        }
        let selection = await composite.currentSelection
        XCTAssertEqual(selection, .none)
    }

    func testSendBeforeConnectThrows() async {
        let primary = StubTransport(behavior: .succeed)
        let fallback = StubTransport(behavior: .succeed)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        do {
            try await composite.send(RemoteEnvelope.ping())
            XCTFail("send should throw before connect")
        } catch {
            XCTAssertTrue(error is FallbackTransport.FallbackError)
        }
    }

    func testSendRoutesToActiveTransport() async throws {
        let primary = StubTransport(behavior: .succeed)
        let fallback = StubTransport(behavior: .succeed)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        _ = try await composite.connect()
        try await composite.send(RemoteEnvelope.ping())

        let pCounts = await primary.counts()
        let fCounts = await fallback.counts()
        XCTAssertEqual(pCounts.send, 1)
        XCTAssertEqual(fCounts.send, 0)
    }

    func testDisconnectResetsSelection() async throws {
        let primary = StubTransport(behavior: .succeed)
        let fallback = StubTransport(behavior: .succeed)
        let composite = FallbackTransport(primary: primary, fallback: fallback)

        _ = try await composite.connect()
        await composite.disconnect()
        let selection = await composite.currentSelection
        XCTAssertEqual(selection, .none)
    }
}
