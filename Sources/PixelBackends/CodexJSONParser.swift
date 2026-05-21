import Foundation
import PixelCore

/// Codex CLI'nın `exec --json` çıktısının her satırını `StreamDelta`'ya çevirir.
/// Codex Claude'dan farklı olarak partial token delta vermez — `item.completed`
/// event'inde `item.type == "agent_message"` ise tam metin tek seferde gelir;
/// `turn.completed` event'i ile bitiş.
public enum CodexJSONParser {
    public static func parse(_ line: String) -> StreamDelta? {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return nil
        }

        switch type {
        case "item.completed":
            return parseItemCompleted(json)
        case "turn.completed":
            return .done
        default:
            return nil
        }
    }

    private static func parseItemCompleted(_ json: [String: Any]) -> StreamDelta? {
        guard let item = json["item"] as? [String: Any],
              let itemType = item["type"] as? String,
              itemType == "agent_message",
              let text = item["text"] as? String,
              !text.isEmpty
        else {
            return nil
        }
        return .textChunk(text)
    }
}
