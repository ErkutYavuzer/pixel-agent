import Foundation
import PixelCore

public enum SSEParser {
    public static func parseDataLine(_ line: String) -> StreamDelta? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return nil
        }

        switch type {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String,
               deltaType == "text_delta",
               let text = delta["text"] as? String {
                return .textChunk(text)
            }
            return nil
        case "message_stop":
            return .done
        default:
            return nil
        }
    }
}
