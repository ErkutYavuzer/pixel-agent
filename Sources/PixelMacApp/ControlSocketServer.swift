import Darwin
import Foundation
import PixelBackends
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

    public init(socketPath: String = BridgePaths.defaultSocketPath()) {
        self.socketPath = socketPath
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
        let path = socketPath
        acceptQueue.async {
            while true {
                let clientFD = accept(fd, nil, nil)
                if clientFD < 0 {
                    // listenFD kapandığında accept EBADF döner — döngüden çık
                    return
                }
                Task { await Self.handleClient(fd: clientFD, socketPath: path) }
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

    private static func handleClient(fd: Int32, socketPath: String) async {
        defer { close(fd) }

        guard let requestBytes = readLine(fd: fd) else { return }
        let response: BridgeResponse
        do {
            let req = try JSONDecoder().decode(BridgeRequest.self, from: Data(requestBytes))
            response = await execute(request: req)
        } catch {
            response = .failure("İstek parse edilemedi: \(error.localizedDescription)")
        }
        _ = writeLine(fd: fd, response: response)
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

    private static func execute(request: BridgeRequest) async -> BridgeResponse {
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

        default:
            return .failure("Bilinmeyen bridge tool: \(request.tool)")
        }
    }

    /// MCP üzerinden gelen `dispatch_subagent` çağrısı: backend resolve + SubagentRunner.run +
    /// sonuç. Bağlantı subagent süresi boyunca açık tutulur (single-shot bridge bloklanır).
    /// MCP client (claude-cli vs.) kendi timeout'u ile sınırlı; budget bu pencereye sığmalı.
    private static func dispatchSubagent(_ args: JSONValue) async -> BridgeResponse {
        guard let prompt = args["prompt"]?.stringValue, !prompt.isEmpty else {
            return .failure("`prompt` parametresi zorunlu.")
        }
        guard let backendName = args["backend"]?.stringValue,
              let kind = CLIKind(rawValue: backendName) else {
            return .failure("`backend` claude/codex/gemini olmalı.")
        }

        // Her request'te fresh detect — kullanıcı CLI'larını ekleyebilir/güncelleyebilir.
        let detector = CLIDetector()
        guard let executablePath = detector.locate(kind) else {
            return .failure("Backend bulunamadı: \(kind.executableName) (PATH veya bilinen lokasyonlarda yok).")
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

        let backend = CLIBackend(kind: kind, executablePath: executablePath)
        let runner = SubagentRunner(backend: backend, budget: budget)
        let result = await runner.run(prompt: prompt)

        let payload: JSONValue = .object([
            "status": .string(Self.statusName(of: result)),
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
