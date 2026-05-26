#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// **Sprint 43 (v0.2.70):** OpenAI Realtime API WebSocket provider.
///
/// **Endpoint:** `wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17`
/// **Headers:** `Authorization: Bearer <api_key>`, `OpenAI-Beta: realtime=v1`
///
/// **Akış (Sprint 43 MVP):**
/// 1. `start()`:
///    - API key oku (VoiceCredentialsStore)
///    - WebSocket bağlantı kur (`URLSessionWebSocketTask`)
///    - Server-side VAD config gönder (`session.update`)
///    - Mic capture başlat (AVAudioEngine tap)
///    - Audio chunk'ları base64 encode → `input_audio_buffer.append` send
///    - Receive loop: server event'leri parse + handle
/// 2. Server VAD speech_started/stopped → response otomatik trigger
///    (`response.create` client'tan gerekmiyor — server otomatik)
/// 3. Server `response.audio.delta` → `RealtimeAudioPlayer.schedule`
/// 4. Server `response.audio_transcript.delta` → `.interim` transcript event
/// 5. Server `response.done` → `.final` transcript event (full text)
/// 6. `stop()`: WebSocket close, mic tap remove
///
/// **Sprint 44 aday:** Interrupt (`response.cancel`), function calling
/// (`session.tools` + `response.function_call_arguments.done` handle).
///
/// **Mic capture format:** Apple genelde Float32 48kHz stereo verir; bunu
/// Int16 24kHz mono'ya çeviriyoruz (downsample + downmix + format convert).
/// `AVAudioConverter` Apple'ın kendi resampler'ı.
public actor OpenAIRealtimeProvider: VoiceProvider {
    public nonisolated let providerName: String = "OpenAI Realtime"

    public static let endpoint = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17")!

    private let credentialsStore: VoiceCredentialsStore
    private let audioEngine: AVAudioEngine
    private let audioPlayer: RealtimeAudioPlayer
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var isRunning: Bool = false
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    private var accumulatedTranscript: String = ""

    public init(credentialsStore: VoiceCredentialsStore = VoiceCredentialsStore()) {
        self.credentialsStore = credentialsStore
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
        // Mic permission + API key var mı
        let mic: Bool = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        let hasKey = credentialsStore.hasKey(for: .openaiRealtime)
        return mic && hasKey
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard let apiKey = credentialsStore.openaiKey() else {
            continuation?.yield(.error(message: "OpenAI API anahtarı eksik. Settings → Sesli Mod → API Anahtarları."))
            throw VoiceError.notAuthorized
        }

        // 1. WebSocket bağlantı
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        self.webSocketTask = task

        // 2. Session config — server-side VAD aktif
        let config = SessionConfig()
        let sessionEvent = RealtimeClientEvent.sessionUpdate(config: config)
        try await sendEvent(sessionEvent)

        // 3. Audio playback engine
        try await audioPlayer.start()

        // 4. Mic capture başlat
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
        // OpenAI Realtime'da `speak` direkt yok — agent zaten ses üretiyor.
        // No-op (Sprint 44'te muhtemelen `response.create` + manual text turn).
    }

    public func cancelSpeech() async {
        // Sprint 44 aday: response.cancel + audioPlayer.interrupt()
    }

    // MARK: - Mic capture

    private func startMicCapture() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target: PCM16 24kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(PCMAudioCodec.sampleRate),
            channels: AVAudioChannelCount(PCMAudioCodec.channels),
            interleaved: true
        ) else {
            throw VoiceError.audioEngineFailure("Target format yaratılamadı")
        }

        // AVAudioConverter — Apple's resampler/format converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw VoiceError.audioEngineFailure("AVAudioConverter yaratılamadı")
        }

        // WebSocket'i closure içinde kullanmak için weak ref + Task hop
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            // Convert source buffer → target Int16 24kHz mono
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

            // Int16 samples extract
            guard let channelData = outputBuffer.int16ChannelData else { return }
            let count = Int(outputBuffer.frameLength)
            guard count > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

            // Base64 encode + WebSocket send (Task hop)
            let base64 = PCMAudioCodec.encodeToBase64(samples)
            Task { [weak self] in
                guard let self else { return }
                try? await self.sendEvent(.inputAudioBufferAppend(audioBase64: base64))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - WebSocket send/receive

    private func sendEvent(_ event: RealtimeClientEvent) async throws {
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
                guard let event = RealtimeServerEvent.decode(data) else { continue }
                await handle(event: event)
            } catch {
                continuation?.yield(.error(message: "WebSocket: \(error.localizedDescription)"))
                break
            }
        }
    }

    private func handle(event: RealtimeServerEvent) async {
        switch event {
        case .sessionCreated:
            // Hand-shake OK
            break
        case .sessionUpdated:
            // Config ack
            break
        case .audioDelta(let base64):
            let samples = PCMAudioCodec.decodeFromBase64(base64)
            if !samples.isEmpty {
                await audioPlayer.schedule(samples: samples)
            }
        case .transcriptDelta(let text):
            accumulatedTranscript += text
            continuation?.yield(.interim(text: accumulatedTranscript))
        case .responseDone:
            if !accumulatedTranscript.isEmpty {
                continuation?.yield(.final(text: accumulatedTranscript))
                accumulatedTranscript = ""
            }
        case .speechStarted, .speechStopped:
            // Sprint 44 aday: UI feedback (mascot listening state)
            break
        case .error(let msg):
            continuation?.yield(.error(message: msg))
        case .unknown:
            break
        }
    }
}

#endif
