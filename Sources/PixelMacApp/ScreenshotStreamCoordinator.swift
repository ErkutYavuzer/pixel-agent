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
    @Published public private(set) var intervalMs: Int = 1000

    private var task: Task<Void, Never>?

    public init() {}

    /// Stream başlat. Önceki task varsa cancel edilir. `sendImage` her
    /// frame için çağrılır (base64 JPEG). Caller `sendImage`'in
    /// thread-safe / actor-isolated olduğundan emin olmalı.
    public func start(
        intervalMs requestedMs: Int,
        sendImage: @escaping @Sendable (String) async -> Void
    ) {
        stop()
        // Defensive clamp — envelope decoder zaten clamp'liyor ama yine de.
        let clampedMs = max(250, min(5000, requestedMs))
        let interval = Double(clampedMs) / 1000.0
        intervalMs = clampedMs
        isActive = true

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let active = await self?.isActive, active else { break }

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
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            // Final state reset — task end veya cancel.
            await self?.markInactive()
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
