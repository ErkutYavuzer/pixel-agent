import Foundation
import PixelCore

public enum EnvelopeType: String, Sendable, CaseIterable {
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
    /// C12 (Sprint 3): Mac MCP bridge'inde bir tool çağrısı gerçekleştiğinde
    /// iOS dashboard'a duyuru. `EnvelopePayload.toolCallEvent` taşır.
    case toolCallEvent
    /// **Sprint 5 (iOS history viewer):** iOS → Mac, arşiv listesini iste.
    /// Payload boş.
    case archiveListRequest
    /// **Sprint 5:** Mac → iOS, arşiv listesi. `payload.archiveEntries` dolu.
    case archiveListResponse
    /// **Sprint 5:** iOS → Mac, belirli bir arşivi yükle. `payload.archiveLoadID`
    /// dolu (Mac tarafındaki URL string).
    case archiveLoadRequest
    /// **Sprint 5:** Mac → iOS, arşiv mesajları. `payload.archiveMessages` dolu.
    case archiveLoadResponse
    /// **Sprint 4 (forward-compat):** Bilinmeyen wire string'leri buraya
    /// düşer. Eski client'lar yeni envelope tiplerini decode hatası vermek
    /// yerine sessizce yutar; handler'lar `default: break` ile geçer.
    /// `allCases` bu sentinel'i de içerir ama production'da encode edilmez —
    /// yalnızca decode fallback'i.
    case unknown
}

/// **Sprint 5:** iOS history viewer için arşiv listesi envelope payload'u.
/// `ArchivedConversationEntry`'nin wire-suitable versiyonu — URL yerine
/// String, Date yerine Unix epoch.
public struct ArchiveEntryPayload: Codable, Sendable, Equatable, Identifiable {
    /// Mac tarafındaki URL string (file:// URL) — `archiveLoadRequest`'te
    /// kullanılır.
    public let id: String
    /// Backend kind raw value (`"claude"`, `"codex"`, `"gemini"`).
    public let backendKind: String
    /// Arşivleme zamanı — Unix epoch saniye.
    public let archivedAt: Double
    /// Dosyadaki mesaj sayısı.
    public let messageCount: Int
    /// İlk user mesajının kısa preview'ı (60 char). nil olabilir.
    public let firstUserSnippet: String?
    /// Sprint 6 (B2): Mac'te kullanıcı verirse sidecar'dan; yoksa nil.
    /// iOS UI önce bunu, sonra `firstUserSnippet`'ı kullanır. Eski client'lar
    /// bu field'ı yok sayar (Codable opsiyonel — additive).
    public let customTitle: String?

    public init(
        id: String,
        backendKind: String,
        archivedAt: Double,
        messageCount: Int,
        firstUserSnippet: String?,
        customTitle: String? = nil
    ) {
        self.id = id
        self.backendKind = backendKind
        self.archivedAt = archivedAt
        self.messageCount = messageCount
        self.firstUserSnippet = firstUserSnippet
        self.customTitle = customTitle
    }
}

extension EnvelopeType: Codable {
    /// Bilinmeyen `rawValue` → `.unknown` (strict throw yerine). Mevcut
    /// known case'ler için davranış aynı (RawRepresentable Codable default'u).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = EnvelopeType(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Mac'te MCP bridge üzerinden gerçekleşen bir tool call'un kısa özeti (C12).
///
/// iOS dashboard "Mac şu an X tool'unu çalıştırıyor / çalıştırdı" feed'i
/// için kullanır. Saf-data, Codable, Sendable.
public struct ToolCallEventPayload: Codable, Sendable, Equatable, Identifiable {
    /// Stable UUID — `Identifiable` için, iOS list'inde re-render hint.
    public let id: String
    /// Bridge tool adı — `dispatch_subagent`, `ui_screenshot`, `notify`, vb.
    public let toolName: String
    /// `"success"` veya `"failure"` — bridge response sonucundan üretilir.
    public let status: String
    /// Opsiyonel kısa açıklama: hata mesajı veya success summary.
    public let summary: String?
    /// Tetiklenme zamanı — Unix epoch saniye.
    public let timestamp: Double

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        status: String,
        summary: String? = nil,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.timestamp = timestamp
    }
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

    /// C12 (Sprint 3): Tool call event payload — `.toolCallEvent` type'ında dolu.
    public var toolCallEvent: ToolCallEventPayload?

    // Sprint 5 (iOS history viewer): archive flow payload fields.
    /// `.archiveListResponse` type için arşiv listesi.
    public var archiveEntries: [ArchiveEntryPayload]?
    /// `.archiveLoadRequest` type için yüklenecek arşivin id'si (Mac URL string).
    public var archiveLoadID: String?
    /// `.archiveLoadResponse` type için yüklenmiş arşiv mesajları.
    public var archiveMessages: [Message]?

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
        systemMetrics: SystemMetricsPayload? = nil,
        toolCallEvent: ToolCallEventPayload? = nil,
        archiveEntries: [ArchiveEntryPayload]? = nil,
        archiveLoadID: String? = nil,
        archiveMessages: [Message]? = nil
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
        self.toolCallEvent = toolCallEvent
        self.archiveEntries = archiveEntries
        self.archiveLoadID = archiveLoadID
        self.archiveMessages = archiveMessages
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

    /// C12: Mac MCP bridge'inde bir tool call tamamlandığında iOS dashboard'a
    /// duyurmak için.
    public static func toolCallEvent(
        toolName: String,
        status: String,
        summary: String? = nil
    ) -> RemoteEnvelope {
        let event = ToolCallEventPayload(
            toolName: toolName,
            status: status,
            summary: summary
        )
        return RemoteEnvelope(
            type: .toolCallEvent,
            payload: EnvelopePayload(toolCallEvent: event)
        )
    }

    // MARK: - Sprint 5 (iOS history viewer) archive flow

    /// iOS → Mac: arşiv listesini iste. Payload null (boş).
    public static func archiveListRequest() -> RemoteEnvelope {
        RemoteEnvelope(type: .archiveListRequest)
    }

    /// Mac → iOS: arşiv listesi cevabı.
    public static func archiveListResponse(entries: [ArchiveEntryPayload]) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .archiveListResponse,
            payload: EnvelopePayload(archiveEntries: entries)
        )
    }

    /// iOS → Mac: belirli arşivi yükle.
    public static func archiveLoadRequest(id: String) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .archiveLoadRequest,
            payload: EnvelopePayload(archiveLoadID: id)
        )
    }

    /// Mac → iOS: yüklenmiş arşivin mesajları.
    public static func archiveLoadResponse(messages: [Message]) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .archiveLoadResponse,
            payload: EnvelopePayload(archiveMessages: messages)
        )
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
