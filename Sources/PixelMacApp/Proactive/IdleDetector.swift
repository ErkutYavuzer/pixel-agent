import AppKit
import Foundation

/// **Sprint 38 (v0.2.65):** Sistem idle süresi detektörü.
///
/// `CGEventSource.secondsSinceLastEventType(.combinedSessionState,
/// eventType: anyInput)` — Apple framework, accessibility permission YOK.
/// Klavye + fare + trackpad herhangi bir event'in üzerinden geçen saniyeyi
/// döndürür.
///
/// `IdleDetector` polling actor:
/// - Her 10 saniyede idle süresi check
/// - Threshold (default 15 dk = 900s) aşılırsa `onIdleDetected` callback
/// - Kullanıcı tekrar aktif (idle < threshold/2) olursa `hasFired` reset →
///   bir sonraki idle döngüsünde tekrar tetiklenebilir
///
/// **Saf clock + idle source injection** — test'lerde mock kullanılabilir.
public actor IdleDetector {
    /// Mock'lanabilir idle süre kaynağı. Production'da CGEventSource;
    /// test'lerde fake closure.
    public typealias IdleSource = @Sendable () -> TimeInterval

    /// Her tetikleyen iş kuyruğa çağrılır. Caller `ProactiveEngine`.
    public typealias FireCallback = @Sendable (_ idleMinutes: Int) async -> Void

    /// Default idle threshold — v2 ile uyumlu (15 dakika).
    public static let defaultThresholdSeconds: TimeInterval = 15 * 60

    /// Polling interval — saniyede 1 kez idle check fazla pahalı; 10s makul.
    public static let defaultPollIntervalSeconds: TimeInterval = 10

    /// **Sprint 38:** Production idle source — CGEventSource.
    public static let systemIdleSource: IdleSource = {
        // anyInput — keyboard + mouse + trackpad + tap dahil.
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInput
        )
    }

    private let idleSource: IdleSource
    private let thresholdSeconds: TimeInterval
    private let pollIntervalSeconds: TimeInterval
    private let onFire: FireCallback

    private var pollTask: Task<Void, Never>?
    private var hasFired: Bool = false

    public init(
        thresholdSeconds: TimeInterval = defaultThresholdSeconds,
        pollIntervalSeconds: TimeInterval = defaultPollIntervalSeconds,
        idleSource: @escaping IdleSource = systemIdleSource,
        onFire: @escaping FireCallback
    ) {
        self.thresholdSeconds = max(60, thresholdSeconds)  // min 1 dakika
        self.pollIntervalSeconds = max(1, pollIntervalSeconds)
        self.idleSource = idleSource
        self.onFire = onFire
    }

    /// **Sprint 38:** Polling başlat. Idempotent — mevcut task cancel edilir.
    public func start() {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = await self.pollIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// **Sprint 38:** Tek tick — idle süreyi kontrol et, threshold üstünde
    /// ve henüz fire etmemişse callback çağır. Public test'ler için (manual
    /// tick).
    public func tick() async {
        let idleSeconds = idleSource()
        if idleSeconds >= thresholdSeconds && !hasFired {
            hasFired = true
            let minutes = Int(idleSeconds / 60)
            await onFire(minutes)
        } else if idleSeconds < thresholdSeconds / 2 {
            // Kullanıcı tekrar aktif → fired flag reset, sonraki uzun idle
            // döngüsünde tekrar tetiklenebilir.
            hasFired = false
        }
    }

    /// Test için — fire state'ini görüntüle.
    public var isInFiredState: Bool { hasFired }
}
