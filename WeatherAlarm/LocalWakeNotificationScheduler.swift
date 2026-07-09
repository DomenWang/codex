import Foundation
import UserNotifications

enum LocalWakeNotificationSchedulerError: LocalizedError {
    case notificationAuthorizationDenied

    var errorDescription: String? {
        switch self {
        case .notificationAuthorizationDenied:
            return "Notification authorization was denied."
        }
    }
}

final class LocalWakeNotificationScheduler {
    private enum Identifiers {
        static let fallbackWakeAlarm = "smartwake.local.fallback_wake_alarm"
        static let snoozeWakeAlarm = "smartwake.local.snooze_wake_alarm"
        static let testWakeAlarm = "smartwake.local.test_wake_alarm"
    }

    private let settingsStore: AlarmSettingsStore
    private let notificationCenter: UNUserNotificationCenter

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
    }

    /// AlarmKit 失败时的真实本地通知兜底。
    ///
    /// 这不会伪装成系统闹钟，也不能修改 Apple 时钟 App 里的闹钟。
    /// 每次用户更改起床时间时，先删除旧的本地通知，再创建新的每日通知。
    func rescheduleFallbackWakeNotification() async throws {
        let settings = try settingsStore.loadRequiredSettings()
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw LocalWakeNotificationSchedulerError.notificationAuthorizationDenied
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifiers.fallbackWakeAlarm])

        var dateComponents = DateComponents()
        dateComponents.hour = settings.wakeUpHour
        dateComponents.minute = settings.wakeUpMinute

        let content = UNMutableNotificationContent()
        content.title = "SmartWake 起床提醒"
        content.body = "到起床时间了。可以停止，也可以再睡5分钟。"
        content.sound = .default
        content.categoryIdentifier = WakeNotificationDelegate.wakeAlarmCategoryIdentifier

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: Identifiers.fallbackWakeAlarm,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    func scheduleSnoozeNotification(afterMinutes minutes: Int) async throws {
        try await scheduleOneOffNotification(
            identifier: Identifiers.snoozeWakeAlarm,
            title: "SmartWake 贪睡提醒",
            body: "5分钟到了，该起床了。",
            after: TimeInterval(minutes * 60)
        )
    }

    func scheduleTestNotification(afterSeconds seconds: TimeInterval = 5) async throws {
        try await scheduleOneOffNotification(
            identifier: Identifiers.testWakeAlarm,
            title: "SmartWake 试响",
            body: "这是闹钟功能测试。正式闹钟会按你设置的时间提醒。",
            after: seconds
        )
    }

    private func scheduleOneOffNotification(
        identifier: String,
        title: String,
        body: String,
        after interval: TimeInterval
    ) async throws {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw LocalWakeNotificationSchedulerError.notificationAuthorizationDenied
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = WakeNotificationDelegate.wakeAlarmCategoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, interval),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }
}
