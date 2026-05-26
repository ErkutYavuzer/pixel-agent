import Foundation
import UserNotifications

/// **Sprint 40 (v0.2.67):** Proaktif notification tap handler.
///
/// `UNUserNotificationCenterDelegate` adapter — kullanıcı macOS notification'a
/// tıkladığında `userNotificationCenter(_:didReceive:withCompletionHandler:)`
/// callback'i tetiklenir. UserInfo dict'inden `ProactiveTrigger` decode edilir,
/// `ProactivePromptComposer` ile draft text üretilir,
/// `NotificationCenter.default` yayınlar (Pixel `.proactivePromptInject`).
///
/// `ChatView` / `DualChatHost` `.onReceive` ile dinler, current `ChatViewModel`'a
/// inject eder.
///
/// **`final class NSObject`** çünkü `UNUserNotificationCenterDelegate` Obj-C
/// protocol. Singleton instance — `RootView .task` register eder.
public final class NotificationActionDispatcher: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // **Sprint 40:** UNUserNotificationCenter.delegate Obj-C protocol için
    // class instance gerek. `@unchecked Sendable` — internal state mutable
    // değil (sadece NSObject + delegate); Swift 6 strict concurrency hatasını
    // belirgin yaparak kabul ediyoruz.
    public static let shared = NotificationActionDispatcher()

    /// **Sprint 40:** UserDefaults flag — kullanıcı opt-out edebilir.
    /// nil → default `true` (ON).
    public static let enabledDefaultsKey = "pixel.proactive.notificationInjectEnabled"

    public override init() { super.init() }

    /// **Sprint 40:** UNUserNotificationCenter delegate registration.
    /// `RootView .task` çağrısı. Idempotent.
    public func register() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// **Sprint 40:** Tap handler — kullanıcı bildirim üzerine tıkladığında
    /// veya "tıklayıp aç" eylemine basıldığında çağrılır.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        // Default action — kullanıcı bildirime tıkladı (banner / center).
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        // Opt-out kontrolü
        guard Self.isInjectEnabled() else { return }

        let raw = response.notification.request.content.userInfo
        guard let payload = Self.normalizePayload(raw) else { return }
        guard let trigger = ProactiveTrigger(userInfoPayload: payload) else { return }

        let draft = ProactivePromptComposer.prompt(for: trigger)
        Self.broadcast(draft: draft)
    }

    /// **Sprint 40:** App foreground iken bildirim gelirse — Mac'te
    /// `.banner` + `.sound` göster (default suppress edilirdi).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Helpers

    /// **Sprint 40:** `[AnyHashable: Any]` → `[String: String]` filtreli
    /// downcast. Test edilebilir + defensive.
    public static func normalizePayload(_ raw: [AnyHashable: Any]) -> [String: String]? {
        var out: [String: String] = [:]
        for (key, value) in raw {
            guard let strKey = key as? String, let strValue = value as? String else {
                continue
            }
            out[strKey] = strValue
        }
        return out.isEmpty ? nil : out
    }

    /// **Sprint 40:** UserDefaults toggle. nil → default true.
    public static func isInjectEnabled(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: enabledDefaultsKey) as? Bool {
            return stored
        }
        return true
    }

    /// **Sprint 40:** Draft inject Notification yayınla. ChatView .onReceive
    /// dinler ve composer field'ına yazar.
    public static func broadcast(draft: String) {
        NotificationCenter.default.post(
            name: .proactivePromptInject,
            object: nil,
            userInfo: ["draft": draft]
        )
    }
}

extension Notification.Name {
    /// **Sprint 40 (v0.2.67):** Proaktif notification tap → ChatView draft
    /// inject. `userInfo["draft"]: String`.
    public static let proactivePromptInject = Notification.Name("pixel.proactive.promptInject")
}
