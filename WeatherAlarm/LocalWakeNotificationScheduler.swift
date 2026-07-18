import Foundation
import UserNotifications

enum SmartWakeEngagementPolicy {
    static let meaningfulAdjustmentMinutes = 5
    static let adjustmentNotificationCooldown: TimeInterval = 60 * 60
    static let dismissedOfferOpenThreshold = 3
    static let expiredOfferOpenThreshold = 5
    static let standardOfferDuration: TimeInterval = 5 * 60
    static let postPurchaseOfferDuration: TimeInterval = 10 * 60
    static let offerReappearanceCooldown: TimeInterval = 7 * 24 * 60 * 60
    static let maximumAutomaticOfferReappearances = 2

    static func isEveningPreparationWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        (19..<22).contains(calendar.component(.hour, from: date))
    }

    static func shouldNotifyAdjustment(
        previousMinutes: Int?,
        currentMinutes: Int,
        lastNotificationDate: Date?,
        now: Date
    ) -> Bool {
        guard previousMinutes != currentMinutes else {
            return false
        }

        let isStateTransition = previousMinutes == nil
            || (previousMinutes == 0) != (currentMinutes == 0)
        if isStateTransition {
            return true
        }

        guard let previousMinutes,
              abs(previousMinutes - currentMinutes) >= meaningfulAdjustmentMinutes else {
            return false
        }

        guard let lastNotificationDate else {
            return true
        }

        return now.timeIntervalSince(lastNotificationDate) >= adjustmentNotificationCooldown
    }

    static func canShowAutomaticOfferReappearance(
        previousReappearanceCount: Int,
        eligibleAt: Date?,
        now: Date
    ) -> Bool {
        previousReappearanceCount < maximumAutomaticOfferReappearances
            && eligibleAt.map { $0 <= now } == true
    }
}

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
        static let autoSavedOrdinaryAlarmPrefix = "smartwake.local.auto_saved_ordinary_alarm."
        static let eveningRainPreparation = "smartwake.local.evening_rain_preparation"
        static let alarmAdjustmentPrefix = "smartwake.local.alarm_adjustment."
        static let weatherUpgradeReminder = "smartwake.local.weather_upgrade_reminder"
    }

    private enum StateKeys {
        static let eveningRainDay = "smartwake.notification.evening_rain_day"
        static let weatherUpgradeNextScheduleDate = "smartwake.notification.weather_upgrade_next_schedule_date"

        static func adjustmentMinutes(alarmID: UUID) -> String {
            "smartwake.notification.adjustment_minutes.\(alarmID.uuidString)"
        }

        static func adjustmentNotificationDate(alarmID: UUID) -> String {
            "smartwake.notification.adjustment_last_date.\(alarmID.uuidString)"
        }
    }

    private let settingsStore: AlarmSettingsStore
    private let notificationCenter: UNUserNotificationCenter
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let entitlementSnapshotStore: PurchaseEntitlementSnapshotStore

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        notificationCenter: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = AppGroupUserDefaults.shared,
        calendar: Calendar = .current,
        entitlementSnapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore()
    ) {
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
        self.calendar = calendar
        self.entitlementSnapshotStore = entitlementSnapshotStore
    }

    /// AlarmKit 失败时的真实本地通知兜底。
    ///
    /// 这不会伪装成系统闹钟，也不能修改 Apple 时钟 App 里的闹钟。
    /// 每次用户更改起床时间时，先删除旧的本地通知，再创建新的每日通知。
    func rescheduleFallbackWakeNotification() async throws {
        let settings = try settingsStore.loadRequiredSettings()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifiers.fallbackWakeAlarm])

        guard settings.effectiveIsWakeUpAlarmEnabled else {
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [Identifiers.fallbackWakeAlarm])
            return
        }

        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw LocalWakeNotificationSchedulerError.notificationAuthorizationDenied
        }

        let now = Date()
        let statusDate = WeatherAlarmStatusStore().loadLatestStatus()?.scheduledWakeUpDate
        let nextDate: Date
        if let statusDate, statusDate > now.addingTimeInterval(5) {
            nextDate = statusDate
        } else if let baseDate = settings.nextBaseWakeUpDate(after: now, calendar: calendar) {
            nextDate = baseDate
        } else {
            throw LocalWakeNotificationSchedulerError.notificationAuthorizationDenied
        }
        let dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nextDate
        )

        let content = UNMutableNotificationContent()
        content.title = "SmartWake 起床提醒"
        content.body = "到起床时间了。可以停止，也可以再睡5分钟。"
        content.sound = .default
        content.categoryIdentifier = WakeNotificationDelegate.wakeAlarmCategoryIdentifier

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: Identifiers.fallbackWakeAlarm,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    func cancelFallbackWakeNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifiers.fallbackWakeAlarm])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Identifiers.fallbackWakeAlarm])
    }

    func scheduleSnoozeNotification(afterMinutes minutes: Int) async throws {
        try await scheduleOneOffNotification(
            identifier: Identifiers.snoozeWakeAlarm,
            title: "SmartWake 贪睡提醒",
            body: "5分钟到了，该起床了。",
            after: TimeInterval(minutes * 60),
            categoryIdentifier: WakeNotificationDelegate.wakeAlarmCategoryIdentifier
        )
    }

    func scheduleTestNotification(afterSeconds seconds: TimeInterval = 5) async throws {
        try await scheduleOneOffNotification(
            identifier: Identifiers.testWakeAlarm,
            title: "SmartWake 试响",
            body: "这是闹钟功能测试。正式闹钟会按你设置的时间提醒。",
            after: seconds,
            categoryIdentifier: WakeNotificationDelegate.wakeAlarmCategoryIdentifier
        )
    }

    func scheduleAutoSavedOrdinaryAlarmNotification(
        alarmID: UUID,
        title: String,
        timeText: String
    ) async throws {
        try await scheduleOneOffNotification(
            identifier: Identifiers.autoSavedOrdinaryAlarmPrefix + alarmID.uuidString,
            title: "已自动保存闹钟",
            body: "\(timeText) 的 \(title) 没有编辑完，我先给你保存了 \(timeText) 的闹钟。",
            after: 1,
            categoryIdentifier: nil,
            playsSound: false
        )
    }

    func notifyRainPreparationIfNeeded(
        alarmTitle: String,
        status: WeatherAlarmStatus,
        now: Date = Date()
    ) async {
        guard entitlementSnapshotStore.canUseWeather else {
            return
        }

        guard SmartWakeEngagementPolicy.isEveningPreparationWindow(now, calendar: calendar),
              status.weatherBufferMinutes > 0,
              status.advanceMinutes > 0,
              await notificationsAreAuthorized() else {
            return
        }

        let day = dayKey(for: now)
        guard userDefaults.string(forKey: StateKeys.eveningRainDay) != day else {
            return
        }

        await addImmediateNotification(
            identifier: Identifiers.eveningRainPreparation,
            title: "明早有雨，今晚早点休息",
            body: "\(alarmTitle)会提前 \(status.advanceMinutes) 分钟响，雨天的从容从今晚多睡一会儿开始。"
        )
        userDefaults.set(day, forKey: StateKeys.eveningRainDay)
    }

    func notifyAlarmAdjustmentIfChanged(
        alarmID: UUID,
        alarmTitle: String,
        baseWakeUpDate: Date,
        advanceMinutes: Int,
        weatherBufferMinutes: Int,
        commuteDelayMinutes: Int
    ) async {
        guard entitlementSnapshotStore.canUseWeather || entitlementSnapshotStore.canUseGaode else {
            return
        }

        let minutesKey = StateKeys.adjustmentMinutes(alarmID: alarmID)
        let previousMinutes = userDefaults.object(forKey: minutesKey) as? Int

        userDefaults.set(advanceMinutes, forKey: minutesKey)

        let notificationDateKey = StateKeys.adjustmentNotificationDate(alarmID: alarmID)
        let lastNotificationDate = userDefaults.object(forKey: notificationDateKey) as? Date
        let now = Date()
        guard SmartWakeEngagementPolicy.shouldNotifyAdjustment(
            previousMinutes: previousMinutes,
            currentMinutes: advanceMinutes,
            lastNotificationDate: lastNotificationDate,
            now: now
        ),
              await notificationsAreAuthorized() else {
            return
        }

        let title: String
        let body: String
        if advanceMinutes > 0 {
            var reasons: [String] = []
            if weatherBufferMinutes > 0 {
                reasons.append("天气")
            }
            if commuteDelayMinutes > 0 {
                reasons.append("路况")
            }
            let reasonText = reasons.isEmpty ? "最新情况" : reasons.joined(separator: "和")
            title = "\(alarmTitle)已提前 \(advanceMinutes) 分钟"
            body = "根据\(reasonText)重新安排好了，预计 \(timeText(baseWakeUpDate.addingTimeInterval(TimeInterval(-advanceMinutes * 60)))) 响铃。"
        } else if let previousMinutes, previousMinutes > 0 {
            title = "\(alarmTitle)不用提前了"
            body = "最新情况已经好转，将恢复在 \(timeText(baseWakeUpDate)) 响铃。"
        } else {
            return
        }

        await addImmediateNotification(
            identifier: Identifiers.alarmAdjustmentPrefix + alarmID.uuidString,
            title: title,
            body: body
        )
        userDefaults.set(now, forKey: notificationDateKey)
    }

    func removePaidFeatureNotifications() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        let pendingIDs = pending.map(\.identifier).filter(isPaidFeatureNotificationIdentifier)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingIDs)

        let delivered = await notificationCenter.deliveredNotifications()
        let deliveredIDs = delivered.map { $0.request.identifier }.filter(isPaidFeatureNotificationIdentifier)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        userDefaults.removeObject(forKey: StateKeys.eveningRainDay)
    }

    func removeWeatherUpgradeReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Identifiers.weatherUpgradeReminder])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [Identifiers.weatherUpgradeReminder])
        userDefaults.removeObject(forKey: StateKeys.weatherUpgradeNextScheduleDate)
    }

    private func scheduleOneOffNotification(
        identifier: String,
        title: String,
        body: String,
        after interval: TimeInterval,
        categoryIdentifier: String? = nil,
        playsSound: Bool = true
    ) async throws {
        let authorizationOptions: UNAuthorizationOptions = playsSound ? [.alert, .sound] : [.alert]
        let granted = try await notificationCenter.requestAuthorization(options: authorizationOptions)
        guard granted else {
            throw LocalWakeNotificationSchedulerError.notificationAuthorizationDenied
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playsSound ? .default : nil
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

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

    private func notificationsAreAuthorized() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func addImmediateNotification(identifier: String, title: String, body: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await notificationCenter.add(request)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func timeText(_ date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func isPaidFeatureNotificationIdentifier(_ identifier: String) -> Bool {
        identifier == Identifiers.eveningRainPreparation
            || identifier.hasPrefix(Identifiers.alarmAdjustmentPrefix)
    }
}
