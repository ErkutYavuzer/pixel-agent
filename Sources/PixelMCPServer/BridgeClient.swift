import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// PixelMacApp'a Unix socket üzerinden tek-atımlık (single-shot) RPC.
/// Her çağrı: connect → write request + `\n` → read until `\n` → close.
public enum BridgeClient {
    public enum BridgeError: Error, LocalizedError {
        case socketCreateFailed(Int32)
        case pathTooLong(Int)
        case connectFailed(String, Int32)
        case writeFailed
        case readFailed
        case decodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .socketCreateFailed(let errno):
                return "Unix socket oluşturulamadı (errno=\(errno))"
            case .pathTooLong(let n):
                return "Socket path çok uzun: \(n) > 104"
            case .connectFailed(let path, let errno):
                return "Bridge bağlanamadı (errno=\(errno)): \(path) — PixelAgent.app çalışıyor mu?"
            case .writeFailed:
                return "Socket yazma başarısız"
            case .readFailed:
                return "Socket okuma başarısız"
            case .decodeFailed(let msg):
                return "Bridge yanıtı parse edilemedi: \(msg)"
            }
        }
    }

    /// Tek-atımlık RPC. `socketPath` yoksa veya bridge cevap vermiyorsa hata fırlatır.
    public static func call(
        tool: String,
        arguments: JSONValue = .object([:]),
        socketPath: String = BridgePaths.defaultSocketPath()
    ) async throws -> BridgeResponse {
        #if canImport(Darwin)
        let request = BridgeRequest(tool: tool, arguments: arguments)
        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0a)  // newline-delimited

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.socketCreateFailed(errno) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= BridgePaths.maxSocketPathLength else {
            throw BridgeError.pathTooLong(pathBytes.count)
        }
        try Self.copyPathIntoSockaddr(&addr, path: pathBytes)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw BridgeError.connectFailed(socketPath, errno)
        }

        // Yaz
        let written = requestData.withUnsafeBytes { buf -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return write(fd, base, buf.count)
        }
        guard written == requestData.count else { throw BridgeError.writeFailed }

        // Oku (newline'a kadar veya EOF)
        var accumulated: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
                read(fd, ptr.baseAddress, ptr.count)
            }
            if n < 0 { throw BridgeError.readFailed }
            if n == 0 { break }
            for i in 0..<n {
                if chunk[i] == 0x0a {
                    accumulated.append(contentsOf: chunk[0..<i])
                    return try decode(accumulated)
                }
            }
            accumulated.append(contentsOf: chunk[0..<n])
        }
        return try decode(accumulated)
        #else
        throw BridgeError.connectFailed("Bridge sadece Darwin üzerinde", -1)
        #endif
    }

    private static func decode(_ bytes: [UInt8]) throws -> BridgeResponse {
        do {
            return try JSONDecoder().decode(BridgeResponse.self, from: Data(bytes))
        } catch {
            throw BridgeError.decodeFailed("\(error)")
        }
    }

    #if canImport(Darwin)
    /// `sockaddr_un.sun_path` 104-byte C tuple — Swift'te tipini kaybetmeden
    /// path bytelarını kopyalama helper'ı.
    private static func copyPathIntoSockaddr(
        _ addr: inout sockaddr_un,
        path: ContiguousArray<CChar>
    ) throws {
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
    #endif
}
