import Foundation

public enum EnvelopeType: String, Codable, Sendable, CaseIterable {
    case hello
    case ready
    case ping
    case ack
    case error
    case userMessage
    case assistantMessage
    case assistantChunk
    case clientConfig
    case clientAction
    case hostStatus
    case screenshotPayload
}

public struct SubagentStatusPayload: Codable, Sendable, Equatable {
    public let id: String
    public let prompt: String
    public let status: String
    public let partialOutput: String
    public let startedAt: Double

    public init(id: String, prompt: String, status: String, partialOutput: String, startedAt: Double) {
        self.id = id
        self.prompt = prompt
        self.status = status
        self.partialOutput = partialOutput
        self.startedAt = startedAt
    }
}

public struct SystemMetricsPayload: Codable, Sendable, Equatable {
    public let cpuUsage: Double
    public let ramUsage: Double
    public let activeWindow: String

    public init(cpuUsage: Double, ramUsage: Double, activeWindow: String) {
        self.cpuUsage = cpuUsage
        self.ramUsage = ramUsage
        self.activeWindow = activeWindow
    }
}

public struct EnvelopePayload: Codable, Sendable, Equatable {
    public var text: String?
    public var role: String?
    public var messageID: String?
    public var errorCode: String?
    public var errorMessage: String?
    public var metadata: [String: String]?
    /// Hello envelope'unda gönderici tarafın ed25519 public key'i (base64).
    public var publicKey: String?

    // Configuration / Action payload fields
    public var selectedBackend: String?
    public var selectedModel: String?
    public var planMode: Bool?
    public var actionType: String?
    public var targetID: String?
    public var base64Image: String?

    // Status metrics/subagent payloads
    public var availableBackends: [String]?
    public var availableModels: [String: [String]]?
    public var activeSubagents: [SubagentStatusPayload]?
    public var systemMetrics: SystemMetricsPayload?

    public init(
        text: String? = nil,
        role: String? = nil,
        messageID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        metadata: [String: String]? = nil,
        publicKey: String? = nil,
        selectedBackend: String? = nil,
        selectedModel: String? = nil,
        planMode: Bool? = nil,
        actionType: String? = nil,
        targetID: String? = nil,
        base64Image: String? = nil,
        availableBackends: [String]? = nil,
        availableModels: [String: [String]]? = nil,
        activeSubagents: [SubagentStatusPayload]? = nil,
        systemMetrics: SystemMetricsPayload? = nil
    ) {
        self.text = text
        self.role = role
        self.messageID = messageID
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.metadata = metadata
        self.publicKey = publicKey
        self.selectedBackend = selectedBackend
        self.selectedModel = selectedModel
        self.planMode = planMode
        self.actionType = actionType
        self.targetID = targetID
        self.base64Image = base64Image
        self.availableBackends = availableBackends
        self.availableModels = availableModels
        self.activeSubagents = activeSubagents
        self.systemMetrics = systemMetrics
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

    public static func assistantChunk(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .assistantChunk,
            payload: EnvelopePayload(text: text, role: "assistant", messageID: messageID)
        )
    }

    public static func ping() -> RemoteEnvelope {
        RemoteEnvelope(type: .ping)
    }

    /// Handshake'in ilk envelope'u: gönderen tarafın public key'ini taşır.
    public static func hello(publicKey: String) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .hello,
            payload: EnvelopePayload(publicKey: publicKey)
        )
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

    public static func clientConfig(backend: String, model: String, planMode: Bool) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .clientConfig,
            payload: EnvelopePayload(selectedBackend: backend, selectedModel: model, planMode: planMode)
        )
    }

    public static func clientAction(type actionType: String, targetID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .clientAction,
            payload: EnvelopePayload(actionType: actionType, targetID: targetID)
        )
    }

    public static func hostStatus(
        selectedBackend: String,
        selectedModel: String,
        planMode: Bool,
        availableBackends: [String],
        availableModels: [String: [String]],
        activeSubagents: [SubagentStatusPayload],
        systemMetrics: SystemMetricsPayload
    ) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .hostStatus,
            payload: EnvelopePayload(
                selectedBackend: selectedBackend,
                selectedModel: selectedModel,
                planMode: planMode,
                availableBackends: availableBackends,
                availableModels: availableModels,
                activeSubagents: activeSubagents,
                systemMetrics: systemMetrics
            )
        )
    }

    public static func screenshotPayload(base64Image: String) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .screenshotPayload,
            payload: EnvelopePayload(base64Image: base64Image)
        )
    }
}

extension EnvelopePayload {
    public static func == (lhs: EnvelopePayload, rhs: EnvelopePayload) -> Bool {
        return lhs.text == rhs.text &&
               lhs.role == rhs.role &&
               lhs.messageID == rhs.messageID &&
               lhs.errorCode == rhs.errorCode &&
               lhs.errorMessage == rhs.errorMessage &&
               lhs.metadata == rhs.metadata &&
               lhs.publicKey == rhs.publicKey &&
               lhs.selectedBackend == rhs.selectedBackend &&
               lhs.selectedModel == rhs.selectedModel &&
               lhs.planMode == rhs.planMode &&
               lhs.actionType == rhs.actionType &&
               lhs.targetID == rhs.targetID &&
               lhs.base64Image == rhs.base64Image &&
               lhs.availableBackends == rhs.availableBackends &&
               lhs.availableModels == rhs.availableModels &&
               lhs.activeSubagents == rhs.activeSubagents &&
               lhs.systemMetrics == rhs.systemMetrics
    }
}

extension RemoteEnvelope {
    public static func == (lhs: RemoteEnvelope, rhs: RemoteEnvelope) -> Bool {
        guard lhs.v == rhs.v,
              lhs.id == rhs.id,
              lhs.ts == rhs.ts,
              lhs.type == rhs.type,
              lhs.sig == rhs.sig
        else {
            return false
        }
        return lhs.payload == rhs.payload
    }
}
