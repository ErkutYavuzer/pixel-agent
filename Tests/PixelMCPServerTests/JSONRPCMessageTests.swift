import XCTest
@testable import PixelMCPServer

final class JSONRPCMessageTests: XCTestCase {
    func testDecodeRequestWithIntID() throws {
        let json = #"{"jsonrpc":"2.0","id":42,"method":"initialize","params":{}}"#
        let req = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        XCTAssertEqual(req.method, "initialize")
        XCTAssertEqual(req.id, .int(42))
        XCTAssertNotNil(req.params)
    }

    func testDecodeRequestWithStringID() throws {
        let json = #"{"jsonrpc":"2.0","id":"req-1","method":"tools/list"}"#
        let req = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        XCTAssertEqual(req.id, .string("req-1"))
        XCTAssertNil(req.params)
    }

    func testDecodeNotification() throws {
        // id alanı yoksa notification.
        let json = #"{"jsonrpc":"2.0","method":"initialized"}"#
        let req = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        XCTAssertNil(req.id)
        XCTAssertEqual(req.method, "initialized")
    }

    func testEncodeSuccessResponse() throws {
        let resp = JSONRPCResponse(id: .int(7), result: .object(["ok": .bool(true)]))
        let data = try JSONEncoder().encode(resp)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"id\":7"))
        XCTAssertTrue(str.contains("\"result\""))
        XCTAssertFalse(str.contains("\"error\""))
    }

    func testEncodeErrorResponse() throws {
        let resp = JSONRPCResponse(
            id: .string("x"),
            error: JSONRPCError(code: -32601, message: "Method bulunamadı")
        )
        let data = try JSONEncoder().encode(resp)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"error\""))
        XCTAssertTrue(str.contains("-32601"))
        XCTAssertFalse(str.contains("\"result\""))
    }

    func testErrorCodeConstants() {
        XCTAssertEqual(JSONRPCErrorCode.parseError, -32700)
        XCTAssertEqual(JSONRPCErrorCode.invalidRequest, -32600)
        XCTAssertEqual(JSONRPCErrorCode.methodNotFound, -32601)
        XCTAssertEqual(JSONRPCErrorCode.invalidParams, -32602)
        XCTAssertEqual(JSONRPCErrorCode.internalError, -32603)
    }
}
