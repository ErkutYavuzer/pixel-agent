import XCTest
@testable import PixelMCPServer

final class MCPServerTests: XCTestCase {
    private func makeServer() -> MCPServer {
        let registry = ToolRegistry()
        registry.register(ToolDefinition(
            name: "echo",
            description: "Test tool — input metnini geri yansıtır.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                ]),
            ]),
            handler: { params in
                let text = params?["text"]?.stringValue ?? ""
                return ToolResultBuilder.text("echo: \(text)")
            }
        ))
        return MCPServer(registry: registry, serverName: "test-server", serverVersion: "1.0.0")
    }

    func testInitializeReturnsServerInfo() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(id: .int(1), method: "initialize", params: .object([:]))
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        let result = try XCTUnwrap(resp.result)
        XCTAssertEqual(result["protocolVersion"]?.stringValue, MCPServer.protocolVersion)
        XCTAssertEqual(result["serverInfo"]?["name"]?.stringValue, "test-server")
        XCTAssertEqual(result["serverInfo"]?["version"]?.stringValue, "1.0.0")
        XCTAssertNotNil(result["capabilities"]?["tools"])
    }

    func testInitializedNotificationProducesNoResponse() async {
        let server = makeServer()
        let req = JSONRPCRequest(id: nil, method: "initialized", params: nil)
        let resp = await server.handle(request: req)
        XCTAssertNil(resp)
    }

    func testToolsListReturnsRegisteredTools() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(id: .int(2), method: "tools/list", params: nil)
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        let tools = try XCTUnwrap(resp.result?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"]?.stringValue, "echo")
    }

    func testToolsCallInvokesHandler() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(
            id: .int(3),
            method: "tools/call",
            params: .object([
                "name": .string("echo"),
                "arguments": .object(["text": .string("merhaba")]),
            ])
        )
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        let content = try XCTUnwrap(resp.result?["content"]?.arrayValue)
        XCTAssertEqual(content[0]["text"]?.stringValue, "echo: merhaba")
        XCTAssertEqual(resp.result?["isError"]?.boolValue, false)
    }

    func testToolsCallUnknownToolReturnsMethodNotFound() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(
            id: .int(4),
            method: "tools/call",
            params: .object(["name": .string("does_not_exist")])
        )
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        XCTAssertNotNil(resp.error)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testToolsCallMissingNameReturnsInvalidParams() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(
            id: .int(5),
            method: "tools/call",
            params: .object([:])
        )
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.invalidParams)
    }

    func testUnknownMethodReturnsMethodNotFound() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(id: .int(6), method: "made/up", params: nil)
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.methodNotFound)
    }

    func testPingReturnsEmptyObject() async throws {
        let server = makeServer()
        let req = JSONRPCRequest(id: .int(7), method: "ping", params: nil)
        let respOpt = await server.handle(request: req)
        let resp = try XCTUnwrap(respOpt)
        XCTAssertEqual(resp.result, .object([:]))
    }

    func testProcessLineEndToEnd() async throws {
        let server = makeServer()
        let line = #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"echo","arguments":{"text":"x"}}}"#
        let result = await server.processLine(line)
        let out = try XCTUnwrap(result)
        let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(out.utf8))
        XCTAssertEqual(resp.id, .int(10))
        XCTAssertEqual(resp.result?["content"]?.arrayValue?[0]["text"]?.stringValue, "echo: x")
    }

    func testProcessLineBadJSONReturnsParseError() async throws {
        let server = makeServer()
        let result = await server.processLine("{not json")
        let out = try XCTUnwrap(result)
        let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: Data(out.utf8))
        XCTAssertEqual(resp.error?.code, JSONRPCErrorCode.parseError)
    }

    func testProcessLineNotificationProducesNil() async {
        let server = makeServer()
        let out = await server.processLine(#"{"jsonrpc":"2.0","method":"initialized"}"#)
        XCTAssertNil(out)
    }
}
