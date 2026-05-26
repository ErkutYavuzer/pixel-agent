import Foundation
import UserNotifications

public enum SystemNotifications {
    /// `UNUserNotificationCenter` yalnızca `.app` paketi (CFBundlePackageType=APPL)
    /// kontekstinde çalışır. `swift run` ve xctest'te `bundleProxyForCurrentProcess`
    /// hatası fırlatır — skip.
    ///
    /// `bundleIdentifier != nil` kontrolü yetersiz: xctest binary'sinin de
    /// bundleIdentifier'ı vardır (`com.apple.dt.xctest.tool`) ama .app paketi
    /// değildir. Uzantı kontrolü ile gerçek app context'i ayırırız.
    private static var isBundledApp: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return Bundle.main.bundleURL.pathExtension == "app"
    }

    public static func requestAuthorization() async -> Bool {
        guard isBundledApp else { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    public static func post(
        title: String,
        body: String,
        identifier: String = UUID().uuidString
    ) async {
        await post(title: title, body: body, userInfo: [:], identifier: identifier)
    }

    /// **Sprint 40 (v0.2.67):** `userInfo` parametresi ile notification post.
    /// `UNNotificationResponse.notification.request.content.userInfo`
    /// üzerinden delegate `didReceive` callback'inde okunabilir.
    /// Caller `Sendable`-friendly `[String: String]` dict geçer; method
    /// içeride `[AnyHashable: Any]` formatına yükseltir.
    public static func post(
        title: String,
        body: String,
        userInfo: [String: String],
        identifier: String = UUID().uuidString
    ) async {
        guard isBundledApp else { return }
        let content = buildContent(title: title, body: body, userInfo: userInfo)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    public static func buildContent(title: String, body: String, userInfo: [String: String] = [:]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !userInfo.isEmpty {
            content.userInfo = userInfo  // [AnyHashable: Any] upcast
        }
        return content
    }
}
