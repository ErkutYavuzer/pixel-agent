import Foundation

/// **Sprint 43 (v0.2.70):** OpenAI Realtime audio format codec.
///
/// **Format spec** (OpenAI Realtime API doc):
/// - 16-bit signed PCM (`Int16`)
/// - 24 kHz sample rate
/// - Mono (1 channel)
/// - Little-endian byte order
/// - **Base64-encoded** when sent over WebSocket (JSON-safe)
///
/// **Mic capture path** (provider'da AVAudioEngine tap → AVAudioPCMBuffer):
/// 1. Apple format: typically Float32 48kHz stereo
/// 2. Convert → Int16 24kHz mono (resampling + downmix + clamp)
/// 3. `encodeToBase64([Int16])` → "input_audio_buffer.append" event
///
/// **Server response path** (`response.audio.delta`):
/// 1. Server gönderir: base64 Int16 24kHz mono
/// 2. `decodeFromBase64(_:)` → [Int16]
/// 3. AVAudioEngine'e PCM16 buffer olarak schedule
///
/// **Saf helper** — Foundation only, no AVFoundation. Test edilebilir,
/// platform-independent. Resampling/downmix `RealtimeAudioPlayer`'da
/// (AVFoundation gerek).
public enum PCMAudioCodec {
    /// OpenAI Realtime sabit sample rate (Hz).
    public static let sampleRate: Int = 24_000

    /// Mono — 1 channel.
    public static let channels: Int = 1

    /// Int16 = 2 byte per sample.
    public static let bytesPerSample: Int = 2

    /// **Sprint 43:** Int16 PCM array → base64 string.
    /// Little-endian byte order (OpenAI spec).
    public static func encodeToBase64(_ samples: [Int16]) -> String {
        guard !samples.isEmpty else { return "" }
        let byteCount = samples.count * bytesPerSample
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let dst = rawBuffer.baseAddress else { return }
            samples.withUnsafeBufferPointer { src in
                memcpy(dst, src.baseAddress, byteCount)
            }
        }
        return data.base64EncodedString()
    }

    /// **Sprint 43:** Base64 string → Int16 PCM array.
    /// Bozuk base64 veya odd byte count → empty array (defensive).
    public static func decodeFromBase64(_ base64: String) -> [Int16] {
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            return []
        }
        // Byte count Int16 boundary'sine yakın olmalı; değilse trim.
        let sampleCount = data.count / bytesPerSample
        guard sampleCount > 0 else { return [] }
        var samples = [Int16](repeating: 0, count: sampleCount)
        samples.withUnsafeMutableBufferPointer { dst in
            data.withUnsafeBytes { src in
                guard let srcPtr = src.baseAddress else { return }
                memcpy(dst.baseAddress, srcPtr, sampleCount * bytesPerSample)
            }
        }
        return samples
    }

    /// **Sprint 43:** Float32 [−1.0, +1.0] sample → Int16 [-32768, 32767]
    /// clamp + scale conversion. Resampling caller'ın işi (AVAudioConverter).
    public static func float32ToInt16(_ floats: [Float]) -> [Int16] {
        floats.map { f in
            let clamped = max(-1.0, min(1.0, f))
            let scaled = clamped * 32767.0
            return Int16(scaled.rounded())
        }
    }

    /// **Sprint 43:** Int16 → Float32 [−1.0, +1.0] normalize.
    public static func int16ToFloat32(_ samples: [Int16]) -> [Float] {
        samples.map { Float($0) / 32767.0 }
    }
}
