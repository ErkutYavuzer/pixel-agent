import AppKit
import Foundation

/// **Sprint 38 (v0.2.65):** Frontmost uygulama değişimini izleyen actor.
///
/// `NSWorkspace.didActivateApplicationNotification` notification'unu dinler.
/// Her aktivasyon callback'i tetikler — debounce caller tarafında
/// (`ProactiveEngine` rate limiter ile + per-bundle son aktivasyon
/// zamanı kontrolü).
///
/// **Permission YOK** — NSWorkspace public API.
///
/// **Filter:** kendi pixel-agent uygulamamızın aktivasyonu callback'i
/// tetiklemez (her ⌘Tab focus dönüşünde gereksiz spam).
public actor AppChangeObserver {
    public typealias FireCallback = @Sendable (_ name: String, _ bundleID: String) async -> Void

    private let onFire: FireCallback
    private let selfBundleID: String?
    private var observer: NSObjectProtocol?

    /// Per-bundle son fire timestamp — kullanıcı ⌘Tab ile aynı uygulama
    /// arasında oynarken her saniye fire olmasın. Default 60 saniye debounce
    /// per bundle.
    private var lastFiredByBundle: [String: Date] = [:]
    public static let defaultBundleDebounceSeconds: TimeInterval = 60
    private let bundleDebounceSeconds: TimeInterval

    public init(
        bundleDebounceSeconds: TimeInterval = defaultBundleDebounceSeconds,
        selfBundleID: String? = Bundle.main.bundleIdentifier,
        onFire: @escaping FireCallback
    ) {
        self.bundleDebounceSeconds = max(0, bundleDebounceSeconds)
        self.selfBundleID = selfBundleID
        self.onFire = onFire
    }

    /// **Sprint 38:** Observer kayıt. Idempotent. `Notification` Sendable
    /// değildir; closure içinde sync olarak `name`/`bundleID` çıkarıp Task'a
    /// Sendable primitive olarak geçer.
    public func start() {
        stop()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            // Notification'dan Sendable primitives extract et (queue: .main = sync).
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundle = app.bundleIdentifier else {
                return
            }
            let name = app.localizedName ?? "Bilinmeyen"
            Task { await self.handle(name: name, bundleID: bundle) }
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    /// **Sprint 38:** Public test/manual entry point.
    public func handle(name: String, bundleID: String, now: Date = Date()) async {
        // Kendi app'imizin aktivasyonunu ignore et.
        if let selfBundleID, bundleID == selfBundleID { return }

        // Per-bundle debounce
        if let last = lastFiredByBundle[bundleID],
           now.timeIntervalSince(last) < bundleDebounceSeconds {
            return
        }
        lastFiredByBundle[bundleID] = now
        await onFire(name, bundleID)
    }

    /// Test için — son fire timestamp'ı bundle başına.
    public var snapshotLastFired: [String: Date] { lastFiredByBundle }
}
