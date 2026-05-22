import Foundation
import PixelRemote

/// LAN transport'u newline-delimited JSON kullanır — bridge (`PixelMCPServer`)
/// ve relay (Cloudflare Worker) ile tutarlı framing. Her envelope tek satır JSON.
public enum LANFraming {
    public enum FramingError: Error, LocalizedError {
        case encodeFailed(String)
        case decodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .encodeFailed(let s): return "Envelope encode hatası: \(s)"
            case .decodeFailed(let s): return "Envelope decode hatası: \(s)"
            }
        }
    }

    /// Envelope → newline-terminated JSON bytes. Wire format: `<json>\n`.
    public static func encode(_ envelope: RemoteEnvelope) throws -> Data {
        do {
            var data = try JSONEncoder().encode(envelope)
            data.append(0x0a)
            return data
        } catch {
            throw FramingError.encodeFailed(error.localizedDescription)
        }
    }

    /// `\n` ayrılmış buffer → her satırın decode edilmiş envelope listesi.
    /// Son `\n` görmemiş (eksik) satır `leftover` olarak döner (sonraki recv'de devam etmek için).
    public static func decode(buffer: Data) throws -> (envelopes: [RemoteEnvelope], leftover: Data) {
        var envelopes: [RemoteEnvelope] = []
        var cursor = 0
        var leftover = Data()
        let bytes = [UInt8](buffer)

        var lineStart = 0
        for i in 0..<bytes.count {
            if bytes[i] == 0x0a {
                let line = Data(bytes[lineStart..<i])
                if !line.isEmpty {
                    do {
                        let env = try JSONDecoder().decode(RemoteEnvelope.self, from: line)
                        envelopes.append(env)
                    } catch {
                        throw FramingError.decodeFailed(error.localizedDescription)
                    }
                }
                lineStart = i + 1
                cursor = lineStart
            }
        }
        if cursor < bytes.count {
            leftover = Data(bytes[cursor..<bytes.count])
        }
        return (envelopes, leftover)
    }
}
