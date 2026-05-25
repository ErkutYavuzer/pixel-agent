import Darwin
import Foundation
import PixelBackends
import PixelComputerUse
import PixelCore
import PixelMCPServer
import PixelSubagent
import PixelTools

/// `pixel-mcp-server`'ın bundle-bağımlı tool isteklerini dinleyen Unix
/// domain socket sunucusu.
///
/// Transport: newline-delimited JSON, BridgeRequest in / BridgeResponse out,
/// her bağlantı tek-atımlık (single-shot RPC).
///
/// Accept loop background `DispatchQueue` üzerinde döner; tool execution
/// MainActor'a hop edilir (DockBadge.set NSApp.dockTile gerektirir).
public actor ControlSocketServer {
    private let socketPath: String
    private var listenFD: Int32 = -1
    private var running = false
    private let acceptQueue = DispatchQueue(
        label: "dev.erkutyavuzer.pixel-agent.control-accept",
        qos: .utility
    )

    /// Birleşik subagent havuzu — UI ve MCP bridge buraya yönlendirilir. `nil` ise
    /// `dispatch_subagent` eski stateless yola düşer (her request fresh
    /// `CLIDetector` + `SubagentRunner`). Test target için backwards compat.
    private var manager: SubagentManager?

    /// Computer use facade — lazily oluşturulur (ADR-0026). Bridge handler'da
    /// `ui_*` çağrılarında kullanılır.
    private lazy var computer = PixelComputerUse()

    /// C12: Her execute() sonrası tetiklenir — ChatHost iOS dashboard'a
    /// duyuru yapar. `nil` ise no-op (test target / unwired durumlar).
    /// Closure parametreleri: toolName, status ("success" / "failure"),
    /// summary (response body veya hata mesajı).
    var onToolCalled: (@Sendable (String, String, String?) -> Void)?

    public init(socketPath: String = BridgePaths.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    /// `RootView` Manager hazır olduğunda çağırır. Idempotent — son `attach` kazanır.
    func attach(_ manager: SubagentManager) {
        self.manager = manager
    }

    /// C12: ChatHost wire-up'ı bunu kullanır.
    func attachToolCallListener(_ listener: @Sendable @escaping (String, String, String?) -> Void) {
        self.onToolCalled = listener
    }

    public func start() throws {
        guard !running else { return }

        // Eski socket dosyası kaldıysa sil (ECONNRESET / unlinked)
        try? FileManager.default.removeItem(atPath: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.socketCreateFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= BridgePaths.maxSocketPathLength else {
            close(fd)
            throw ControlError.pathTooLong(pathBytes.count)
        }
        Self.copyPathIntoSockaddr(&addr, path: pathBytes)

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw ControlError.bindFailed(socketPath, err)
        }

        guard listen(fd, 8) == 0 else {
            let err = errno
            close(fd)
            throw ControlError.listenFailed(err)
        }

        listenFD = fd
        running = true

        // Accept loop — background queue (blocking accept syscall)
        acceptQueue.async { [weak self] in
            while true {
                let clientFD = accept(fd, nil, nil)
                if clientFD < 0 {
                    // listenFD kapandığında accept EBADF döner — döngüden çık
                    return
                }
                guard let self else {
                    close(clientFD)
                    return
                }
                Task { await self.handleClient(fd: clientFD) }
            }
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - Connection handling

    private func handleClient(fd: Int32) async {
        defer { close(fd) }

        guard let requestBytes = Self.readLine(fd: fd) else { return }
        let response: BridgeResponse
        var toolName: String?
        do {
            let req = try JSONDecoder().decode(BridgeRequest.self, from: Data(requestBytes))
            toolName = req.tool
            response = await execute(request: req)
        } catch {
            response = .failure("İstek parse edilemedi: \(error.localizedDescription)")
        }
        _ = Self.writeLine(fd: fd, response: response)

        // C12: Tool call event'i ChatHost'a fire — iOS dashboard'a duyurmak için.
        if let tool = toolName, let listener = onToolCalled {
            let (status, summary) = Self.summarize(response)
            listener(tool, status, summary)
        }
    }

    /// C12: BridgeResponse'tan `(status, summary)` çiftini çıkarır.
    /// Success summary string-truncated (~100 char), failure error mesajı.
    /// `BridgeResponse` enum değil struct (ok/result/error); pattern match yok.
    private static func summarize(_ response: BridgeResponse) -> (status: String, summary: String?) {
        if response.ok {
            let raw = response.result.map(stringSummary(of:)) ?? "ok"
            let trimmed = raw.count > 100 ? String(raw.prefix(100)) + "…" : raw
            return ("success", trimmed)
        } else {
            return ("failure", response.error ?? "Bilinmeyen hata")
        }
    }

    private static func stringSummary(of value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array: return "ok (array)"
        case .object: return "ok (object)"
        }
    }

    private static func readLine(fd: Int32) -> [UInt8]? {
        var acc: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBufferPointer { ptr -> Int in
                read(fd, ptr.baseAddress, ptr.count)
            }
            if n <= 0 { return acc.isEmpty ? nil : acc }
            for i in 0..<n {
                if buf[i] == 0x0a {
                    acc.append(contentsOf: buf[0..<i])
                    return acc
                }
            }
            acc.append(contentsOf: buf[0..<n])
        }
    }

    private static func writeLine(fd: Int32, response: BridgeResponse) -> Bool {
        guard var data = try? JSONEncoder().encode(response) else { return false }
        data.append(0x0a)
        let written = data.withUnsafeBytes { buf -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return write(fd, base, buf.count)
        }
        return written == data.count
    }

    // MARK: - Tool dispatch

    private func execute(request: BridgeRequest) async -> BridgeResponse {
        switch request.tool {
        case "dock_badge_set":
            let label = request.arguments["label"]?.stringValue
            await MainActor.run { DockBadge.set(label) }
            return .success(.string(label.map { "Badge: \($0)" } ?? "Badge temizlendi"))

        case "notify":
            guard let title = request.arguments["title"]?.stringValue else {
                return .failure("`title` parametresi zorunlu.")
            }
            let body = request.arguments["body"]?.stringValue ?? ""
            await SystemNotifications.post(title: title, body: body)
            return .success(.string("Bildirim gönderildi: \(title)"))

        case "play_sound":
            guard let name = request.arguments["name"]?.stringValue else {
                return .failure("`name` parametresi zorunlu.")
            }
            await MainActor.run { SoundEffect.play(name) }
            return .success(.string("Ses çalındı: \(name)"))

        case "dispatch_subagent":
            return await dispatchSubagent(request.arguments)

        case "ui_query":
            return await uiQuery(request.arguments)

        case "ui_click":
            return await uiClick(request.arguments)

        case "ui_type":
            return await uiType(request.arguments)

        case "ui_screenshot":
            return await uiScreenshot(request.arguments)

        case "ui_resolve":
            return await uiResolve(request.arguments)

        default:
            return .failure("Bilinmeyen bridge tool: \(request.tool)")
        }
    }

    // MARK: - Computer use bridge handlers (ADR-0026)

    private func uiQuery(_ args: JSONValue) async -> BridgeResponse {
        guard let queryArg = args["query"] else {
            return .failure("`query` parametresi zorunlu.")
        }
        do {
            let query = try Self.decodeUIQuery(from: queryArg)
            let elements = try await computer.query(query)
            let payload = try Self.encodeJSON(elements)
            return .success(payload)
        } catch let error as ComputerUseError {
            return .failure(error.errorDescription ?? "\(error)")
        } catch {
            return .failure("ui_query: \(error.localizedDescription)")
        }
    }

    private func uiClick(_ args: JSONValue) async -> BridgeResponse {
        guard let queryArg = args["query"] else {
            return .failure("`query` parametresi zorunlu.")
        }
        let count: Int = {
            if case .int(let n) = args["count"], n > 0 { return n }
            return 1
        }()
        // **Faz 3b (ADR-0029):** modifiers JSON array of strings ("command",
        // "option", "shift", "control"; aliases & glyphs de kabul edilir).
        let modifiers: ModifierFlags = {
            guard case .array(let arr) = args["modifiers"] else { return [] }
            let names = arr.compactMap { $0.stringValue }
            return ModifierFlags.parse(names)
        }()
        do {
            let query = try Self.decodeUIQuery(from: queryArg)
            let element = try await computer.click(query, count: count, modifiers: modifiers)
            let payload = try Self.encodeJSON(element)
            return .success(payload)
        } catch let error as ComputerUseError {
            return .failure(error.errorDescription ?? "\(error)")
        } catch {
            return .failure("ui_click: \(error.localizedDescription)")
        }
    }

    private func uiType(_ args: JSONValue) async -> BridgeResponse {
        guard let text = args["text"]?.stringValue else {
            return .failure("`text` parametresi zorunlu.")
        }
        let intoQuery: UIQuery?
        if let intoArg = args["into"] {
            do {
                intoQuery = try Self.decodeUIQuery(from: intoArg)
            } catch {
                return .failure("`into` parse edilemedi: \(error.localizedDescription)")
            }
        } else {
            intoQuery = nil
        }
        do {
            try await computer.type(text, into: intoQuery)
            return .success(.string("Yazıldı (\(text.count) karakter)."))
        } catch let error as ComputerUseError {
            return .failure(error.errorDescription ?? "\(error)")
        } catch {
            return .failure("ui_type: \(error.localizedDescription)")
        }
    }

    /// **Faz 3a (ADR-0028):** opaqueID re-resolve. Element artık yoksa
    /// `{ "found": false }` döner; varsa element snapshot'ını payload olarak verir.
    private func uiResolve(_ args: JSONValue) async -> BridgeResponse {
        guard let oid = args["opaque_id"]?.stringValue else {
            return .failure("`opaque_id` parametresi zorunlu.")
        }
        do {
            if let element = try await computer.resolve(opaqueID: oid) {
                let payload = try Self.encodeJSON(element)
                return .success(payload)
            } else {
                return .success(.object(["found": .bool(false), "opaque_id": .string(oid)]))
            }
        } catch let error as ComputerUseError {
            return .failure(error.errorDescription ?? "\(error)")
        } catch {
            return .failure("ui_resolve: \(error.localizedDescription)")
        }
    }

    private func uiScreenshot(_ args: JSONValue) async -> BridgeResponse {
        let target: ScreenshotTarget
        switch args["target"]?.stringValue {
        case "window":
            guard let bid = args["bundle_id"]?.stringValue else {
                return .failure("target=window iken `bundle_id` zorunlu.")
            }
            target = .window(bundleID: bid)
        case "window_content":
            // **Faz 3c (ADR-0030):** titlebar kesilmiş pencere içeriği.
            guard let bid = args["bundle_id"]?.stringValue else {
                return .failure("target=window_content iken `bundle_id` zorunlu.")
            }
            let offset: Double = {
                switch args["titlebar_offset"] {
                case .double(let d): return d
                case .int(let n): return Double(n)
                default: return ScreenshotTarget.defaultTitlebarOffset
                }
            }()
            target = .windowContent(bundleID: bid, titlebarOffset: offset)
        case "all_displays":
            target = .allDisplays
        default:
            target = .activeDisplay
        }

        // **Faz 4 (ADR-0031):** Set-of-Mark — caller annotated capture istiyorsa
        // elements array'ini decode et.
        let annotateElements: [UIElement]
        if case .array(let arr) = args["elements"] {
            do {
                annotateElements = try arr.map { try Self.decodeUIElement(from: $0) }
            } catch {
                return .failure("elements decode başarısız: \(error.localizedDescription)")
            }
        } else {
            annotateElements = []
        }

        // **Faz 5 (v0.2.38):** auto_discover + som_options decode.
        let autoDiscover: Bool = {
            if case .bool(let b) = args["auto_discover"] { return b }
            return false
        }()

        let options: SoMOptions
        if let optsValue = args["som_options"] {
            do {
                options = try Self.decodeJSON(SoMOptions.self, from: optsValue)
            } catch {
                return .failure("som_options decode başarısız: \(error.localizedDescription)")
            }
        } else {
            options = .default
        }

        do {
            let result = try await computer.screenshot(
                of: target,
                annotating: annotateElements,
                autoDiscover: autoDiscover,
                options: options
            )
            // PNG'i base64 olarak göm — MCP image content shape'i Faz 2 (şu an text).
            let base64 = result.pngData.base64EncodedString()
            let marksPayload: JSONValue = .array(
                try result.marks.map { mark in
                    let elementJSON = try Self.encodeJSON(mark.element)
                    return .object([
                        "id": .string(mark.id),
                        "element": elementJSON,
                        "frame_in_image": .object([
                            "x": .double(mark.frameInImage.x),
                            "y": .double(mark.frameInImage.y),
                            "width": .double(mark.frameInImage.width),
                            "height": .double(mark.frameInImage.height),
                        ]),
                    ])
                }
            )
            let payload: JSONValue = .object([
                "format": .string("png"),
                "pixel_width": .int(result.pixelWidth),
                "pixel_height": .int(result.pixelHeight),
                "logical_frame": .object([
                    "x": .double(result.logicalFrame.x),
                    "y": .double(result.logicalFrame.y),
                    "width": .double(result.logicalFrame.width),
                    "height": .double(result.logicalFrame.height),
                ]),
                "bundle_id": result.bundleID.map { .string($0) } ?? .null,
                "png_base64": .string(base64),
                "marks": marksPayload,
            ])
            return .success(payload)
        } catch let error as ComputerUseError {
            return .failure(error.errorDescription ?? "\(error)")
        } catch {
            return .failure("ui_screenshot: \(error.localizedDescription)")
        }
    }

    // MARK: - JSON ↔ Codable bridge

    /// `JSONValue` → `Codable` decode (Foundation JSON üzerinden round-trip).
    private static func decodeUIQuery(from value: JSONValue) throws -> UIQuery {
        let data = try JSONEncoder().encode(value)
        // MCP JSON snake_case kullanıyor; Codable default match için CodingKeys
        // veya snake_case stratejisi gerekiyor. UIQuery alanları zaten camelCase
        // → convertFromSnakeCase strategy ile bundle_id → bundleID otomatik.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(UIQuery.self, from: data)
    }

    /// **Faz 4 (ADR-0031):** `JSONValue` → `UIElement` decode. ui_query çıktısı
    /// snake_case'de gelir (bundle_id, opaque_id, ...) — convertFromSnakeCase
    /// strategy ile bundleID/opaqueID alanlarına çevrilir.
    private static func decodeUIElement(from value: JSONValue) throws -> UIElement {
        try decodeJSON(UIElement.self, from: value)
    }

    /// **Faz 5 (v0.2.38):** Generic JSONValue → Codable decode. snake_case
    /// convention'a otomatik dönüşür (SoMOptions için `outline_width` →
    /// `outlineWidth` vb.).
    private static func decodeJSON<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// MCP üzerinden gelen `dispatch_subagent` çağrısı.
    ///
    /// - Manager attach edilmişse: havuza ekler (UI'da görünür) ve sonucu bekler.
    ///   Cap dolu / backend yok → `BridgeResponse.failure(...)`.
    /// - Manager nil ise (test edge case): eski stateless yol — her request fresh
    ///   `CLIDetector` + `SubagentRunner`. UI'a yansımaz.
    ///
    /// Bağlantı subagent süresince açık kalır (single-shot bridge bloklanır).
    private func dispatchSubagent(_ args: JSONValue) async -> BridgeResponse {
        guard let prompt = args["prompt"]?.stringValue, !prompt.isEmpty else {
            return .failure("`prompt` parametresi zorunlu.")
        }
        guard let backendName = args["backend"]?.stringValue,
              let kind = CLIKind(rawValue: backendName) else {
            return .failure("`backend` claude/codex/gemini olmalı.")
        }

        // Budget parametreleri (opsiyonel).
        let duration: TimeInterval = {
            switch args["max_duration_seconds"] {
            case .int(let n): return TimeInterval(n)
            case .double(let d): return d
            default: return Budget.default.maxDuration
            }
        }()
        let outputBytes: Int? = {
            if case .int(let n) = args["max_output_bytes"], n > 0 { return n }
            return nil
        }()
        let budget = Budget(maxDuration: max(1, duration), maxOutputBytes: outputBytes)

        // **Faz 4 (v0.2.39):** follow_ups varsa multi-turn yolu. Manager
        // attached olsa bile multi-turn UI entegrasyonu v0.3+'a kalıyor;
        // şimdilik stateless yolla (UI panel'inde görünmez ama bridge
        // response döner).
        if case .array(let followUpArr) = args["follow_ups"] {
            let followUps = followUpArr.compactMap { $0.stringValue }
            let allTurns = [prompt] + followUps
            return await dispatchMultiTurn(turns: allTurns, kind: kind, budget: budget)
        }

        // Manager attach edilmişse birleşik havuza yönlendir.
        if let manager = self.manager {
            let outcome = await manager.dispatchAndWait(prompt: prompt, backend: kind, budget: budget)
            switch outcome {
            case .success(let subResult):
                return Self.bridgeResponse(from: subResult, backendKind: kind)
            case .failure(let error):
                return .failure(error.errorDescription ?? "\(error)")
            }
        }

        // Stateless fallback — test target ve Manager-attached-değil durumlar için.
        let detector = CLIDetector()
        guard let executablePath = detector.locate(kind) else {
            return .failure("Backend bulunamadı: \(kind.executableName) (PATH veya bilinen lokasyonlarda yok).")
        }
        let backend = CLIBackend(kind: kind, executablePath: executablePath)
        let runner = SubagentRunner(backend: backend, budget: budget)
        let result = await runner.run(prompt: prompt)
        return Self.bridgeResponse(from: result, backendKind: kind)
    }

    /// **Faz 4 (v0.2.39):** Multi-turn subagent dispatch'i (follow_ups var).
    /// **Faz 5 (v0.2.41):** Manager attached ise UI panel'inde turn list
    /// görünür; yoksa eski stateless yolla (UI'a yansımaz).
    /// Her turn için per-turn output + outcome JSON'a serialize edilir.
    private func dispatchMultiTurn(turns: [String], kind: CLIKind, budget: Budget) async -> BridgeResponse {
        // Faz 5: Manager attached ise birleşik havuza yönlendir.
        if let manager = self.manager {
            let outcome = await manager.dispatchMultiTurnAndWait(
                turns: turns,
                backend: kind,
                budget: budget
            )
            switch outcome {
            case .success(let result):
                return Self.multiTurnBridgeResponse(from: result, backendKind: kind)
            case .failure(let error):
                return .failure(error.errorDescription ?? "\(error)")
            }
        }

        // Stateless fallback — Manager-attached-değil durumlar için (test).
        let detector = CLIDetector()
        guard let executablePath = detector.locate(kind) else {
            return .failure("Backend bulunamadı: \(kind.executableName) (PATH veya bilinen lokasyonlarda yok).")
        }
        let backend = CLIBackend(kind: kind, executablePath: executablePath)
        let runner = MultiTurnSubagentRunner(backend: backend, budget: budget)
        let result = await runner.runConversation(turns: turns)
        return Self.multiTurnBridgeResponse(from: result, backendKind: kind)
    }

    private static func multiTurnBridgeResponse(
        from result: MultiTurnSubagentResult,
        backendKind kind: CLIKind
    ) -> BridgeResponse {
        let status: String
        var errorPayload: String? = nil
        var failedTurnIndex: Int? = nil
        switch result {
        case .completedAllTurns:
            status = "completed_all_turns"
        case .budgetExceededAt(let idx, let reason, _, _):
            status = "budget_exceeded_at"
            failedTurnIndex = idx
            errorPayload = reason.rawValue
        case .cancelledAt(let idx, _, _):
            status = "cancelled_at"
            failedTurnIndex = idx
        case .failedAt(let idx, let err, _, _):
            status = "failed_at"
            failedTurnIndex = idx
            errorPayload = err
        }

        let turnsPayload: JSONValue = .array(result.completedTurns.map { turn in
            let outcomeStr: String
            var detail: String? = nil
            switch turn.outcome {
            case .completed: outcomeStr = "completed"
            case .budgetExceeded(let r): outcomeStr = "budget_exceeded"; detail = r.rawValue
            case .cancelled: outcomeStr = "cancelled"
            case .failed(let e): outcomeStr = "failed"; detail = e
            }
            var dict: [String: JSONValue] = [
                "output": .string(turn.output),
                "duration_seconds": .double(turn.durationSeconds),
                "outcome": .string(outcomeStr),
            ]
            if let detail { dict["detail"] = .string(detail) }
            return .object(dict)
        })

        var payload: [String: JSONValue] = [
            "status": .string(status),
            "backend": .string(kind.rawValue),
            "total_duration_seconds": .double(result.totalDurationSeconds),
            "turns": turnsPayload,
        ]
        if let idx = failedTurnIndex {
            payload["failed_turn_index"] = .int(idx)
        }
        if let err = errorPayload {
            payload["error"] = .string(err)
        }
        return .success(.object(payload))
    }

    /// `SubagentResult` → `BridgeResponse` çevirimi. Hem manager yolu hem stateless yol
    /// aynı format döndürür: `status`/`output`/`duration_seconds`/`backend` payload'ı +
    /// duruma uygun ok/error.
    private static func bridgeResponse(
        from result: SubagentResult,
        backendKind kind: CLIKind
    ) -> BridgeResponse {
        let payload: JSONValue = .object([
            "status": .string(statusName(of: result)),
            "output": .string(result.output),
            "duration_seconds": .double(result.durationSeconds),
            "backend": .string(kind.rawValue),
        ])

        switch result {
        case .completed:
            return .success(payload)
        case .budgetExceeded(let reason, _, _):
            return BridgeResponse(
                ok: false,
                result: payload,
                error: "Budget aşıldı (\(reason.rawValue))"
            )
        case .cancelled:
            return BridgeResponse(ok: false, result: payload, error: "Subagent iptal edildi")
        case .failed(let error, _, _):
            return BridgeResponse(ok: false, result: payload, error: error)
        }
    }

    private static func statusName(of result: SubagentResult) -> String {
        switch result {
        case .completed: return "completed"
        case .budgetExceeded: return "budget_exceeded"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }

    // MARK: - sockaddr_un helper

    private static func copyPathIntoSockaddr(
        _ addr: inout sockaddr_un,
        path: ContiguousArray<CChar>
    ) {
        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            let raw = UnsafeMutableRawPointer(tuplePtr)
            let dst = raw.assumingMemoryBound(to: CChar.self)
            path.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    dst.update(from: base, count: path.count)
                }
            }
        }
    }
}

public enum ControlError: Error, LocalizedError {
    case socketCreateFailed(Int32)
    case pathTooLong(Int)
    case bindFailed(String, Int32)
    case listenFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .socketCreateFailed(let e): return "Socket() başarısız, errno=\(e)"
        case .pathTooLong(let n): return "Socket path \(n) byte — max 104"
        case .bindFailed(let p, let e): return "bind() başarısız (\(p), errno=\(e))"
        case .listenFailed(let e): return "listen() başarısız, errno=\(e)"
        }
    }
}
