import AppKit
import ApplicationServices
import Foundation

/// **Sprint 39 (v0.2.66):** Aynı pencerede uzun süre kalma detektörü.
///
/// v2 (`ProactiveEngine.swift:214-243`) paterni:
/// Her poll'da frontmost app + AX window title oku → "key" değişmediyse
/// dwell counter artır. Threshold (default 15 dk) aşılırsa fire.
///
/// **Permission:** `AXIsProcessTrusted()` true olmalı (Accessibility izni
/// System Settings → Privacy & Security → Accessibility). Permission yoksa
/// title boş kalır, dwell sadece bundle ID üzerinden takip edilir.
///
/// State:
/// - `currentWindowKey: String` — "\(bundleID)|\(title)" format
/// - `currentWindowDwell: TimeInterval` — bu key'te geçirilen süre
/// - `dwellFiredForCurrentWindow: Bool` — per-window dedup
public actor WindowDwellDetector {
    /// Mock'lanabilir frontmost window info kaynağı.
    public typealias WindowSource = @Sendable () -> WindowInfo?

    public struct WindowInfo: Sendable, Equatable {
        public let appName: String
        public let bundleID: String
        public let title: String  // Boş olabilir (permission yok)

        public init(appName: String, bundleID: String, title: String) {
            self.appName = appName
            self.bundleID = bundleID
            self.title = title
        }
    }

    public typealias FireCallback = @Sendable (
        _ name: String,
        _ bundleID: String,
        _ title: String,
        _ minutes: Int
    ) async -> Void

    /// Default dwell threshold (saniye) — v2 ile uyumlu 15 dakika.
    public static let defaultThresholdSeconds: TimeInterval = 15 * 60

    /// Polling interval (saniye).
    public static let defaultPollIntervalSeconds: TimeInterval = 30

    /// **Sprint 39:** Production window source — NSWorkspace + AX bridge.
    /// Accessibility permission yoksa title boş.
    @MainActor
    public static func systemWindowInfo() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            return nil
        }
        let name = app.localizedName ?? "Bilinmeyen"
        let title = Self.frontmostWindowTitle(pid: app.processIdentifier) ?? ""
        return WindowInfo(appName: name, bundleID: bundleID, title: title)
    }

    /// **Sprint 39:** AX ile aktif pencere başlığı — permission yoksa nil.
    /// v2 paterninin direkt eşi.
    @MainActor
    private static func frontmostWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        guard status == .success,
              let raw = focusedWindow,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(raw, to: AXUIElement.self)
        var titleRef: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleStatus == .success, let title = titleRef as? String else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private let thresholdSeconds: TimeInterval
    private let pollIntervalSeconds: TimeInterval
    private let windowSource: WindowSource
    private let onFire: FireCallback
    private let selfBundleID: String?

    private var pollTask: Task<Void, Never>?
    private var currentWindowKey: String = ""
    private var currentWindowDwell: TimeInterval = 0
    private var dwellFiredForCurrentWindow: Bool = false

    public init(
        thresholdSeconds: TimeInterval = defaultThresholdSeconds,
        pollIntervalSeconds: TimeInterval = defaultPollIntervalSeconds,
        windowSource: @escaping WindowSource = {
            MainActor.assumeIsolated { WindowDwellDetector.systemWindowInfo() }
        },
        selfBundleID: String? = Bundle.main.bundleIdentifier,
        onFire: @escaping FireCallback
    ) {
        self.thresholdSeconds = max(60, thresholdSeconds)
        self.pollIntervalSeconds = max(1, pollIntervalSeconds)
        self.windowSource = windowSource
        self.selfBundleID = selfBundleID
        self.onFire = onFire
    }

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

    /// **Sprint 39:** Tek tick — key değişimi check + dwell artır veya reset.
    public func tick() async {
        guard let info = windowSource() else {
            resetDwell()
            return
        }
        // Self filter
        if let selfBundleID, info.bundleID == selfBundleID {
            resetDwell()
            return
        }

        let key = "\(info.bundleID)|\(info.title)"
        if key == currentWindowKey {
            currentWindowDwell += pollIntervalSeconds
        } else {
            currentWindowKey = key
            currentWindowDwell = 0
            dwellFiredForCurrentWindow = false
        }

        guard currentWindowDwell >= thresholdSeconds,
              !dwellFiredForCurrentWindow else { return }

        dwellFiredForCurrentWindow = true
        let minutes = Int(currentWindowDwell / 60)
        await onFire(info.appName, info.bundleID, info.title, minutes)
    }

    private func resetDwell() {
        currentWindowKey = ""
        currentWindowDwell = 0
        dwellFiredForCurrentWindow = false
    }

    /// Test için — internal state.
    public var snapshotDwellSeconds: TimeInterval { currentWindowDwell }
    public var snapshotFired: Bool { dwellFiredForCurrentWindow }
}
