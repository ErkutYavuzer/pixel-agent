import XCTest
import CryptoKit

@testable import PixelRemote

final class RemoteHostTests: XCTestCase {
    @MainActor
    private func makeHost(
        relayURL: String = "ws://localhost:8787"
    ) -> RemoteHost {
        RemoteHost(
            relayURL: relayURL,
            keyStore: InMemoryKeyStore(),
            keyService: "test.pixel-agent",
            keyAccount: "test-mac-key"
        )
    }

    @MainActor
    func testInitWithDefaultURL() {
        let host = makeHost()
        XCTAssertEqual(host.relayURL, "ws://localhost:8787")
        XCTAssertFalse(host.isConnected)
        XCTAssertFalse(host.isPaired)
        XCTAssertNil(host.lastError)
        XCTAssertTrue(PairingCode.isValid(host.pairingCode))
    }

    @MainActor
    func testCustomRelayURL() {
        let host = makeHost(relayURL: "wss://example.workers.dev")
        XCTAssertEqual(host.relayURL, "wss://example.workers.dev")
    }

    @MainActor
    func testRegenerateCodeChangesCode() {
        let host = makeHost()
        let original = host.pairingCode
        host.regenerateCode()
        XCTAssertNotEqual(host.pairingCode, original)
        XCTAssertTrue(PairingCode.isValid(host.pairingCode))
    }

    @MainActor
    func testConnectSetsErrorOnInvalidURL() async {
        let host = makeHost(relayURL: "")
        await host.connect()
        XCTAssertNotNil(host.lastError)
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testConnectSetsErrorOnNonWebSocketScheme() async {
        let host = makeHost(relayURL: "https://example.com")
        await host.connect()
        XCTAssertNotNil(host.lastError)
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testSendAssistantWhenDisconnectedIsNoOp() async {
        let host = makeHost()
        await host.sendAssistantMessage("test")
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testDisconnectIsIdempotentBeforeConnect() async {
        let host = makeHost()
        await host.disconnect()
        await host.disconnect()
        XCTAssertFalse(host.isConnected)
    }

    @MainActor
    func testPublicKeyBase64IsExposedAndDecodable() throws {
        let host = makeHost()
        XCTAssertFalse(host.publicKeyBase64.isEmpty)
        let data = try XCTUnwrap(Data(base64Encoded: host.publicKeyBase64))
        XCTAssertEqual(data.count, 32) // ed25519 pubkey
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: data))
    }

    @MainActor
    func testSameKeyStoreReturnsSamePublicKeyAcrossInstances() {
        let store = InMemoryKeyStore()
        let h1 = RemoteHost(
            relayURL: "ws://x",
            keyStore: store,
            keyService: "svc", keyAccount: "acct"
        )
        let h2 = RemoteHost(
            relayURL: "ws://x",
            keyStore: store,
            keyService: "svc", keyAccount: "acct"
        )
        XCTAssertEqual(h1.publicKeyBase64, h2.publicKeyBase64)
    }

    @MainActor
    func testDifferentKeyStoresProduceDifferentPublicKeys() {
        let h1 = RemoteHost(
            relayURL: "ws://x",
            keyStore: InMemoryKeyStore(),
            keyService: "svc", keyAccount: "acct"
        )
        let h2 = RemoteHost(
            relayURL: "ws://x",
            keyStore: InMemoryKeyStore(),
            keyService: "svc", keyAccount: "acct"
        )
        XCTAssertNotEqual(h1.publicKeyBase64, h2.publicKeyBase64)
    }
}
