import Foundation
import UserNotifications

/// Local notifications only (no APNs/server). Used for sitter-side walk alerts that can
/// fire while the app is backgrounded on the tracking device.
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private var firedIdentifiers = Set<String>()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Fire a local notification once per identifier (deduped for the app session).
    func scheduleLocalAlert(title: String, body: String, identifier: String) {
        guard !firedIdentifiers.contains(identifier) else { return }
        firedIdentifiers.insert(identifier)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Allow an alert to fire again (e.g. when a new walk starts).
    func reset(identifier: String) {
        firedIdentifiers.remove(identifier)
    }
}
