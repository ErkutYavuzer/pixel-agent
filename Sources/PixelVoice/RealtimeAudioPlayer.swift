#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// **Sprint 43 (v0.2.70):** OpenAI Realtime audio chunk playback.
///
/// Server `response.audio.delta` event'i base64 Int16 PCM 24kHz mono chunk
/// yolladığında bu player AVAudioEngine üstünden schedule eder. Chunk'lar
/// sıralı çalınır (buffer queue).
///
/// `AVAudioPCMBuffer` Sendable değil — actor içinde tutmak yerine her
/// `schedule(_:)` çağrısında yeni buffer yaratılır, AVAudioEngine'e push
/// edilir. Apple framework internal queue thread-safe.
public actor RealtimeAudioPlayer {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let outputFormat: AVAudioFormat
    private var isStarted: Bool = false

    public init() {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        // OpenAI Realtime: PCM16 24kHz mono LE.
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(PCMAudioCodec.sampleRate),
            channels: AVAudioChannelCount(PCMAudioCodec.channels),
            interleaved: true
        )!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
    }

    /// **Sprint 43:** Engine'i başlat. Idempotent.
    public func start() throws {
        guard !isStarted else { return }
        engine.prepare()
        try engine.start()
        playerNode.play()
        isStarted = true
    }

    /// **Sprint 43:** Engine'i durdur — queued buffer'lar drain edilir.
    public func stop() {
        playerNode.stop()
        engine.stop()
        isStarted = false
    }

    /// **Sprint 43:** PCM16 Int16 sample'larını AVAudioPCMBuffer'a kopyala
    /// ve queue'ya schedule et. Player otomatik sırayla çalar.
    public func schedule(samples: [Int16]) {
        guard !samples.isEmpty, isStarted else { return }
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCount
        ) else { return }
        buffer.frameLength = frameCount
        guard let channelData = buffer.int16ChannelData else { return }
        samples.withUnsafeBufferPointer { src in
            memcpy(channelData[0], src.baseAddress, samples.count * MemoryLayout<Int16>.size)
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// **Sprint 44 aday:** Queued buffer'ları drop et + playback'i kes.
    /// Sprint 43 MVP'de kullanılmıyor (server-side VAD interrupt yok).
    public func interrupt() {
        playerNode.stop()
        playerNode.play()
    }

    public var snapshotIsStarted: Bool { isStarted }
}

#endif
