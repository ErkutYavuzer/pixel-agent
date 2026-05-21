import Foundation

public enum RelayError: LocalizedError, Equatable {
    case notConnected
    case invalidRelayURL
    case invalidPairingCode(String)
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Relay'e bağlı değil."
        case .invalidRelayURL:
            return "Geçersiz relay URL."
        case .invalidPairingCode(let code):
            return "Geçersiz pairing kodu: '\(code)' — format [A-Z0-9]{6} olmalı."
        case .encodingFailed(let message):
            return "Envelope encode hatası: \(message)"
        case .decodingFailed(let message):
            return "Envelope decode hatası: \(message)"
        }
    }
}
