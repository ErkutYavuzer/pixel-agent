import XCTest
@testable import PixelRemote

final class RelayTransportTests: XCTestCase {
    func testInitWithValidURL() {
        let url = URL(string: "ws://example.com:8787")!
        let transport = RelayTransport(
            relayURL: url,
            pairingCode: "ABCDEF",
            role: .mac
        )
        _ = transport
    }

    func testInitWithMacRole() {
        let url = URL(string: "wss://relay.example.com")!
        let transport = RelayTransport(
            relayURL: url,
            pairingCode: "ABCDEF",
            role: .mac
        )
        _ = transport
    }

    func testInitWithIOSRole() {
        let url = URL(string: "wss://relay.example.com")!
        let transport = RelayTransport(
            relayURL: url,
            pairingCode: "ABCDEF",
            role: .ios
        )
        _ = transport
    }

    func testConnectThrowsForInvalidPairingCode() async {
        let url = URL(string: "ws://example.com")!
        let transport = RelayTransport(
            relayURL: url,
            pairingCode: "00",  // 6 char değil
            role: .mac
        )
        do {
            _ = try await transport.connect()
            XCTFail("Should throw for invalid pairing code")
        } catch {
            // Beklenen — RelayClient validation fail eder
            XCTAssertTrue(error is RelayError)
        }
    }

    func testDisconnectIsIdempotent() async {
        let url = URL(string: "ws://example.com")!
        let transport = RelayTransport(
            relayURL: url,
            pairingCode: "ABCDEF",
            role: .mac
        )
        await transport.disconnect()
        await transport.disconnect()
    }
}
