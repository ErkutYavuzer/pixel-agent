import Foundation

public enum AnthropicError: LocalizedError, Equatable {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case decodeError(String)
    case nonHTTPResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "ANTHROPIC_API_KEY ortam değişkeni tanımlı değil veya boş."
        case .httpError(let status, let body):
            return "Anthropic API HTTP \(status): \(body)"
        case .decodeError(let message):
            return "Anthropic SSE decode hatası: \(message)"
        case .nonHTTPResponse:
            return "Anthropic API'den HTTP olmayan yanıt geldi."
        }
    }
}
