import Foundation

/// MCP server <-> PixelMacApp arasındaki Unix socket köprüsünde taşınan mesaj.
///
/// Taşıma: newline-delimited JSON (tek satır = tek mesaj). Hâlihazırda MCP
/// stdio transport'unun aynı satır formatı.
public struct BridgeRequest: Codable, Sendable {
    public let tool: String
    public let arguments: JSONValue

    public init(tool: String, arguments: JSONValue = .object([:])) {
        self.tool = tool
        self.arguments = arguments
    }
}

public struct BridgeResponse: Codable, Sendable {
    public let ok: Bool
    public let result: JSONValue?
    public let error: String?

    public init(ok: Bool, result: JSONValue? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.error = error
    }

    public static func success(_ result: JSONValue = .object([:])) -> BridgeResponse {
        BridgeResponse(ok: true, result: result, error: nil)
    }

    public static func failure(_ error: String) -> BridgeResponse {
        BridgeResponse(ok: false, result: nil, error: error)
    }
}

public enum BridgePaths {
    /// `~/Library/Caches/dev.erkutyavuzer.pixel-agent/control.sock`
    ///
    /// Dizin yoksa oluşturulur (mkdir -p). sandbox-aware değil — pixel-agent
    /// şu an sandboxed olarak ship edilmiyor.
    public static func defaultSocketPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("dev.erkutyavuzer.pixel-agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("control.sock").path
    }

    /// `sockaddr_un.sun_path` 104 byte (BSD/macOS). Path bundan uzunsa bind/connect
    /// EINVAL döndürür — preflight kontrol için.
    public static let maxSocketPathLength = 104
}
