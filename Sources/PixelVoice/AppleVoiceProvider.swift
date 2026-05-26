#if canImport(Speech) && canImport(AVFoundation)
import AVFoundation
import Foundation
import Speech

/// **Sprint 42 (v0.2.69):** Apple framework tabanlı VoiceProvider — SFSpeech
/// Recognizer + AVSpeechSynthesizer. Lokal, ücretsiz, sıfır API key.
///
/// **Latency:** Microphone capture → SFSpeechRecognitionTask → interim/final
/// transcript, ~100ms typical. Apple Silicon Neural Engine accelerated.
///
/// **Limitasyonlar (Sprint 43+'da OpenAI Realtime/Gemini Live ile aşılır):**
/// - **Interrupt zayıf:** Agent konuşurken kullanıcı sözünü kesemez (TTS
///   queue'da kalır). OpenAI Realtime server-side VAD ile düzgün interrupt.
/// - **Function calling YOK:** Agent voice modunda MCP tool çağıramaz —
///   sadece transcript → text → backend → text → speak akışı.
/// - **Türkçe destek vardır** (`tr-TR` locale ile init'lenirse). Default
///   `en-US`; Settings'te locale picker (v0.2.70+).
///
/// **Permission:**
/// - `NSMicrophoneUsageDescription` Info.plist
/// - `NSSpeechRecognitionUsageDescription` Info.plist
/// - `AVCaptureDevice.requestAccess(for: .audio)` runtime
/// - `SFSpeechRecognizer.requestAuthorization` runtime
public actor AppleVoiceProvider: VoiceProvider {
    public nonisolated let providerName: String = "Apple Speech"

    public nonisolated let locale: Locale
    private let synthesizer: AVSpeechSynthesizer
    private let audioEngine: AVAudioEngine
    private let recognizer: SFSpeechRecognizer?

    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning: Bool = false

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
        self.synthesizer = AVSpeechSynthesizer()
        self.audioEngine = AVAudioEngine()
        self.recognizer = SFSpeechRecognizer(locale: locale)
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
        // Both speech recognition and microphone must be granted.
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard speech == .authorized else { return false }

        let mic: Bool = await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        return mic
    }

    public func start() async throws {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else {
            continuation?.yield(.error(message: "SFSpeechRecognizer kullanılamıyor (locale: \(locale.identifier))"))
            throw VoiceError.recognizerUnavailable
        }
        let authorized = await isAuthorized()
        guard authorized else {
            continuation?.yield(.error(message: "Mikrofon veya konuşma tanıma izni verilmedi"))
            throw VoiceError.notAuthorized
        }

        // Start engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        // Continuation closure'una @Sendable yields için snapshot
        let yielder: @Sendable (TranscriptEvent) -> Void = { [weak self] event in
            Task { await self?.yieldEvent(event) }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    yielder(.final(text: text))
                } else {
                    yielder(.interim(text: text))
                }
            }
            if let error {
                yielder(.error(message: error.localizedDescription))
            }
        }

        // SFSpeechAudioBufferRecognitionRequest.append thread-safe — closure
        // içinde direkt çağır (actor hop'una gerek yok). AVAudioPCMBuffer
        // Sendable değil ama recognition request'i kendi internal queue'sunda
        // process eder.
        let requestRef = request
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            requestRef.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRunning = true
        } catch {
            continuation?.yield(.error(message: "Audio engine başlatılamadı: \(error.localizedDescription)"))
            throw error
        }
    }

    public func stop() async {
        guard isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRunning = false
    }

    public func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    public func cancelSpeech() async {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Private helpers

    private func yieldEvent(_ event: TranscriptEvent) {
        continuation?.yield(event)
    }
}

/// **Sprint 42 (v0.2.69):** Voice provider hataları.
public enum VoiceError: Error, Sendable {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineFailure(String)
}

#endif
