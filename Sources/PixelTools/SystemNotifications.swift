import Foundation
import UserNotifications

public enum SystemNotifications {
    /// `UNUserNotificationCenter` yalnızca bundle'lı app context'inde çalışır.
    /// `swift run` ile çalıştırıldığında Bundle.main.bundleIdentifier nil olur — skip.
    private static var isBundledApp: Bool {
        Bundle.main.bundleIdentifier != nil
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
        guard isBundledApp else { return }
        let content = buildContent(title: title, body: body)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    public static func buildContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }
}
