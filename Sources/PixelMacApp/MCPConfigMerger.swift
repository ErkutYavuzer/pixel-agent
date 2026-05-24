import Foundation

/// Mac'te bir IDE'nin (Claude Desktop / Cursor / Codex CLI) MCP config
/// JSON dosyasını okuyup pixel-agent server entry'sini ekleyen/güncelleyen
/// saf yardımcı (Sprint 6 — MCP setup wizard).
///
/// Mevcut `IntegrationView` (Sprint 1 / C8) sadece kopya-yapıştır snippet'i
/// gösteriyordu. Bu helper diff'i hesaplar; UI tarafı Apply tıklayınca
/// üretilen merged JSON'u dosyaya yazar.
///
/// Saf — `FileManager` yok, sadece JSON parse + serialize. Test edilebilir.
enum MCPConfigMerger {

    /// Default MCP server adı.
    static let defaultServerName = "pixel-agent"

    /// Mevcut JSON içeriğine pixel-agent entry'sini ekle/güncelle.
    /// `existingJSON` nil veya boş ise sıfırdan minimal config üretir.
    /// Var olan başka entry'ler korunur (idempotent — başka MCP server'ları
    /// etkilenmez).
    ///
    /// Throws: `MCPConfigError` (parse hatası vb.).
    static func mergePixelAgent(
        binaryPath: String,
        intoExistingJSON existingJSON: String?,
        serverName: String = defaultServerName
    ) throws -> String {
        var root: [String: Any] = [:]
        if let json = existingJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
           !json.isEmpty {
            guard let data = json.data(using: .utf8) else {
                throw MCPConfigError.parseFailed("UTF-8 dönüşümü başarısız")
            }
            do {
                let parsed = try JSONSerialization.jsonObject(with: data, options: [])
                guard let dict = parsed as? [String: Any] else {
                    throw MCPConfigError.parseFailed("Root JSON object değil")
                }
                root = dict
            } catch let err as MCPConfigError {
                throw err
            } catch {
                throw MCPConfigError.parseFailed(error.localizedDescription)
            }
        }

        // Get-or-create mcpServers object
        var mcpServers = (root["mcpServers"] as? [String: Any]) ?? [:]

        // pixel-agent entry
        let serverEntry: [String: Any] = [
            "command": binaryPath,
            "args": [String](),
        ]
        mcpServers[serverName] = serverEntry
        root["mcpServers"] = mcpServers

        // Re-serialize pretty (kullanıcı diff'i okuyabilsin).
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPConfigError.serializeFailed("UTF-8 string'e dönüştürülemedi")
        }
        return string
    }

    /// Mevcut config'in pixel-agent için durumunu tanılar.
    /// UI bu enum'a göre badge ve buton metni gösterir.
    static func currentStatus(
        existingJSON: String?,
        binaryPath: String,
        serverName: String = defaultServerName
    ) -> MCPConfigStatus {
        guard let json = existingJSON?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = parsed as? [String: Any] else {
            return .notConfigured
        }
        guard let mcpServers = root["mcpServers"] as? [String: Any] else {
            return .notConfigured
        }
        guard let entry = mcpServers[serverName] as? [String: Any] else {
            return .notConfigured
        }
        let existingPath = entry["command"] as? String
        if existingPath == binaryPath {
            return .configuredCorrectly
        }
        return .configuredWithDifferentPath(currentPath: existingPath ?? "(belirsiz)")
    }
}

/// Mevcut MCP config'in pixel-agent için durumu — UI üç farklı badge gösterir.
enum MCPConfigStatus: Equatable, Sendable {
    /// Hiç pixel-agent entry'si yok veya config dosyası yok/boş.
    case notConfigured
    /// pixel-agent entry'si var ve `command` path doğru.
    case configuredCorrectly
    /// pixel-agent entry'si var ama farklı bir binary path'e işaret ediyor
    /// (eski sürüm veya yanlış kurulum). Apply tıklayınca güncellenir.
    case configuredWithDifferentPath(currentPath: String)

    /// UI label.
    var displayName: String {
        switch self {
        case .notConfigured: return "Kurulu değil"
        case .configuredCorrectly: return "Kurulu ✓"
        case .configuredWithDifferentPath: return "Eski sürüm var"
        }
    }

    /// SF Symbol.
    var systemImage: String {
        switch self {
        case .notConfigured: return "circle"
        case .configuredCorrectly: return "checkmark.circle.fill"
        case .configuredWithDifferentPath: return "exclamationmark.triangle.fill"
        }
    }

    /// Apply butonu disabled mı? (Doğru kuruluysa Re-apply gereksiz —
    /// kullanıcı yine de tetikleyebilsin diye false, ama label değişir.)
    var actionLabel: String {
        switch self {
        case .notConfigured: return "Kur"
        case .configuredCorrectly: return "Yeniden Uygula"
        case .configuredWithDifferentPath: return "Güncelle"
        }
    }
}

enum MCPConfigError: Error, LocalizedError, Equatable {
    case parseFailed(String)
    case serializeFailed(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed(let reason): return "Config JSON parse hatası: \(reason)"
        case .serializeFailed(let reason): return "Config serialize hatası: \(reason)"
        }
    }
}
