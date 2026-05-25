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
    /// iOS dashboard'a duyuru.
    case toolCallEvent
    /// **Sprint 5 (iOS history viewer):** iOS → Mac, arşiv listesini iste.
    /// Payload boş.
    case archiveListRequest
    /// **Sprint 5:** Mac → iOS, arşiv listesi.
    case archiveListResponse
    /// **Sprint 5:** iOS → Mac, belirli bir arşivi yükle.
    case archiveLoadRequest
    /// **Sprint 5:** Mac → iOS, arşiv mesajları.
    case archiveLoadResponse
    /// **Sprint 10 (v0.2.35):** iOS → Mac, bir arşivi yeniden adlandır.
    /// `newTitle` nil → custom title kaldırılır (snippet fallback'e döner).
    case archiveRename
    /// **Sprint 10 (v0.2.35):** iOS → Mac, bir arşivin tag listesini ayarla.
    /// `tags` nil veya boş → tüm tag'ler kaldırılır.
    case archiveSetTags
    /// **Sprint 4 (forward-compat):** Bilinmeyen wire string'leri buraya
    /// düşer. Eski client'lar yeni envelope tiplerini decode hatası vermek
    /// yerine sessizce yutar; handler'lar `default: break` ile geçer.
    /// `allCases` bu sentinel'i de içerir ama production'da encode edilmez —
    /// yalnızca decode fallback'i.
    case unknown
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

// MARK: - Sub-structs

/// **Sprint 5:** iOS history viewer için arşiv listesi envelope payload'u.
/// `ArchivedConversationEntry`'nin wire-suitable versiyonu — URL yerine
/// String, Date yerine Unix epoch.
public struct ArchiveEntryPayload: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let backendKind: String
    public let archivedAt: Double
    public let messageCount: Int
    public let firstUserSnippet: String?
    public let customTitle: String?
    public let tags: [String]?

    public init(
        id: String,
        backendKind: String,
        archivedAt: Double,
        messageCount: Int,
        firstUserSnippet: String?,
        customTitle: String? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.backendKind = backendKind
        self.archivedAt = archivedAt
        self.messageCount = messageCount
        self.firstUserSnippet = firstUserSnippet
        self.customTitle = customTitle
        self.tags = tags
    }
}

/// Mac'te MCP bridge üzerinden gerçekleşen bir tool call'un kısa özeti (C12).
public struct ToolCallEventPayload: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let toolName: String
    public let status: String
    public let summary: String?
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

/// `EnvelopeType.hostStatus` için aggregator content.
public struct HostStatusContent: Sendable, Equatable {
    public let selectedBackend: String
    public let selectedModel: String
    public let planMode: Bool
    public let availableBackends: [String]
    public let availableModels: [String: [String]]
    public let activeSubagents: [SubagentStatusPayload]
    public let systemMetrics: SystemMetricsPayload

    public init(
        selectedBackend: String,
        selectedModel: String,
        planMode: Bool,
        availableBackends: [String],
        availableModels: [String: [String]],
        activeSubagents: [SubagentStatusPayload],
        systemMetrics: SystemMetricsPayload
    ) {
        self.selectedBackend = selectedBackend
        self.selectedModel = selectedModel
        self.planMode = planMode
        self.availableBackends = availableBackends
        self.availableModels = availableModels
        self.activeSubagents = activeSubagents
        self.systemMetrics = systemMetrics
    }
}

// MARK: - EnvelopePayload (sum type)

/// **Sprint 8 (v0.2.33):** v0.2.32'ye kadar 20 opsiyonel field'lı flat struct'tı;
/// hangi field'ın hangi type'a ait olduğu konvansiyondu, derleyici garanti vermezdi.
/// Şimdi `EnvelopeType` ile 1:1 sum type — type checker hangi case'in hangi
/// veri taşıdığını bilir.
///
/// **Wire format değişmedi.** `RemoteEnvelope` custom Codable kullanır; payload'u
/// type-aware (RemoteEnvelope.type'a göre) build/serialize eder. Eski iOS/Mac
/// sürümleri yeni Mac/iOS ile uyumlu kalır.
///
/// **Backward-compat:** Önceki `payload?.text`, `payload?.actionType` vb.
/// access patternleri `extension` içindeki computed getter'lar ile çalışmaya
/// devam eder; caller migration zorunlu değildir.
///
/// Empty payload type'lar (`ping`, `ready`, `archiveListRequest`) için
/// `RemoteEnvelope.payload` `nil` olur — bu enum'da `empty` case'i yok.
public enum EnvelopePayload: Sendable, Equatable {
    case hello(publicKey: String)
    case error(code: String, message: String)
    case ack(referenceID: String)
    case userMessage(text: String, messageID: String?)
    case assistantMessage(text: String, messageID: String?)
    case assistantChunk(text: String, messageID: String?)
    case clientConfig(backend: String, model: String, planMode: Bool)
    case clientAction(actionType: String, targetID: String?)
    case hostStatus(HostStatusContent)
    case screenshotPayload(base64Image: String)
    case toolCallEvent(ToolCallEventPayload)
    case archiveListResponse(entries: [ArchiveEntryPayload])
    case archiveLoadRequest(archiveID: String)
    case archiveLoadResponse(messages: [Message])
    /// Sprint 10 (v0.2.35): iOS → Mac mutation. `newTitle` nil → kaldır.
    case archiveRename(archiveID: String, newTitle: String?)
    /// Sprint 10 (v0.2.35): iOS → Mac mutation. `tags` nil → tüm tag'leri kaldır.
    case archiveSetTags(archiveID: String, tags: [String]?)
}

// MARK: - Backward-compat field getters
//
// v0.2.32 ve önceki sürümlerde EnvelopePayload struct'tı; `payload?.text`,
// `payload?.actionType` gibi access pattern'leri yaygındı. Sum type'a geçince
// caller'ları kırmamak için her bir eski field için computed getter sağlanır.
// İlgili case'de dolu, diğerlerinde nil döner.
extension EnvelopePayload {
    public var text: String? {
        switch self {
        case .userMessage(let t, _), .assistantMessage(let t, _), .assistantChunk(let t, _):
            return t
        default: return nil
        }
    }

    public var role: String? {
        switch self {
        case .userMessage: return "user"
        case .assistantMessage, .assistantChunk: return "assistant"
        default: return nil
        }
    }

    public var messageID: String? {
        switch self {
        case .ack(let id): return id
        case .userMessage(_, let id), .assistantMessage(_, let id), .assistantChunk(_, let id):
            return id
        default: return nil
        }
    }

    public var errorCode: String? {
        if case .error(let code, _) = self { return code }
        return nil
    }

    public var errorMessage: String? {
        if case .error(_, let msg) = self { return msg }
        return nil
    }

    public var publicKey: String? {
        if case .hello(let pk) = self { return pk }
        return nil
    }

    public var selectedBackend: String? {
        switch self {
        case .clientConfig(let b, _, _): return b
        case .hostStatus(let c): return c.selectedBackend
        default: return nil
        }
    }

    public var selectedModel: String? {
        switch self {
        case .clientConfig(_, let m, _): return m
        case .hostStatus(let c): return c.selectedModel
        default: return nil
        }
    }

    public var planMode: Bool? {
        switch self {
        case .clientConfig(_, _, let p): return p
        case .hostStatus(let c): return c.planMode
        default: return nil
        }
    }

    public var actionType: String? {
        if case .clientAction(let t, _) = self { return t }
        return nil
    }

    public var targetID: String? {
        if case .clientAction(_, let id) = self { return id }
        return nil
    }

    public var base64Image: String? {
        if case .screenshotPayload(let img) = self { return img }
        return nil
    }

    public var availableBackends: [String]? {
        if case .hostStatus(let c) = self { return c.availableBackends }
        return nil
    }

    public var availableModels: [String: [String]]? {
        if case .hostStatus(let c) = self { return c.availableModels }
        return nil
    }

    public var activeSubagents: [SubagentStatusPayload]? {
        if case .hostStatus(let c) = self { return c.activeSubagents }
        return nil
    }

    public var systemMetrics: SystemMetricsPayload? {
        if case .hostStatus(let c) = self { return c.systemMetrics }
        return nil
    }

    public var toolCallEvent: ToolCallEventPayload? {
        if case .toolCallEvent(let e) = self { return e }
        return nil
    }

    public var archiveEntries: [ArchiveEntryPayload]? {
        if case .archiveListResponse(let entries) = self { return entries }
        return nil
    }

    public var archiveLoadID: String? {
        if case .archiveLoadRequest(let id) = self { return id }
        return nil
    }

    public var archiveMessages: [Message]? {
        if case .archiveLoadResponse(let messages) = self { return messages }
        return nil
    }

    /// Sprint 10: `archiveRename` / `archiveSetTags` ortak `archiveID` getter.
    public var mutationArchiveID: String? {
        switch self {
        case .archiveRename(let id, _): return id
        case .archiveSetTags(let id, _): return id
        default: return nil
        }
    }

    /// Sprint 10: `archiveRename` payload'unda yeni başlık (nil → sıfırla).
    public var renameNewTitle: String? {
        if case .archiveRename(_, let title) = self { return title }
        return nil
    }

    /// Sprint 10: `archiveSetTags` payload'unda yeni tag listesi (nil → sıfırla).
    public var editedTags: [String]? {
        if case .archiveSetTags(_, let tags) = self { return tags }
        return nil
    }
}

// MARK: - Wire format (flat dict, eski formatla uyumlu)

/// Wire'da kullanılan tüm field'lar. `RemoteEnvelope` custom Codable bu
/// key set'ini kullanır. Eski `EnvelopePayload` struct'ın field'larıyla
/// birebir aynı (backward-compat zorunlu).
private enum PayloadKey: String, CodingKey {
    case text, role, messageID
    case errorCode, errorMessage
    case publicKey
    case selectedBackend, selectedModel, planMode
    case actionType, targetID
    case base64Image
    case availableBackends, availableModels, activeSubagents, systemMetrics
    case toolCallEvent
    case archiveEntries, archiveLoadID, archiveMessages
    // Sprint 10 (v0.2.35): iOS → Mac mutation envelope'ları.
    case mutationArchiveID, renameNewTitle, editedTags
    /// `renameNewTitle` nil olarak gönderilmek istendiğinde explicit sentinel
    /// (decoder JSON `null`'ı opsiyonel field yokluğu olarak okuyamıyor;
    /// "field var ama null" ile "field hiç yok" ayrımı encoder side'da
    /// hep field encode edip null değer atayarak yapılmalı). Bu key true
    /// → kullanıcı bilerek "title kaldır" diyor demektir.
    case renameClearsTitle
}

extension EnvelopePayload {
    /// Type-aware decode: `RemoteEnvelope.init(from:)` önce `type`'ı çeker,
    /// sonra bunu çağırır. Eski wire format flat dict'ten ilgili case'i
    /// build eder. Eksik field'lar boş default'a düşer.
    fileprivate static func decode(from decoder: Decoder, type: EnvelopeType) throws -> EnvelopePayload? {
        let c = try decoder.container(keyedBy: PayloadKey.self)

        switch type {
        case .hello:
            let pk = try c.decodeIfPresent(String.self, forKey: .publicKey)
            return .hello(publicKey: pk ?? "")

        case .error:
            let code = try c.decodeIfPresent(String.self, forKey: .errorCode) ?? ""
            let msg = try c.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
            return .error(code: code, message: msg)

        case .ack:
            let id = try c.decodeIfPresent(String.self, forKey: .messageID) ?? ""
            return .ack(referenceID: id)

        case .userMessage:
            let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            let id = try c.decodeIfPresent(String.self, forKey: .messageID)
            return .userMessage(text: text, messageID: id)

        case .assistantMessage:
            let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            let id = try c.decodeIfPresent(String.self, forKey: .messageID)
            return .assistantMessage(text: text, messageID: id)

        case .assistantChunk:
            let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            let id = try c.decodeIfPresent(String.self, forKey: .messageID)
            return .assistantChunk(text: text, messageID: id)

        case .clientConfig:
            let backend = try c.decodeIfPresent(String.self, forKey: .selectedBackend) ?? ""
            let model = try c.decodeIfPresent(String.self, forKey: .selectedModel) ?? ""
            let plan = try c.decodeIfPresent(Bool.self, forKey: .planMode) ?? false
            return .clientConfig(backend: backend, model: model, planMode: plan)

        case .clientAction:
            let action = try c.decodeIfPresent(String.self, forKey: .actionType) ?? ""
            let targetID = try c.decodeIfPresent(String.self, forKey: .targetID)
            return .clientAction(actionType: action, targetID: targetID)

        case .hostStatus:
            let content = HostStatusContent(
                selectedBackend: try c.decodeIfPresent(String.self, forKey: .selectedBackend) ?? "",
                selectedModel: try c.decodeIfPresent(String.self, forKey: .selectedModel) ?? "",
                planMode: try c.decodeIfPresent(Bool.self, forKey: .planMode) ?? false,
                availableBackends: try c.decodeIfPresent([String].self, forKey: .availableBackends) ?? [],
                availableModels: try c.decodeIfPresent([String: [String]].self, forKey: .availableModels) ?? [:],
                activeSubagents: try c.decodeIfPresent([SubagentStatusPayload].self, forKey: .activeSubagents) ?? [],
                systemMetrics: try c.decodeIfPresent(SystemMetricsPayload.self, forKey: .systemMetrics)
                    ?? SystemMetricsPayload(cpuUsage: 0, ramUsage: 0, activeWindow: "")
            )
            return .hostStatus(content)

        case .screenshotPayload:
            let img = try c.decodeIfPresent(String.self, forKey: .base64Image) ?? ""
            return .screenshotPayload(base64Image: img)

        case .toolCallEvent:
            guard let event = try c.decodeIfPresent(ToolCallEventPayload.self, forKey: .toolCallEvent) else {
                return nil
            }
            return .toolCallEvent(event)

        case .archiveListResponse:
            let entries = try c.decodeIfPresent([ArchiveEntryPayload].self, forKey: .archiveEntries) ?? []
            return .archiveListResponse(entries: entries)

        case .archiveLoadRequest:
            let id = try c.decodeIfPresent(String.self, forKey: .archiveLoadID) ?? ""
            return .archiveLoadRequest(archiveID: id)

        case .archiveLoadResponse:
            let messages = try c.decodeIfPresent([Message].self, forKey: .archiveMessages) ?? []
            return .archiveLoadResponse(messages: messages)

        case .archiveRename:
            let id = try c.decodeIfPresent(String.self, forKey: .mutationArchiveID) ?? ""
            // `renameClearsTitle: true` → title kaldır (nil). Aksi halde
            // `renameNewTitle` decode; field yoksa nil sayma → boş string olarak
            // davran (ConversationStore.renameArchive whitespace-only'i de
            // sıfırlama sayar — pratikte aynı sonuç).
            let clears = try c.decodeIfPresent(Bool.self, forKey: .renameClearsTitle) ?? false
            if clears {
                return .archiveRename(archiveID: id, newTitle: nil)
            }
            let title = try c.decodeIfPresent(String.self, forKey: .renameNewTitle)
            return .archiveRename(archiveID: id, newTitle: title)

        case .archiveSetTags:
            let id = try c.decodeIfPresent(String.self, forKey: .mutationArchiveID) ?? ""
            // `editedTags` yoksa nil → tüm tag'leri kaldır anlamı; varsa
            // (boş array dahil) explicit set.
            let tags = try c.decodeIfPresent([String].self, forKey: .editedTags)
            return .archiveSetTags(archiveID: id, tags: tags)

        case .ping, .ready, .archiveListRequest, .unknown:
            // Empty payload type'lar — nil dönmeli (RemoteEnvelope.payload = nil).
            return nil
        }
    }

    /// Encode: case'e göre ilgili field'ları wire'a yaz. Eski formatla
    /// birebir aynı — boş field'lar omit edilir (`encodeIfPresent`).
    fileprivate func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: PayloadKey.self)
        switch self {
        case .hello(let pk):
            try c.encode(pk, forKey: .publicKey)

        case .error(let code, let msg):
            try c.encode(code, forKey: .errorCode)
            try c.encode(msg, forKey: .errorMessage)

        case .ack(let id):
            try c.encode(id, forKey: .messageID)

        case .userMessage(let text, let id):
            try c.encode(text, forKey: .text)
            try c.encode("user", forKey: .role)
            try c.encodeIfPresent(id, forKey: .messageID)

        case .assistantMessage(let text, let id):
            try c.encode(text, forKey: .text)
            try c.encode("assistant", forKey: .role)
            try c.encodeIfPresent(id, forKey: .messageID)

        case .assistantChunk(let text, let id):
            try c.encode(text, forKey: .text)
            try c.encode("assistant", forKey: .role)
            try c.encodeIfPresent(id, forKey: .messageID)

        case .clientConfig(let backend, let model, let plan):
            try c.encode(backend, forKey: .selectedBackend)
            try c.encode(model, forKey: .selectedModel)
            try c.encode(plan, forKey: .planMode)

        case .clientAction(let action, let targetID):
            try c.encode(action, forKey: .actionType)
            try c.encodeIfPresent(targetID, forKey: .targetID)

        case .hostStatus(let content):
            try c.encode(content.selectedBackend, forKey: .selectedBackend)
            try c.encode(content.selectedModel, forKey: .selectedModel)
            try c.encode(content.planMode, forKey: .planMode)
            try c.encode(content.availableBackends, forKey: .availableBackends)
            try c.encode(content.availableModels, forKey: .availableModels)
            try c.encode(content.activeSubagents, forKey: .activeSubagents)
            try c.encode(content.systemMetrics, forKey: .systemMetrics)

        case .screenshotPayload(let img):
            try c.encode(img, forKey: .base64Image)

        case .toolCallEvent(let event):
            try c.encode(event, forKey: .toolCallEvent)

        case .archiveListResponse(let entries):
            try c.encode(entries, forKey: .archiveEntries)

        case .archiveLoadRequest(let id):
            try c.encode(id, forKey: .archiveLoadID)

        case .archiveLoadResponse(let messages):
            try c.encode(messages, forKey: .archiveMessages)

        case .archiveRename(let id, let title):
            try c.encode(id, forKey: .mutationArchiveID)
            if let title {
                try c.encode(title, forKey: .renameNewTitle)
            } else {
                // nil intent'ini wire'da explicit sentinel ile taşı.
                try c.encode(true, forKey: .renameClearsTitle)
            }

        case .archiveSetTags(let id, let tags):
            try c.encode(id, forKey: .mutationArchiveID)
            // tags nil → field omit (decoder nil olarak okur → "kaldır")
            // tags == [] → explicit boş array yine "kaldır" semantiği
            try c.encodeIfPresent(tags, forKey: .editedTags)
        }
    }
}

// MARK: - RemoteEnvelope (custom Codable, type-aware payload decode)

public struct RemoteEnvelope: Sendable, Equatable {
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

extension RemoteEnvelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case v, id, ts, type, payload, sig
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.v = try c.decode(Int.self, forKey: .v)
        self.id = try c.decode(String.self, forKey: .id)
        self.ts = try c.decode(Int.self, forKey: .ts)
        self.type = try c.decode(EnvelopeType.self, forKey: .type)
        self.sig = try c.decodeIfPresent(String.self, forKey: .sig)

        // Payload type-aware decode. Wire'da nested container var mı kontrol.
        if c.contains(.payload), try !c.decodeNil(forKey: .payload) {
            let nested = try c.superDecoder(forKey: .payload)
            self.payload = try EnvelopePayload.decode(from: nested, type: self.type)
        } else {
            self.payload = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(id, forKey: .id)
        try c.encode(ts, forKey: .ts)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(sig, forKey: .sig)

        if let payload {
            let nested = c.superEncoder(forKey: .payload)
            try payload.encode(to: nested)
        }
    }
}

// MARK: - Factory metodları

extension RemoteEnvelope {
    public static func userMessage(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(type: .userMessage, payload: .userMessage(text: text, messageID: messageID))
    }

    public static func assistantMessage(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(type: .assistantMessage, payload: .assistantMessage(text: text, messageID: messageID))
    }

    public static func assistantChunk(text: String, messageID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(type: .assistantChunk, payload: .assistantChunk(text: text, messageID: messageID))
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
        return RemoteEnvelope(type: .toolCallEvent, payload: .toolCallEvent(event))
    }

    // MARK: - Sprint 5 (iOS history viewer) archive flow

    public static func archiveListRequest() -> RemoteEnvelope {
        RemoteEnvelope(type: .archiveListRequest)
    }

    public static func archiveListResponse(entries: [ArchiveEntryPayload]) -> RemoteEnvelope {
        RemoteEnvelope(type: .archiveListResponse, payload: .archiveListResponse(entries: entries))
    }

    public static func archiveLoadRequest(id: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .archiveLoadRequest, payload: .archiveLoadRequest(archiveID: id))
    }

    public static func archiveLoadResponse(messages: [Message]) -> RemoteEnvelope {
        RemoteEnvelope(type: .archiveLoadResponse, payload: .archiveLoadResponse(messages: messages))
    }

    /// Sprint 10 (v0.2.35): iOS → Mac. Bir arşivi yeniden adlandır.
    /// `newTitle` nil → custom title kaldırılır (snippet fallback'e döner).
    public static func archiveRename(archiveID: String, newTitle: String?) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .archiveRename,
            payload: .archiveRename(archiveID: archiveID, newTitle: newTitle)
        )
    }

    /// Sprint 10 (v0.2.35): iOS → Mac. Bir arşivin tag listesini ayarla.
    /// `tags` nil veya boş → tüm tag'ler kaldırılır.
    public static func archiveSetTags(archiveID: String, tags: [String]?) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .archiveSetTags,
            payload: .archiveSetTags(archiveID: archiveID, tags: tags)
        )
    }

    /// Handshake'in ilk envelope'u: gönderen tarafın public key'ini taşır.
    public static func hello(publicKey: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .hello, payload: .hello(publicKey: publicKey))
    }

    public static func ack(referenceID: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .ack, payload: .ack(referenceID: referenceID))
    }

    public static func error(code: String, message: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .error, payload: .error(code: code, message: message))
    }

    public static func clientConfig(backend: String, model: String, planMode: Bool) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .clientConfig,
            payload: .clientConfig(backend: backend, model: model, planMode: planMode)
        )
    }

    public static func clientAction(type actionType: String, targetID: String? = nil) -> RemoteEnvelope {
        RemoteEnvelope(
            type: .clientAction,
            payload: .clientAction(actionType: actionType, targetID: targetID)
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
        let content = HostStatusContent(
            selectedBackend: selectedBackend,
            selectedModel: selectedModel,
            planMode: planMode,
            availableBackends: availableBackends,
            availableModels: availableModels,
            activeSubagents: activeSubagents,
            systemMetrics: systemMetrics
        )
        return RemoteEnvelope(type: .hostStatus, payload: .hostStatus(content))
    }

    public static func screenshotPayload(base64Image: String) -> RemoteEnvelope {
        RemoteEnvelope(type: .screenshotPayload, payload: .screenshotPayload(base64Image: base64Image))
    }
}
