import Foundation
import UserNotifications

/// Schedules a local notification at the next session-reset moment.
enum NotificationManager {
    static let resetNotificationId = "claudeSessionReset"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    static func scheduleResetNotification(at date: Date?,
                                          enabled: Bool,
                                          soundName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [resetNotificationId])

        guard enabled, let date, date > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Session Reset"
        content.body = "Your 5-hour usage window just refreshed."
        if soundName == "default" {
            content.sound = .default
        } else if !soundName.isEmpty {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        }

        let interval = max(1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: resetNotificationId, content: content, trigger: trigger)

        center.add(request) { error in
            if let error { print("Schedule error: \(error)") }
        }
    }
}
