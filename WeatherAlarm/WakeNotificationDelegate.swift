import Foundation
import UserNotifications

final class WakeNotificationDelegate: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let wakeAlarmCategoryIdentifier = "smartwake.wake_alarm"
    static let snoozeActionIdentifier = "smartwake.action.snooze"
    static let stopActionIdentifier = "smartwake.action.stop"

    static func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "再睡5分钟",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier,
            title: "停止",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: wakeAlarmCategoryIdentifier,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.snoozeActionIdentifier else {
            return
        }

        try? await LocalWakeNotificationScheduler().scheduleSnoozeNotification(afterMinutes: 5)
    }
}
