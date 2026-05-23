import Foundation

/// MCP (Model Context Protocol) sunucusunun çekirdek logic'i.
///
/// Transport bağımsız: `processLine(_:)` saf string in → string out (test-friendly).
/// Stdio transport için `runStdio()`.
public actor MCPServer {
    public static let protocolVersion = "2024-11-05"

    private let registry: ToolRegistry
    private let serverName: String
    private let serverVersion: String

    public init(
        registry: ToolRegistry = BuiltInTools.makeRegistry(),
        serverName: String = "pixel-agent",
        serverVersion: String = "0.2.17"
    ) {
        self.registry = registry
        self.serverName = serverName
        self.serverVersion = serverVersion
    }

    // MARK: - Method dispatch

    public func handle(request: JSONRPCRequest) async -> JSONRPCResponse? {
        // Notification: id yok → response gönderme.
        let isNotification = request.id == nil

        switch request.method {
        case "initialize":
            if isNotification { return nil }
            return JSONRPCResponse(id: request.id, result: initializeResult())

        case "initialized", "notifications/initialized":
            return nil  // notification → no response

        case "tools/list":
            if isNotification { return nil }
            return JSONRPCResponse(id: request.id, result: registry.listResult())

        case "tools/call":
            if isNotification { return nil }
            switch await handleToolCall(params: request.params) {
            case .success(let value):
                return JSONRPCResponse(id: request.id, result: value)
            case .failure(let error):
                return JSONRPCResponse(id: request.id, error: error)
            }

        case "ping":
            if isNotification { return nil }
            return JSONRPCResponse(id: request.id, result: .object([:]))

        default:
            if isNotification { return nil }  // bilinmeyen notification'ları sessizce yut
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(
                    code: JSONRPCErrorCode.methodNotFound,
                    message: "Method bulunamadı: \(request.method)"
                )
            )
        }
    }

    // MARK: - Method implementations

    private func initializeResult() -> JSONValue {
        .object([
            "protocolVersion": .string(Self.protocolVersion),
            "serverInfo": .object([
                "name": .string(serverName),
                "version": .string(serverVersion),
            ]),
            "capabilities": .object([
                "tools": .object([:]),
            ]),
        ])
    }

    private func handleToolCall(params: JSONValue?) async -> Result<JSONValue, JSONRPCError> {
        guard let name = params?["name"]?.stringValue else {
            return .failure(JSONRPCError(
                code: JSONRPCErrorCode.invalidParams,
                message: "tools/call için `name` zorunlu."
            ))
        }
        guard let tool = registry.find(name) else {
            return .failure(JSONRPCError(
                code: JSONRPCErrorCode.methodNotFound,
                message: "Tool bulunamadı: \(name)"
            ))
        }
        let args = params?["arguments"]
        let result = await tool.handler(args)
        return .success(result)
    }

    // MARK: - Line-level transport

    /// Bir JSON satırını parse edip işler. Response (notification ise nil) JSON string olarak döner.
    /// Decode hataları JSON-RPC parse error (`-32700`) olarak yansır.
    public func processLine(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8) else { return nil }
        do {
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
            guard let response = await handle(request: request) else { return nil }
            return try encode(response)
        } catch {
            let response = JSONRPCResponse(
                id: nil,
                error: JSONRPCError(
                    code: JSONRPCErrorCode.parseError,
                    message: "JSON parse hatası: \(error.localizedDescription)"
                )
            )
            return try? encode(response)
        }
    }

    private func encode(_ response: JSONRPCResponse) throws -> String {
        let data = try JSONEncoder().encode(response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Stdio runner

    /// Stdin'den newline-delimited JSON oku, dispatch et, stdout'a yaz.
    /// EOF / stdin kapanınca döner.
    public func runStdio() async {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            if let response = await processLine(line) {
                print(response)
                // print() default'ta line-buffered; sub-process kullanımında flush kritik.
                fflush(stdout)
            }
        }
    }
}
