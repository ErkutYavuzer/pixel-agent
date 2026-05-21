import XCTest

@testable import PixelRemote

final class RemoteHostTests: XCTestCase {
    @MainActor
    func testInitWithDefaultURL() {
        let host = RemoteHost()
        XCTAssertEqual(host.relayURL, "ws://localhost:8787")
        XCTAssertFalse(host.isConnected)
        XCTAssertNil(host.lastError)
        XCTAssertTrue(PairingCode.isValid(host.pairingCode))
    }

    @MainActor
    func testCustomRelayURL() {
        let host = RemoteHost(relayURL: "wss://example.workers.dev")
        XCTAssertEqual(host.relayURL, "wss://example.workers.dev")
    }

    @MainActor
    func testRegenerateCodeChangesCode() {
        let host = RemoteHost()
        let original = host.pairingCode
        host.regenerateCode()
        XCTAssertNotEqual(host.pairingCode, original)
        XCTAssertTrue(PairingCode.isValid(host.pairingCode))
    }

    @MainActor
    func testConnectSetsErrorOnInvalidURL() async {
        let host = RemoteHost(relayURL: "")
        await host.connect()
        XCTAssertNotNil(host.lastError)
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testConnectSetsErrorOnNonWebSocketScheme() async {
        let host = RemoteHost(relayURL: "https://example.com")
        await host.connect()
        XCTAssertNotNil(host.lastError)
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testSendAssistantWhenDisconnectedIsNoOp() async {
        let host = RemoteHost()
        await host.sendAssistantMessage("test")
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testDisconnectIsIdempotentBeforeConnect() async {
        let host = RemoteHost()
        await host.disconnect()
        await host.disconnect()
        XCTAssertFalse(host.isConnected)
    }
}
