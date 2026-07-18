import Foundation
import UserNotifications

/// 当 StoreKit 临时查不到权益、但本地购买快照仍显示用户买过时，安排本地提醒。
///
/// 这不是权限判断来源；它只是给用户一个补救窗口，提醒打开 App 刷新购买状态。
@MainActor
final class PurchaseRestoreWarningNotifier {
    private let snapshotStore: PurchaseEntitlementSnapshotStore
    private let notificationCenter: UNUserNotificationCenter
    private let calendar: Calendar
    private let notificationIdentifier = "weatherwake.purchase.restore.warning"

    init(
        snapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore(),
        notificationCenter: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) {
        self.snapshotStore = snapshotStore
        self.notificationCenter = notificationCenter
        self.calendar = calendar
    }

    func scheduleIfNeeded(now: Date = Date()) async {
        guard snapshotStore.needsRestoreWarning else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            return
        }

        guard let warningDate = todayAt21IfStillUpcoming(now: now) else {
            return
        }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert])
            guard granted else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "SmartWake需要你打开一下"
            content.body = "智能闹钟权限可能需要刷新。今晚睡前打开 App 一次，明早会更稳。"
            content.sound = nil
            content.interruptionLevel = .passive

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: warningDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier,
                content: content,
                trigger: trigger
            )

            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
            try await notificationCenter.add(request)
        } catch {
            // 本地通知失败不影响后台闹钟兜底；后台仍然使用权限快照。
        }
    }

    private func todayAt21IfStillUpcoming(now: Date) -> Date? {
        guard let warningDate = calendar.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: now
        ) else {
            return nil
        }

        return warningDate > now ? warningDate : nil
    }
}
