import XCTest
@testable import PixelMCPServer

final class BridgeProtocolTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let req = BridgeRequest(
            tool: "dock_badge_set",
            arguments: .object(["label": .string("3")])
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(BridgeRequest.self, from: data)
        XCTAssertEqual(decoded.tool, "dock_badge_set")
        XCTAssertEqual(decoded.arguments["label"]?.stringValue, "3")
    }

    func testResponseSuccessRoundTrip() throws {
        let resp = BridgeResponse.success(.string("OK"))
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(BridgeResponse.self, from: data)
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(decoded.result?.stringValue, "OK")
        XCTAssertNil(decoded.error)
    }

    func testResponseFailureRoundTrip() throws {
        let resp = BridgeResponse.failure("bağlanamadı")
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(BridgeResponse.self, from: data)
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(decoded.error, "bağlanamadı")
        XCTAssertNil(decoded.result)
    }

    func testRequestDefaultArguments() {
        let req = BridgeRequest(tool: "notify")
        if case .object(let obj) = req.arguments {
            XCTAssertTrue(obj.isEmpty)
        } else {
            XCTFail("default arguments should be empty object")
        }
    }

    func testDefaultSocketPathInUserCache() {
        let path = BridgePaths.defaultSocketPath()
        XCTAssertTrue(path.contains("Library/Caches/dev.erkutyavuzer.pixel-agent"))
        XCTAssertTrue(path.hasSuffix("/control.sock"))
    }

    func testDefaultSocketPathLengthFitsSunPath() {
        let path = BridgePaths.defaultSocketPath()
        XCTAssertLessThanOrEqual(path.utf8CString.count, BridgePaths.maxSocketPathLength)
    }

    func testBridgeClientFailsOnMissingSocket() async {
        // Var olmayan path → connect EACCES/ENOENT, hata fırlatmalı
        let badPath = "/tmp/pixel-agent-test-nonexistent-\(UUID().uuidString).sock"
        do {
            _ = try await BridgeClient.call(tool: "noop", socketPath: badPath)
            XCTFail("Expected error")
        } catch {
            // Beklenen — herhangi bir BridgeError
            XCTAssertTrue(error is BridgeClient.BridgeError)
        }
    }
}
