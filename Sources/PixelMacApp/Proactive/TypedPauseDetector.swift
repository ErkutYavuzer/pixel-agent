import AppKit
import Foundation

/// **Sprint 39 (v0.2.66):** Yazma duraksaması detektörü.
///
/// v2 (`ProactiveEngine.swift:245-280`) paterni:
/// Kullanıcı aktif yazıyordu (en az 2 ardışık poll'da keyDown gördük),
/// sonra 8-30 saniye keyDown gelmedi → "yazıp durdu" sinyali.
///
/// **Permission YOK** — `CGEventSource.secondsSinceLastEventType(.combinedSessionState,
/// eventType: .keyDown)` public API. CGEventTap'tan farklı: sadece "son keyDown'dan
/// beri ne kadar geçti" int değeri okur, event capture etmez.
///
/// State machine:
/// 1. `typingActiveStreak = 0` başlangıç.
/// 2. Her poll'da `keyDownSec < pollInterval` ise streak++, fire flag reset.
/// 3. Pause window: `keyDownSec ∈ [8, 30]` saniye + streak >= 2 → fire.
/// 4. `keyDownSec > 30` ise streak reset (kullanıcı başka şey yapıyor).
/// 5. Aynı bundle için per-fire dedup (`typedPauseFiredFor`).
public actor TypedPauseDetector {
    /// Mock'lanabilir keyDown idle süre kaynağı (saniye).
    public typealias KeyDownIdleSource = @Sendable () -> TimeInterval

    /// Mock'lanabilir frontmost app kaynağı (name, bundleID).
    public typealias FrontAppSource = @Sendable () -> (name: String, bundleID: String)?

    public typealias FireCallback = @Sendable (_ name: String, _ bundleID: String) async -> Void

    /// Default polling interval (saniye). v2 ile uyumlu.
    public static let defaultPollIntervalSeconds: TimeInterval = 5

    /// Pause window alt sınır (saniye).
    public static let pauseLowerBoundSeconds: TimeInterval = 8

    /// Pause window üst sınır (saniye). Daha eskisi "başka şey yapıyor".
    public static let pauseUpperBoundSeconds: TimeInterval = 30

    /// Minimum aktif streak — single tuş edit'lerini filter eder.
    public static let minActiveStreak: Int = 2

    /// Production keyDown idle source — CGEventSource.
    public static let systemKeyDownSource: KeyDownIdleSource = {
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .keyDown
        )
    }

    /// Production frontmost app source — NSWorkspace.
    @MainActor
    public static let systemFrontAppSource: FrontAppSource = {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return nil
        }
        return (name: app.localizedName ?? "Bilinmeyen", bundleID: bundleID)
    }

    private let pollIntervalSeconds: TimeInterval
    private let keyDownSource: KeyDownIdleSource
    private let frontAppSource: FrontAppSource
    private let onFire: FireCallback
    private let selfBundleID: String?

    private var pollTask: Task<Void, Never>?
    private var typingActiveStreak: Int = 0
    private var typedPauseFiredFor: String?

    public init(
        pollIntervalSeconds: TimeInterval = defaultPollIntervalSeconds,
        keyDownSource: @escaping KeyDownIdleSource = TypedPauseDetector.systemKeyDownSource,
        frontAppSource: @escaping FrontAppSource = { MainActor.assumeIsolated { TypedPauseDetector.systemFrontAppSource() } },
        selfBundleID: String? = Bundle.main.bundleIdentifier,
        onFire: @escaping FireCallback
    ) {
        self.pollIntervalSeconds = max(1, pollIntervalSeconds)
        self.keyDownSource = keyDownSource
        self.frontAppSource = frontAppSource
        self.selfBundleID = selfBundleID
        self.onFire = onFire
    }

    /// **Sprint 39:** Polling task başlat. Idempotent.
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

    /// **Sprint 39:** Tek tick — state machine'i ilerlet, koşul varsa fire.
    /// Public — test'lerde manuel tick.
    public func tick() async {
        let keyDownSec = keyDownSource()

        // Aktif yazma penceresi
        if keyDownSec < pollIntervalSeconds {
            typingActiveStreak &+= 1
            typedPauseFiredFor = nil  // Yeni yazma turu — eski fire flag clear
            return
        }

        // Çok uzun pause → streak reset
        if keyDownSec > Self.pauseUpperBoundSeconds {
            typingActiveStreak = 0
            return
        }

        // Pause window dışı (< 8s) → no-op, sonraki tick'i bekle
        guard keyDownSec >= Self.pauseLowerBoundSeconds else { return }

        // Yeterli aktif streak yok → filter (küçük edit)
        guard typingActiveStreak >= Self.minActiveStreak else { return }

        // Front app + self filter + per-bundle dedup
        guard let front = frontAppSource() else { return }
        if let selfBundleID, front.bundleID == selfBundleID { return }
        if typedPauseFiredFor == front.bundleID { return }

        typedPauseFiredFor = front.bundleID
        await onFire(front.name, front.bundleID)
    }

    /// Test için — internal state expose.
    public var snapshotActiveStreak: Int { typingActiveStreak }
    public var snapshotFiredFor: String? { typedPauseFiredFor }
}
