import Foundation
import PixelComputerUse
import SwiftUI

/// **Sprint 15 (v0.2.40):** iOS continuous screenshot stream için Mac side
/// task management. iOS `screenshotStreamStart` envelope gönderince
/// start'lanır; her interval'da screenshot çekip JPEG + base64'leyip
/// `sendImage` callback'i çağırır. `screenshotStreamStop` veya disconnect
/// stop tetikler.
///
/// `@MainActor ObservableObject` — ChatHost `@StateObject` olarak tutar.
/// Task referansı internal; dış API sadece start/stop + `isActive`
/// @Published.
@MainActor
public final class ScreenshotStreamCoordinator: ObservableObject {
    @Published public private(set) var isActive: Bool = false
    /// Şu an aktif kullanılan interval (Sprint 21: adaptive — son tick latency'sine göre değişebilir).
    @Published public private(set) var intervalMs: Int = 1000
    /// **Sprint 21 (v0.2.46):** Son tick'te ölçülen send latency (capture +
    /// JPEG + transport.send). UI debugging veya istatistik için public.
    @Published public private(set) var lastSendLatencyMs: Int = 0

    private var task: Task<Void, Never>?
    /// Kullanıcı tercih tabanı — adaptive controller buna kadar küçülür.
    private var baseIntervalMs: Int = 1000

    public init() {}

    /// Stream başlat. Önceki task varsa cancel edilir. `sendImage` her
    /// frame için çağrılır (base64 JPEG). Caller `sendImage`'in
    /// thread-safe / actor-isolated olduğundan emin olmalı.
    ///
    /// **Sprint 21 (v0.2.46):** `requestedMs` kullanıcı tercih tabanı —
    /// adaptive controller `AdaptiveRateController` ile bunun **üstünde**
    /// hareket edebilir (slow network'te büyür, rahat network'te tabana
    /// döner).
    public func start(
        intervalMs requestedMs: Int,
        sendImage: @escaping @Sendable (String) async -> Void
    ) {
        stop()
        // Defensive clamp — envelope decoder zaten clamp'liyor ama yine de.
        let clampedMs = max(250, min(5000, requestedMs))
        intervalMs = clampedMs
        baseIntervalMs = clampedMs
        lastSendLatencyMs = 0
        isActive = true

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let active = await self?.isActive, active else { break }

                let sendStart = Date()
                do {
                    let result = try await ScreenshotCapture.capture(target: .activeDisplay)
                    if let jpegData = ImageEncoding.compressPNGToJPEG(
                        data: result.pngData,
                        quality: 0.5
                    ) {
                        let base64 = jpegData.base64EncodedString()
                        await sendImage(base64)
                    }
                } catch {
                    // Screenshot başarısız → log + bir sonraki tick'i bekle
                    // (tek frame skip; stream devam eder). PixelAgent.app
                    // çoğu zaman Screen Recording iznine sahip.
                }

                if Task.isCancelled { break }

                // **Sprint 21 (v0.2.46):** Adaptive rate — son tick latency'sini
                // ölç, controller ile yeni interval öner. Kullanıcı tercih
                // baseMs'e kadar küçülür; slow network'te büyür.
                let latencyMs = Int(Date().timeIntervalSince(sendStart) * 1000)
                let currentMs = await self?.intervalMs ?? clampedMs
                let baseMs = await self?.baseIntervalMs ?? clampedMs
                let nextMs = AdaptiveRateController.nextInterval(
                    currentMs: currentMs,
                    lastSendLatencyMs: latencyMs,
                    baseMs: baseMs
                )
                await self?.applyAdaptiveTick(latency: latencyMs, newInterval: nextMs)

                try? await Task.sleep(nanoseconds: UInt64(nextMs) * 1_000_000)
            }

            // Final state reset — task end veya cancel.
            await self?.markInactive()
        }
    }

    /// Sprint 21: Adaptive tick state update — MainActor isolated.
    private func applyAdaptiveTick(latency: Int, newInterval: Int) {
        lastSendLatencyMs = latency
        if newInterval != intervalMs {
            intervalMs = newInterval
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isActive = false
    }

    private func markInactive() {
        // Task'in son çağrısı — UI state'i temizle (cancel veya doğal exit).
        isActive = false
    }
}
