import Foundation
import PixelCore

/// Claude CLI'nın `--output-format stream-json --include-partial-messages`
/// çıktısının her satırını `StreamDelta`'ya çevirir. Tanımadığı / metin-dışı
/// event'leri (system status, rate_limit, message_start, vb.) `nil` döner —
/// bunlar yutulmalıdır.
public enum StreamJSONParser {
    public static func parse(_ line: String) -> StreamDelta? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return nil
        }

        switch type {
        case "stream_event":
            return parseStreamEvent(json)
        case "result":
            return .done
        default:
            return nil
        }
    }

    private static func parseStreamEvent(_ json: [String: Any]) -> StreamDelta? {
        guard let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String
        else {
            return nil
        }

        guard eventType == "content_block_delta",
              let delta = event["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String,
              deltaType == "text_delta",
              let text = delta["text"] as? String
        else {
            return nil
        }
        return .textChunk(text)
    }
}
