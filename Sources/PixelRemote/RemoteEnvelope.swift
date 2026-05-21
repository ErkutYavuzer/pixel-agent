import Foundation

public enum EnvelopeType: String, Codable, Sendable, CaseIterable {
    case hello
    case ready
    case ping
    case ack
    case error
    case userMessage
    case assistantMessage
}

public struct EnvelopePayload: Codable, Sendable, Equatable {
    public var text: String?
    public var role: String?
    public var messageID: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]?

    public init(
        text: String? = nil,
        role: String? = nil,
        messageID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.text = text
        self.role = role
        self.messageID = messageID
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
    }
}

public struct RemoteEnvelope: Codable, Sendable, Equatable {
    public let v: Int
    public let id: String
    public let ts: Int
    public let type: EnvelopeType
    public let payload: EnvelopePayload?
    public let sig: String?

    public init(
        v: Int = PixelRemote.protocolVersion,
        id: String = UUID().uuidString,
        ts: Int = Int(Date().timeIntervalSince1970),
        type: EnvelopeType,
        payload: EnvelopePayload? = nil,
        sig: String? = nil
    ) {
        self.v = v
        self.id = id
        self.ts = ts
        self.type = type
        self.payload = payload
        self.sig = sig
    }
}

extension RemoteEnvelope {
    public static func userMessage(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .userMessage,
            payload: EnvelopePayload(text: text, role: "user", messageID: messageID)
        )
    }

    public static func assistantMessage(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .assistantMessage,
            payload: EnvelopePayload(text: text, role: "assistant", messageID: messageID)
        )
    }

    public static func ping() -> RemoteEnvelope {
        RemoteEnvelope(type: .ping)
    }

    public static func ack(referenceID: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .ack, payload: EnvelopePayload(messageID: referenceID))
    }

    public static func error(code: String, message: String) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .error,
            payload: EnvelopePayload(errorCode: code, errorMessage: message)
        )
    }
}
