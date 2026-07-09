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
        content.body = "到起床时间了。AlarmKit 不可用时，这是 App 的通知兜底。"
        content.sound = .default

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
}
