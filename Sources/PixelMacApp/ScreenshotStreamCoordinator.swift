import Foundation
import PixelComputerUse
import SwiftUI

/// **Sprint 15 (v0.2.40):** iOS continuous screenshot stream için Mac side
/// task management. iOS `screenshotStreamStart` envelope gönderince
/// start'lanır; her interval'da screenshot çekip JPEG + base64'leyip
/// `sendImage` callback'i çağırır. `screenshotStreamStop` veya disconnect
/// stop tetikler.
///
/// **Sprint 21 (v0.2.46):** Sabit interval yerine `AdaptiveRateController`
/// — son tick latency'sini ölçüp slow/fast lane'lerde scale eder.
///
/// **Sprint 22 (v0.2.47):** Latency artık wire-level. Her tick'te frameID
/// (UUID) üretilip envelope'a iliştirilir; iOS aynı ID'yle ACK döner;
/// `recordAck` round-trip'i hesaplar. Henüz ACK yokken (stream başlangıcı,
/// eski iOS) local latency fallback'i kullanılır — `WireLatencyTracker.effectiveLatencyMs`.
///
/// `@MainActor ObservableObject` — ChatHost `@StateObject` olarak tutar.
@MainActor
public final class ScreenshotStreamCoordinator: ObservableObject {
    @Published public private(set) var isActive: Bool = false
    /// Şu an aktif kullanılan interval (Sprint 21: adaptive — son tick latency'sine göre değişebilir).
    @Published public private(set) var intervalMs: Int = 1000
    /// **Sprint 21 (v0.2.46):** Son tick'te `AdaptiveRateController`'a verilen
    /// effective latency (Sprint 22: wire varsa wire, yoksa local).
    @Published public private(set) var lastSendLatencyMs: Int = 0
    /// **Sprint 22 (v0.2.47):** Yalnızca wire-level latency (son alınan ACK).
    /// UI debug: "Ağ: 87 ms" gibi gösterim için. nil → henüz ACK gelmedi.
    @Published public private(set) var lastWireLatencyMs: Int?

    private var task: Task<Void, Never>?
    /// Kullanıcı tercih tabanı — adaptive controller buna kadar küçülür.
    private var baseIntervalMs: Int = 1000
    /// Sprint 22 (v0.2.47): wire latency state. `recordAck` ve loop tick
    /// bu state'i okuyup/güncelliyor. MainActor isolated.
    private var wireState = WireLatencyState()

    public init() {}

    /// Stream başlat. Önceki task varsa cancel edilir. `sendImage` her
    /// frame için çağrılır (base64 JPEG + frameID). Caller `sendImage`'in
    /// thread-safe / actor-isolated olduğundan emin olmalı.
    ///
    /// **Sprint 21 (v0.2.46):** `requestedMs` kullanıcı tercih tabanı —
    /// adaptive controller `AdaptiveRateController` ile bunun **üstünde**
    /// hareket edebilir (slow network'te büyür, rahat network'te tabana
    /// döner).
    ///
    /// **Sprint 22 (v0.2.47):** `sendImage` callback `(base64, frameID)` alır.
    /// frameID her tick'te yeni UUID. iOS ACK ile geri yansıtır.
    /// **Sprint 24 (v0.2.49):** Callback `(base64, frameID, wireLatencyMs?)` —
    /// önceki frame'in ACK round-trip ölçümünü her envelope'a embed eder; iOS
    /// Mac Paneli badge per-frame (~1Hz) güncellenir. Sprint 23'ün hostStatus
    /// 3sn lag'ini eler.
    public func start(
        intervalMs requestedMs: Int,
        sendImage: @escaping @Sendable (_ base64: String, _ frameID: String, _ wireLatencyMs: Int?) async -> Void
    ) {
        stop()
        // Defensive clamp — envelope decoder zaten clamp'liyor ama yine de.
        let clampedMs = max(250, min(5000, requestedMs))
        intervalMs = clampedMs
        baseIntervalMs = clampedMs
        lastSendLatencyMs = 0
        lastWireLatencyMs = nil
        wireState = WireLatencyState()
        isActive = true

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let active = await self?.isActive, active else { break }

                let frameID = UUID().uuidString
                let sendStart = Date()
                await self?.markFrameSent(frameID: frameID, at: sendStart)

                // Sprint 24 (v0.2.49): önceki frame'in ACK round-trip ölçümünü
                // (varsa) bu frame'e embed et — iOS badge per-frame güncellenir.
                // İlk frame için nil; ikinci frame'den itibaren önceki ACK
                // değeri taşınır. wireState pruning sonrası lastWireLatencyMs
                // güncel kalır.
                let latencyToEmbed = await self?.lastWireLatencyMs

                do {
                    let result = try await ScreenshotCapture.capture(target: .activeDisplay)
                    if let jpegData = ImageEncoding.compressPNGToJPEG(
                        data: result.pngData,
                        quality: 0.5
                    ) {
                        let base64 = jpegData.base64EncodedString()
                        await sendImage(base64, frameID, latencyToEmbed)
                    }
                } catch {
                    // Screenshot başarısız → log + bir sonraki tick'i bekle
                    // (tek frame skip; stream devam eder). PixelAgent.app
                    // çoğu zaman Screen Recording iznine sahip.
                }

                if Task.isCancelled { break }

                // Sprint 21 (v0.2.46): Adaptive rate — son tick latency'sini
                // ölç, controller ile yeni interval öner. Kullanıcı tercih
                // baseMs'e kadar küçülür; slow network'te büyür.
                //
                // Sprint 22 (v0.2.47): Latency artık `effectiveLatencyMs` —
                // wire varsa wire (gerçek round-trip), yoksa local (eski
                // iOS veya stream başlangıcı fallback'i).
                let localLatencyMs = Int(Date().timeIntervalSince(sendStart) * 1000)
                let now = Date()
                let effective = await self?.effectiveLatencyAndPrune(
                    localMs: localLatencyMs,
                    now: now
                ) ?? localLatencyMs
                let currentMs = await self?.intervalMs ?? clampedMs
                let baseMs = await self?.baseIntervalMs ?? clampedMs
                let nextMs = AdaptiveRateController.nextInterval(
                    currentMs: currentMs,
                    lastSendLatencyMs: effective,
                    baseMs: baseMs
                )
                await self?.applyAdaptiveTick(latency: effective, newInterval: nextMs)

                try? await Task.sleep(nanoseconds: UInt64(nextMs) * 1_000_000)
            }

            // Final state reset — task end veya cancel.
            await self?.markInactive()
        }
    }

    /// **Sprint 22 (v0.2.47):** iOS ACK geldi — `RemoteHost.onScreenshotFrameAckReceived`
    /// callback'i bunu çağırır. frameID pending map'inde bulunursa wire
    /// latency hesaplanıp `lastWireLatencyMs` published'ı güncellenir; bir
    /// sonraki tick `effectiveLatencyMs` üzerinden adaptive controller'a
    /// iletilir. Stream aktif değilken gelen geç ACK'ler güvenli no-op
    /// (state zaten reset edilmiştir).
    public func recordAck(frameID: String, at receivedAt: Date) {
        guard let latency = WireLatencyTracker.consumeAck(
            state: &wireState,
            frameID: frameID,
            receivedAt: receivedAt
        ) else {
            return
        }
        lastWireLatencyMs = latency
    }

    /// Sprint 22: frame gönderildiğinde tracker'a kaydet (MainActor isolated).
    /// Worker Task'ten çağrılır.
    private func markFrameSent(frameID: String, at sentAt: Date) {
        WireLatencyTracker.record(state: &wireState, frameID: frameID, at: sentAt)
    }

    /// Sprint 22: tick sonunda local + wire'dan effective seç ve stale
    /// pending entry'leri temizle (30s threshold). Tek MainActor hop'ta
    /// hem prune hem effectiveLatencyMs.
    private func effectiveLatencyAndPrune(localMs: Int, now: Date) -> Int {
        WireLatencyTracker.prune(state: &wireState, olderThan: now.addingTimeInterval(-30))
        return WireLatencyTracker.effectiveLatencyMs(
            state: wireState,
            localMs: localMs,
            now: now
        )
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
