import Foundation

public enum BackendError: LocalizedError, Equatable {
    case cliNotFound(name: String)
    case processFailed(String)
    case exitNonZero(status: Int32, stderr: String)
    case decodeError(String)
    case noBackendAvailable

    public var errorDescription: String? {
        switch self {
        case .cliNotFound(let name):
            return "\(name) CLI bulunamadı (PATH'te veya bilinen yollarda yok)."
        case .processFailed(let message):
            return "Süreç başlatılamadı: \(message)"
        case .exitNonZero(let status, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "CLI çıkış kodu \(status)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
        case .decodeError(let message):
            return "CLI çıktısı decode edilemedi: \(message)"
        case .noBackendAvailable:
            return "Hiçbir CLI yüklü değil. En az birini yükleyin: claude, codex veya gemini."
        }
    }
}
