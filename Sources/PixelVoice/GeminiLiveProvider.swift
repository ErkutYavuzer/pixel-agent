#if canImport(AVFoundation)
import AVFoundation
import Foundation
import PixelMCPServer

/// **Sprint 45 (v0.2.72):** Google Gemini Live API WebSocket provider.
///
/// **Endpoint:** `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=<API_KEY>`
///
/// **Audio formatı:**
/// - Input: PCM16 16 kHz mono (OpenAI'den FARKLI; OpenAI 24kHz)
/// - Output: PCM16 24 kHz mono (RealtimeAudioPlayer Sprint 43'ten reuse)
///
/// **Akış (Sprint 45 MVP):**
/// 1. `start()`:
///    - API key oku (VoiceCredentialsStore.geminiKey)
///    - WebSocket bağlantı `?key=<KEY>` query param ile
///    - `setup` event yolla (model + system_instruction + tools + AUDIO modality)
///    - Mic capture: AVAudioConverter (Apple → PCM16 16kHz mono) → base64 →
///      `realtime_input.media_chunks`
///    - Receive loop event dispatch
/// 2. Server `serverContent.modelTurn.parts[].inlineData` → audio chunk →
///    audioPlayer.schedule (24kHz)
/// 3. Server `toolCall.functionCalls[]` → MCP dispatch → `toolResponse`
/// 4. Server `serverContent.interrupted: true` → audioPlayer.interrupt
///    (kullanıcı agent'ı kesti); Gemini bu durumda yeni input bekler.
/// 5. `stop()`: WebSocket close + mic stop + player stop
public actor GeminiLiveProvider: VoiceProvider {
    public nonisolated let providerName: String = "Gemini Live"

    /// **Gemini Live endpoint base** — `?key=...` parametre runtime'da eklenir.
    public static let endpointBase = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    /// **Input audio sample rate** — Gemini spec: 16 kHz (OpenAI 24kHz'den farklı).
    public static let inputSampleRate: Int = 16_000

    private let credentialsStore: VoiceCredentialsStore
    private let toolRegistry: ToolRegistry?
    private let audioEngine: AVAudioEngine
    private let audioPlayer: RealtimeAudioPlayer
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isRunning: Bool = false
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    private var accumulatedTranscript: String = ""

    public init(
        credentialsStore: VoiceCredentialsStore = VoiceCredentialsStore(),
        toolRegistry: ToolRegistry? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.toolRegistry = toolRegistry
        self.audioEngine = AVAudioEngine()
        self.audioPlayer = RealtimeAudioPlayer()
    }

    public nonisolated var transcriptEvents: AsyncStream<TranscriptEvent> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
        }
    }

    private func setContinuation(_ cont: AsyncStream<TranscriptEvent>.Continuation) {
        self.continuation = cont
    }

    public func isAuthorized() async -> Bool {
        let mic: Bool = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        return mic && credentialsStore.hasKey(for: .geminiLive)
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard let apiKey = credentialsStore.geminiKey() else {
            continuation?.yield(.error(message: "Gemini API anahtarı eksik. Settings → Sesli Mod → API Anahtarları."))
            throw VoiceError.notAuthorized
        }

        // 1. WebSocket bağlantı — key query param
        guard var components = URLComponents(string: Self.endpointBase) else {
            throw VoiceError.audioEngineFailure("Gemini endpoint URL parse fail")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw VoiceError.audioEngineFailure("Gemini endpoint URL build fail")
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        self.webSocketTask = task

        // 2. Setup event — model + tools + system_instruction
        let tools: [GeminiTools]?
        if let toolRegistry {
            let voiceTools = GeminiToolBridge.voiceTools(from: toolRegistry)
            tools = voiceTools.isEmpty ? nil : voiceTools
        } else {
            tools = nil
        }
        let config = GeminiSetupConfig(tools: tools)
        let setupEvent = GeminiClientEvent.setup(config: config)
        try await sendEvent(setupEvent)

        // 3. Audio playback engine (24kHz mono — Sprint 43 reuse)
        try await audioPlayer.start()

        // 4. Mic capture başlat — 16kHz target
        try startMicCapture()

        // 5. Receive loop
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }

        isRunning = true
    }

    public func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        if isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        await audioPlayer.stop()
        isRunning = false
    }

    public func speak(_ text: String) async {
        // Gemini Live'da `speak` direkt yok — agent zaten ses üretiyor.
        // No-op.
    }

    /// **Sprint 45 (v0.2.72):** Gemini'de `response.cancel` benzeri client
    /// event yok; sunucu `interrupted: true` döndürür kullanıcı söze
    /// başlayınca. Manuel cancel için audio queue drain yeterli — yeni input
    /// gelir, server otomatik handle eder.
    public func cancelSpeech() async {
        await audioPlayer.interrupt()
    }

    // MARK: - Mic capture

    private func startMicCapture() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: PCM16 16 kHz mono (Gemini spec — OpenAI'den FARKLI)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Self.inputSampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw VoiceError.audioEngineFailure("Target format yaratılamadı (16kHz)")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw VoiceError.audioEngineFailure("AVAudioConverter yaratılamadı")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            let outputBufferCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: max(1, outputBufferCapacity)
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil else { return }

            guard let channelData = outputBuffer.int16ChannelData else { return }
            let count = Int(outputBuffer.frameLength)
            guard count > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

            let base64 = PCMAudioCodec.encodeToBase64(samples)
            Task { [weak self] in
                guard let self else { return }
                try? await self.sendEvent(.realtimeInput(audioBase64: base64))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - WebSocket send/receive

    private func sendEvent(_ event: GeminiClientEvent) async throws {
        guard let task = webSocketTask else { return }
        let data = try JSONEncoder().encode(event)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(text))
    }

    private func runReceiveLoop() async {
        guard let task = webSocketTask else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .string(let s):
                    data = Data(s.utf8)
                case .data(let d):
                    data = d
                @unknown default:
                    continue
                }
                guard let event = GeminiServerEvent.decode(data) else { continue }
                await handle(event: event)
            } catch {
                continuation?.yield(.error(message: "Gemini WebSocket: \(error.localizedDescription)"))
                break
            }
        }
    }

    private func handle(event: GeminiServerEvent) async {
        switch event {
        case .setupComplete:
            // Hand-shake OK
            break
        case .audioChunk(let base64):
            let samples = PCMAudioCodec.decodeFromBase64(base64)
            if !samples.isEmpty {
                await audioPlayer.schedule(samples: samples)
            }
        case .textChunk(let text):
            accumulatedTranscript += text
            continuation?.yield(.interim(text: accumulatedTranscript))
        case .interrupted:
            // Sprint 45 (v0.2.72): Server kullanıcı söze başladığını detect
            // etti → audio queue drain (agent susmalı), agent kendi response'unu
            // yarıda kesti.
            await audioPlayer.interrupt()
        case .turnComplete:
            if !accumulatedTranscript.isEmpty {
                continuation?.yield(.final(text: accumulatedTranscript))
                accumulatedTranscript = ""
            }
        case .toolCall(let calls):
            for call in calls {
                await dispatchToolCall(call)
            }
        case .error(let message):
            continuation?.yield(.error(message: message))
        case .unknown:
            break
        }
    }

    /// **Sprint 45 (v0.2.72):** Gemini function call dispatch — MCP execute,
    /// sonucu `tool_response.function_responses[]` ile yolla.
    private func dispatchToolCall(_ call: GeminiToolCallRequest) async {
        guard let registry = toolRegistry else {
            await sendToolError(call: call, message: "Tool registry yok")
            return
        }
        guard let tool = registry.find(call.name) else {
            await sendToolError(call: call, message: "Tool bulunamadı: \(call.name)")
            return
        }

        // args JSON → JSONValue
        let argsObject = (try? JSONDecoder().decode(JSONValue.self, from: call.argsJSON)) ?? .object([:])
        let result = await tool.handler(argsObject)

        // result JSONValue → AnyEncodable wrapper
        let response = GeminiFunctionResponse(
            id: call.id,
            name: call.name,
            response: AnyEncodable(result)
        )
        try? await sendEvent(.toolResponse(functionResponses: [response]))
    }

    private func sendToolError(call: GeminiToolCallRequest, message: String) async {
        let errorJSON = JSONValue.object([
            "error": .string(message)
        ])
        let response = GeminiFunctionResponse(
            id: call.id,
            name: call.name,
            response: AnyEncodable(errorJSON)
        )
        try? await sendEvent(.toolResponse(functionResponses: [response]))
    }
}

#endif
