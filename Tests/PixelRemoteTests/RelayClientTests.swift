import Foundation
import XCTest

@testable import PixelRemote

final class RelayRoleTests: XCTestCase {
    func testPathComponents() {
        XCTAssertEqual(RelayRole.mac.pathComponent, "connect")
        XCTAssertEqual(RelayRole.ios.pathComponent, "listen")
    }
}

final class RelayErrorTests: XCTestCase {
    func testNotConnectedDescription() {
        XCTAssertEqual(RelayError.notConnected.errorDescription, "Relay'e bağlı değil.")
    }

    func testInvalidPairingCodeIncludesCodeInMessage() {
        let error = RelayError.invalidPairingCode("xyz")
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("xyz"), "description should include the invalid code")
    }

    func testInvalidRelayURLDescription() {
        XCTAssertEqual(RelayError.invalidRelayURL.errorDescription, "Geçersiz relay URL.")
    }

    func testEncodingFailedIncludesUnderlyingMessage() {
        let error = RelayError.encodingFailed("test reason")
        XCTAssertTrue((error.errorDescription ?? "").contains("test reason"))
    }
}

final class RelayClientTests: XCTestCase {
    func testConnectRejectsInvalidPairingCode() async {
        let client = RelayClient()
        do {
            _ = try await client.connect(
                relayURL: URL(string: "ws://localhost:8787")!,
                pairingCode: "abc",
                role: .mac
            )
            XCTFail("Expected RelayError.invalidPairingCode")
        } catch let error as RelayError {
            if case .invalidPairingCode(let code) = error {
                XCTAssertEqual(code, "abc")
            } else {
                XCTFail("Expected invalidPairingCode, got \(error)")
            }
        } catch {
            XCTFail("Expected RelayError, got \(error)")
        }
    }

    func testConnectRejectsNonWebSocketScheme() async {
        let client = RelayClient()
        do {
            _ = try await client.connect(
                relayURL: URL(string: "https://example.com")!,
                pairingCode: "ABC234",
                role: .mac
            )
            XCTFail("Expected RelayError.invalidRelayURL")
        } catch let error as RelayError {
            XCTAssertEqual(error, .invalidRelayURL)
        } catch {
            XCTFail("Expected RelayError, got \(error)")
        }
    }

    func testSendThrowsWhenNotConnected() async {
        let client = RelayClient()
        let envelope = RemoteEnvelope.ping()
        do {
            try await client.send(envelope)
            XCTFail("Expected RelayError.notConnected")
        } catch let error as RelayError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Expected RelayError, got \(error)")
        }
    }

    func testDisconnectIsIdempotent() async {
        let client = RelayClient()
        await client.disconnect()
        await client.disconnect()
    }
}
