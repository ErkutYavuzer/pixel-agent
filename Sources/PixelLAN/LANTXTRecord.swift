import Foundation

/// Bonjour TXT record DNS-SD wire format encoder (RFC 6763 §6).
///
/// Her giriş `<length-byte><key=value-bytes>` formatında; uzunluğu 1-255 byte.
/// Boş key=value (0 byte) atlanır. >255 byte girişler atlanır (RFC 6763 §6.1).
/// Çıktı `NWListener.Service(txtRecord:)` parametresine doğrudan geçilebilir.
///
/// Deterministic ordering: anahtarlar alfabetik sıralanır — test edilebilirlik için.
public enum LANTXTRecord {
    /// `pk=<value>`, `v=<value>` gibi entry'leri DNS-SD wire format'a dönüştürür.
    public static func encode(_ entries: [String: String]) -> Data {
        var data = Data()
        for key in entries.keys.sorted() {
            guard let value = entries[key] else { continue }
            let bytes = "\(key)=\(value)".data(using: .utf8) ?? Data()
            guard !bytes.isEmpty, bytes.count <= 255 else { continue }
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        return data
    }

    /// Wire format Data'yı `[key: value]` sözlüğüne çevirir. Test ve debugging içindir;
    /// production'da `NWBrowser.Result.Metadata.bonjour(NWTXTRecord)` doğrudan kullanılır.
    public static func decode(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        var i = data.startIndex
        while i < data.endIndex {
            let len = Int(data[i])
            i = data.index(after: i)
            guard len > 0, i + len <= data.endIndex else { break }
            let entry = data[i..<(i + len)]
            i = i.advanced(by: len)
            guard let text = String(data: Data(entry), encoding: .utf8) else { continue }
            guard let eqIdx = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<eqIdx])
            let value = String(text[text.index(after: eqIdx)...])
            result[key] = value
        }
        return result
    }
}
