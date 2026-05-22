import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// MCP tool tanımı: name + description + JSON Schema + async handler.
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let handler: @Sendable (JSONValue?) async -> JSONValue

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        handler: @escaping @Sendable (JSONValue?) async -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }

    /// MCP `tools/list` çıktısı için JSON temsili.
    public var descriptor: JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": inputSchema,
        ])
    }
}

/// Kayıtlı tool'ları tutan kaydedici.
public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: ToolDefinition] = [:]

    public init() {}

    public func register(_ tool: ToolDefinition) {
        tools[tool.name] = tool
    }

    public func all() -> [ToolDefinition] {
        tools.values.sorted { $0.name < $1.name }
    }

    public func find(_ name: String) -> ToolDefinition? {
        tools[name]
    }

    /// MCP `tools/list` response payload.
    public func listResult() -> JSONValue {
        .object(["tools": .array(all().map { $0.descriptor })])
    }
}

// MARK: - Tool result helpers

public enum ToolResultBuilder {
    /// Tek metin bloklu başarılı sonuç.
    public static func text(_ text: String, isError: Bool = false) -> JSONValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                ]),
            ]),
            "isError": .bool(isError),
        ])
    }

    public static func error(_ message: String) -> JSONValue {
        text(message, isError: true)
    }
}

// MARK: - Built-in tools (saf-data — bundle bağımsız)

public enum BuiltInTools {
    /// Tüm built-in tool'ları içeren registry üretir.
    /// Saf-data tool'lar (clipboard, time, active app, lan ip) standalone çalışır;
    /// bridge tool'ları (dock_badge_set, notify, play_sound) PixelMacApp Unix
    /// socket'i (`BridgePaths.defaultSocketPath()`) üzerinden execute olur.
    public static func makeRegistry() -> ToolRegistry {
        let registry = ToolRegistry()
        registry.register(getClipboard)
        registry.register(setClipboard)
        registry.register(getCurrentTime)
        registry.register(getActiveApp)
        registry.register(getLANIP)
        // Bridge tool'lar — PixelMacApp çalışmıyorsa "bağlanamadı" error döner.
        registry.register(dockBadgeSet)
        registry.register(notify)
        registry.register(playSound)
        return registry
    }

    static let getClipboard = ToolDefinition(
        name: "get_clipboard",
        description: "macOS pano (clipboard) içeriğindeki metni döner.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        handler: { _ in
            #if canImport(AppKit)
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            return ToolResultBuilder.text(text)
            #else
            return ToolResultBuilder.error("Clipboard sadece macOS'ta destekleniyor.")
            #endif
        }
    )

    static let setClipboard = ToolDefinition(
        name: "set_clipboard",
        description: "macOS panosuna verilen metni yazar.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Panoya yazılacak metin"),
                ]),
            ]),
            "required": .array([.string("text")]),
        ]),
        handler: { params in
            guard let text = params?["text"]?.stringValue else {
                return ToolResultBuilder.error("`text` parametresi zorunlu.")
            }
            #if canImport(AppKit)
            let pb = NSPasteboard.general
            pb.clearContents()
            let ok = pb.setString(text, forType: .string)
            return ToolResultBuilder.text(ok ? "Panoya yazıldı (\(text.count) karakter)." : "Yazma başarısız.", isError: !ok)
            #else
            return ToolResultBuilder.error("Clipboard sadece macOS'ta destekleniyor.")
            #endif
        }
    )

    static let getCurrentTime = ToolDefinition(
        name: "get_current_time",
        description: "Geçerli saati ISO 8601 (UTC offset dahil) olarak döner.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        handler: { _ in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return ToolResultBuilder.text(formatter.string(from: Date()))
        }
    )

    static let getActiveApp = ToolDefinition(
        name: "get_active_app",
        description: "macOS'ta önde olan (frontmost) uygulamanın adı + bundle ID'sini döner.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        handler: { _ in
            #if canImport(AppKit)
            let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
            let name = app?.localizedName ?? "(bilinmiyor)"
            let bid = app?.bundleIdentifier ?? "(yok)"
            return ToolResultBuilder.text("\(name) — \(bid)")
            #else
            return ToolResultBuilder.error("Active app sadece macOS'ta destekleniyor.")
            #endif
        }
    )

    static let getLANIP = ToolDefinition(
        name: "get_lan_ip",
        description: "en0/en1 üzerindeki primary LAN IPv4 adresini döner (varsa).",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        handler: { _ in
            if let ip = LANInterfaceAddress.primary() {
                return ToolResultBuilder.text(ip)
            }
            return ToolResultBuilder.error("LAN IP tespit edilemedi (en0/en1 inactive).")
        }
    )

    // MARK: - Bridge tools (PixelMacApp gerektirir)

    static let dockBadgeSet = ToolDefinition(
        name: "dock_badge_set",
        description: "PixelAgent.app Dock ikonunun badge etiketini ayarlar (boş string veya null = temizle). PixelAgent.app çalışıyor olmalı.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "label": .object([
                    "type": .array([.string("string"), .string("null")]),
                    "description": .string("Badge metni veya null (temizle)"),
                ]),
            ]),
        ]),
        handler: { params in
            let label = params?["label"]?.stringValue  // null → nil
            return await callBridge(tool: "dock_badge_set", arguments: .object([
                "label": label.map { .string($0) } ?? .null,
            ]))
        }
    )

    static let notify = ToolDefinition(
        name: "notify",
        description: "macOS bildirim merkezi üzerinden kullanıcıya bildirim gönderir. PixelAgent.app çalışıyor olmalı.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object([
                    "type": .string("string"),
                    "description": .string("Bildirim başlığı (zorunlu)"),
                ]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Bildirim gövdesi (opsiyonel)"),
                ]),
            ]),
            "required": .array([.string("title")]),
        ]),
        handler: { params in
            guard let title = params?["title"]?.stringValue else {
                return ToolResultBuilder.error("`title` parametresi zorunlu.")
            }
            var args: [String: JSONValue] = ["title": .string(title)]
            if let body = params?["body"]?.stringValue { args["body"] = .string(body) }
            return await callBridge(tool: "notify", arguments: .object(args))
        }
    )

    static let playSound = ToolDefinition(
        name: "play_sound",
        description: "Bir macOS sistem sesi çalar. PixelAgent.app çalışıyor olmalı.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string("Sistem ses adı (örn: Glass, Basso, Tink, Ping, Pop, Funk, Submarine, Sosumi)"),
                ]),
            ]),
            "required": .array([.string("name")]),
        ]),
        handler: { params in
            guard let name = params?["name"]?.stringValue else {
                return ToolResultBuilder.error("`name` parametresi zorunlu.")
            }
            return await callBridge(tool: "play_sound", arguments: .object([
                "name": .string(name),
            ]))
        }
    )

    /// BridgeClient.call() sarmalayıcı — başarı/başarısızlık MCP `content` shape'ine
    /// dönüştürür. PixelAgent.app çalışmıyorsa connect EACCES/ENOENT döner.
    private static func callBridge(tool: String, arguments: JSONValue) async -> JSONValue {
        do {
            let response = try await BridgeClient.call(tool: tool, arguments: arguments)
            if response.ok {
                let text = response.result?.stringValue ?? "OK"
                return ToolResultBuilder.text(text)
            }
            return ToolResultBuilder.error(response.error ?? "Bilinmeyen bridge hatası.")
        } catch {
            return ToolResultBuilder.error((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}
