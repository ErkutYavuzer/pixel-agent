import Foundation

/// JSON-RPC 2.0 id alanı (int veya string).
public enum JSONRPCID: Codable, Equatable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON-RPC id sadece int veya string olabilir"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let i): try container.encode(i)
        case .string(let s): try container.encode(s)
        }
    }
}

/// JSON-RPC 2.0 request veya notification.
/// `id` nil ise notification — server cevap göndermez.
public struct JSONRPCRequest: Decodable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response (`result` veya `error`'dan tam biri set).
public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(id: JSONRPCID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: JSONRPCID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        self.id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)
        self.result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        self.error = try container.decodeIfPresent(JSONRPCError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        if let result {
            try container.encode(result, forKey: .result)
        }
        if let error {
            try container.encode(error, forKey: .error)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, result, error
    }
}

public struct JSONRPCError: Codable, Sendable, Equatable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}
