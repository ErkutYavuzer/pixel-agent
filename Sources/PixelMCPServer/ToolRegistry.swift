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
        registry.register(dispatchSubagent)
        // Computer use (ADR-0026 + ADR-0028) — bridge tool'lar.
        registry.register(uiQuery)
        registry.register(uiClick)
        registry.register(uiType)
        registry.register(uiScreenshot)
        registry.register(uiResolve)
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

    static let dispatchSubagent = ToolDefinition(
        name: "dispatch_subagent",
        description: """
            Bir LLM CLI'sını (claude/codex/gemini) budget'lı tek-turlu subagent olarak \
            çalıştırır. Sonuç JSON'unda status (completed/budget_exceeded/cancelled/failed) \
            + output + duration_seconds + backend döner. PixelAgent.app çalışıyor olmalı. \
            Bridge bağlantısı subagent süresince açık kalır — `max_duration_seconds`'ı \
            MCP client timeout'unuzun altında tutun.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object([
                    "type": .string("string"),
                    "description": .string("Subagent'a gönderilecek prompt"),
                ]),
                "backend": .object([
                    "type": .string("string"),
                    "enum": .array([.string("claude"), .string("codex"), .string("gemini")]),
                    "description": .string("Hangi CLI çalışsın"),
                ]),
                "max_duration_seconds": .object([
                    "type": .string("number"),
                    "description": .string("Wallclock budget (varsayılan 60). Aşılırsa stream cancel + status=budget_exceeded."),
                ]),
                "max_output_bytes": .object([
                    "type": .string("integer"),
                    "description": .string("Toplam çıktı için UTF-8 byte cap (opsiyonel, varsayılan sınırsız)."),
                ]),
            ]),
            "required": .array([.string("prompt"), .string("backend")]),
        ]),
        handler: { params in
            guard let prompt = params?["prompt"]?.stringValue, !prompt.isEmpty else {
                return ToolResultBuilder.error("`prompt` zorunlu.")
            }
            guard let backend = params?["backend"]?.stringValue else {
                return ToolResultBuilder.error("`backend` zorunlu (claude/codex/gemini).")
            }
            var args: [String: JSONValue] = [
                "prompt": .string(prompt),
                "backend": .string(backend),
            ]
            if let dur = params?["max_duration_seconds"] {
                args["max_duration_seconds"] = dur
            }
            if let bytes = params?["max_output_bytes"] {
                args["max_output_bytes"] = bytes
            }
            return await callBridge(tool: "dispatch_subagent", arguments: .object(args))
        }
    )

    // MARK: - Computer use (ADR-0026)

    /// `UIQuery` JSON schema — `ui_query/ui_click/ui_type` tarafından paylaşılır.
    ///
    /// Faz 3a (v0.2.13): `contains_text` + `within` parametreleri eklendi.
    static let uiQuerySchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "bundle_id": .object([
                "type": .string("string"),
                "description": .string("Hedef uygulama bundle ID'si (örn. com.apple.Safari). Atlanırsa frontmost app."),
            ]),
            "role": .object([
                "type": .string("string"),
                "description": .string("AX role (örn. AXButton, AXTextField, AXLink, AXMenuItem). * = herhangi."),
            ]),
            "title": .object([
                "type": .string("string"),
                "description": .string("AXTitle değeri."),
            ]),
            "label": .object([
                "type": .string("string"),
                "description": .string("AXDescription veya AXLabel değeri."),
            ]),
            "identifier": .object([
                "type": .string("string"),
                "description": .string("AXIdentifier (Accessibility Inspector). Set ise diğer alanlar override edilir."),
            ]),
            "contains_text": .object([
                "type": .string("string"),
                "description": .string("title VEYA label içinde case-insensitive substring. match_mode'a tabi değil."),
            ]),
            "within": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "description": .string("Ancestor constraint — kendisi de bir UIQuery (recursive)."),
                ]),
                "description": .string("Element'in her constraint için uyan en az bir ancestor'a sahip olması gerekir (AND)."),
            ]),
            "match_mode": .object([
                "type": .string("string"),
                "enum": .array([.string("exact"), .string("fuzzy"), .string("regex")]),
                "description": .string("title/label eşleşme stratejisi. Default exact."),
            ]),
            "max_depth": .object([
                "type": .string("integer"),
                "description": .string("Tree traversal max derinlik (default 12)."),
            ]),
            "timeout": .object([
                "type": .string("number"),
                "description": .string("Genel timeout (saniye, default 3.0)."),
            ]),
        ]),
    ])

    static let uiQuery = ToolDefinition(
        name: "ui_query",
        description: """
            macOS AX hiyerarşisini tarayıp eşleşen UI element'leri JSON listesi olarak döner.
            Read-only — Plan modunda kullanılabilir. Accessibility izni gerekir. \
            Sonuç: { role, title, label, identifier, frame:{x,y,w,h}, bundle_id, path[], opaque_id }.
            """,
        inputSchema: uiQuerySchema,
        handler: { params in
            await callBridge(tool: "ui_query", arguments: .object(["query": params ?? .object([:])]))
        }
    )

    static let uiClick = ToolDefinition(
        name: "ui_click",
        description: """
            UIQuery'ye uyan tek element'i tıklar (CGEvent leftMouseDown/Up). \
            Destructive — Plan modunda kullanılmamalı. count=2 double-click. \
            modifiers: ["command","option","shift","control"] kombinleri (⌘-click vb). \
            0 eşleşme → noMatch hatası; ≥2 → ambiguousMatch (query daraltılmalı). \
            Accessibility izni gerekir.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": uiQuerySchema,
                "count": .object([
                    "type": .string("integer"),
                    "description": .string("Tıklama sayısı (default 1, double-click=2)."),
                ]),
                "modifiers": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("command"), .string("option"),
                            .string("shift"), .string("control"),
                        ]),
                    ]),
                    "description": .string("Tıklama sırasında basılı tutulacak modifier tuşlar (Faz 3b)."),
                ]),
            ]),
            "required": .array([.string("query")]),
        ]),
        handler: { params in
            if let err = planModeGuard("ui_click") { return err }
            guard let query = params?["query"] else {
                return ToolResultBuilder.error("`query` parametresi zorunlu.")
            }
            var args: [String: JSONValue] = ["query": query]
            if let count = params?["count"] { args["count"] = count }
            if let mods = params?["modifiers"] { args["modifiers"] = mods }
            return await callBridge(tool: "ui_click", arguments: .object(args))
        }
    )

    static let uiType = ToolDefinition(
        name: "ui_type",
        description: """
            Aktif text input element'ine veya `into` query'sine uyan element'e \
            metin yazar (CGEvent unicode key inject). Destructive — Plan modunda \
            kullanılmamalı. Accessibility izni gerekir.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Yazılacak metin (Unicode-aware)."),
                ]),
                "into": uiQuerySchema,
            ]),
            "required": .array([.string("text")]),
        ]),
        handler: { params in
            if let err = planModeGuard("ui_type") { return err }
            guard let text = params?["text"]?.stringValue else {
                return ToolResultBuilder.error("`text` parametresi zorunlu.")
            }
            var args: [String: JSONValue] = ["text": .string(text)]
            if let into = params?["into"] { args["into"] = into }
            return await callBridge(tool: "ui_type", arguments: .object(args))
        }
    )

    static let uiResolve = ToolDefinition(
        name: "ui_resolve",
        description: """
            Daha önce ui_query ile alınmış bir `opaque_id`'den canlı element snapshot'ı \
            döndürür. Cache yok — her çağrı AX path'i tekrar yürür. Element artık yoksa \
            (UI değişmiş, app kapanmış vs.) sonuç boş gelir. Read-only — Plan modunda \
            kullanılabilir. Accessibility izni gerekir.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "opaque_id": .object([
                    "type": .string("string"),
                    "description": .string("ui_query sonucundaki opaque_id alanı."),
                ]),
            ]),
            "required": .array([.string("opaque_id")]),
        ]),
        handler: { params in
            guard let oid = params?["opaque_id"]?.stringValue else {
                return ToolResultBuilder.error("`opaque_id` parametresi zorunlu.")
            }
            return await callBridge(tool: "ui_resolve", arguments: .object(["opaque_id": .string(oid)]))
        }
    )

    static let uiScreenshot = ToolDefinition(
        name: "ui_screenshot",
        description: """
            Ekran görüntüsü alır (SCScreenshotManager). Read-only — Plan modunda \
            kullanılabilir. Screen Recording izni gerekir. target: \
            "active_display" (default) | "all_displays" | "window" | "window_content". \
            window* seçilirse bundle_id zorunlu. "window_content" ile üst kenardan \
            titlebar_offset kadar (default 28pt) kesilir.
            Faz 4 Set-of-Mark (ADR-0031): `elements` dolu ise her element için \
            numaralı badge + outline çizilir; sonuç `marks` array'inde \
            { id, element, frame_in_image } olarak döner. Vision model "tıkla #5" \
            diyebilir; caller marks[4].element.identifier ile ui_click yapar.
            Sonuç: base64-encoded PNG + pixel boyutları + logical frame + marks.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "target": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("active_display"), .string("all_displays"),
                        .string("window"), .string("window_content"),
                    ]),
                    "description": .string("Ne yakalanacak (default active_display)."),
                ]),
                "bundle_id": .object([
                    "type": .string("string"),
                    "description": .string("target=window | window_content ise hedef uygulama bundle ID'si."),
                ]),
                "titlebar_offset": .object([
                    "type": .string("number"),
                    "description": .string("target=window_content için üst kenardan atılan logical point (default 28). Toolbar varsa 64-72 deneyin."),
                ]),
                "elements": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "description": .string("ui_query çıktısındaki bir UIElement objesi (role, title, frame, opaque_id, ...)."),
                    ]),
                    "description": .string("Faz 4 Set-of-Mark: bu element'ler PNG üzerinde numaralı badge + outline ile işaretlenir. Off-screen olanlar atlanır."),
                ]),
                "auto_discover": .object([
                    "type": .string("boolean"),
                    "description": .string("Faz 5 (v0.2.38): true ve `elements` boşsa AX tree'den interactive element'ler (button/link/textfield/checkbox) otomatik bulunur ve annotate edilir. Vision model için tek-shot 'tıklanabilir ne var?' özeti — önce ui_query yazmaktan kurtarır. Limit 30 element, timeout 2s."),
                ]),
                "som_options": .object([
                    "type": .string("object"),
                    "description": .string("Faz 5 (v0.2.38): SoM renderer override — palette, outline_width, badge_size, font_size, text_color, badge_placement. Boş bırakırsan default değerler (geri uyumlu eski davranış). badge_placement: 'top_left_inside' (default) | 'top_left_outside' | 'top_right_inside' | 'top_right_outside' | 'smart_corner'."),
                ]),
            ]),
        ]),
        handler: { params in
            var args: [String: JSONValue] = [:]
            if let target = params?["target"] { args["target"] = target }
            if let bid = params?["bundle_id"] { args["bundle_id"] = bid }
            if let off = params?["titlebar_offset"] { args["titlebar_offset"] = off }
            if let els = params?["elements"] { args["elements"] = els }
            if let auto = params?["auto_discover"] { args["auto_discover"] = auto }
            if let opts = params?["som_options"] { args["som_options"] = opts }
            return await callBridge(tool: "ui_screenshot", arguments: .object(args))
        }
    )

    /// `PIXEL_PLAN_MODE=1` env var set ise destructive tool'lar (ui_click/ui_type)
    /// hata döner. Read-only tool'lar (ui_query/ui_screenshot) hep çalışır.
    ///
    /// ADR-0017 (Plan Mode) için MCP tarafı enforcement. PixelMacApp Claude
    /// CLI'yi `--permission-mode plan` ile spawn ederken bu env var'ı da set
    /// eder; MCP server start'ında okunur, her tool çağrısında check edilir
    /// (process env runtime'da değişebilir — Faz 3'te static cache opsiyonu).
    static func planModeGuard(_ tool: String) -> JSONValue? {
        if ProcessInfo.processInfo.environment["PIXEL_PLAN_MODE"] == "1" {
            return ToolResultBuilder.error(
                "Plan modunda destructive tool çağrılamaz: \(tool). " +
                "Sadece ui_query / ui_screenshot kullan."
            )
        }
        return nil
    }

    /// BridgeClient.call() sarmalayıcı — başarı/başarısızlık MCP `content` shape'ine
    /// dönüştürür. PixelAgent.app çalışmıyorsa connect EACCES/ENOENT → error.
    ///
    /// Response.result string ise text content. Object ise JSON serialize edilip
    /// text içine konur (claude-cli istemcisinin parse etmesi için).
    private static func callBridge(tool: String, arguments: JSONValue) async -> JSONValue {
        do {
            let response = try await BridgeClient.call(tool: tool, arguments: arguments)
            let text = formatBridgeResult(response.result)
            if response.ok {
                return ToolResultBuilder.text(text)
            }
            // Hata durumunda: structured result varsa onu da göster, error mesajıyla birlikte.
            let errorPrefix = response.error ?? "Bilinmeyen bridge hatası"
            let body = text.isEmpty ? errorPrefix : "\(errorPrefix)\n\(text)"
            return ToolResultBuilder.error(body)
        } catch {
            return ToolResultBuilder.error((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }

    private static func formatBridgeResult(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        if let s = value.stringValue { return s }
        // Object/array — pretty-print JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }
}
