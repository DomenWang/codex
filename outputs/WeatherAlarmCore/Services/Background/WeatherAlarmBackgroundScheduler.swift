import BackgroundTasks
import CoreLocation
import Foundation
import UIKit

enum WeatherAlarmBackgroundError: LocalizedError {
    case missingLocation

    var errorDescription: String? {
        switch self {
        case .missingLocation:
            return "Missing a real user location for WeatherKit. Background refresh will not use a hard-coded location."
        }
    }
}

/// 后台任务调度器：负责注册、提交、处理每日天气检查。
///
/// 使用 BGAppRefreshTask 的原因是：这个任务适合“短时间刷新数据并更新状态”的场景。
/// 但 iOS 不保证精确 05:00 执行；`earliestBeginDate` 表示“最早可以开始”，
/// 实际唤醒时间由系统根据电量、网络、用户使用习惯等因素决定。
@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmBackgroundScheduler {
    static let taskIdentifier = "com.domenx.SmartWake.daily-weather-refresh"

    private let weatherService: WeatherService
    private let alarmManager: AlarmManager
    private let entitlementSnapshotStore: PurchaseEntitlementSnapshotStore
    private let weatherCacheStore: WeatherSummaryCacheStore
    private let locationProvider: () async throws -> CLLocation
    private let calendar: Calendar

    init(
        weatherService: WeatherService = WeatherService(),
        alarmManager: AlarmManager? = nil,
        entitlementSnapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore(),
        weatherCacheStore: WeatherSummaryCacheStore = WeatherSummaryCacheStore(),
        calendar: Calendar = .current,
        locationProvider: @escaping () async throws -> CLLocation
    ) {
        self.weatherService = weatherService
        self.alarmManager = alarmManager ?? AlarmManager()
        self.entitlementSnapshotStore = entitlementSnapshotStore
        self.weatherCacheStore = weatherCacheStore
        self.calendar = calendar
        self.locationProvider = locationProvider
    }

    /// 在 App 启动阶段注册后台任务。
    ///
    /// 建议从 SwiftUI App 的 init 或 AppDelegate 的
    /// `application(_:didFinishLaunchingWithOptions:)` 中调用。
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            self.handle(refreshTask)
        }
    }

    /// 提交下一次每日凌晨 5 点的刷新请求。
    ///
    /// 这不是硬编码“闹钟时间”；它只是后台天气检查的最早运行时间。
    /// 真正的用户闹钟时间仍然来自 AlarmSettingsStore。
    func scheduleNextDaily5AMRefresh(from now: Date = Date()) throws {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = next5AM(after: now)

        try BGTaskScheduler.shared.submit(request)
    }

    /// 处理 BGAppRefreshTask。
    ///
    /// 任务链路：
    /// 1. 先安排下一次 05:00 后台刷新，防止本次任务结束后忘记续约。
    /// 2. 获取真实用户位置。
    /// 3. 使用 WeatherKit 拉取未来 24 小时小时级天气。
    /// 4. 解析 6:00-9:00 降水概率。
    /// 5. 调用 AlarmManager 通过 AlarmKit schedule 更新系统闹钟。
    private func handle(_ task: BGAppRefreshTask) {
        let refreshTask = Task {
            do {
                try scheduleNextDaily5AMRefresh()

                try await alarmManager.ensureBasicAlarmRegistered()

                guard entitlementSnapshotStore.canUseWeather else {
                    task.setTaskCompleted(success: true)
                    return
                }

                let summary = await fetchFreshWeatherSummaryOrCached()
                guard let summary else {
                    task.setTaskCompleted(success: true)
                    return
                }

                do {
                    try await alarmManager.updateAlarmBasedOnWeather(
                        weatherCondition: summary.weatherCondition,
                        precipitationChance: summary.precipitationChancePercent
                    )
                } catch WeatherAlarmManagerError.alarmDisabled {
                    task.setTaskCompleted(success: true)
                    return
                }

                task.setTaskCompleted(success: true)
            } catch {
                // 基础闹钟注册失败时才把任务标记为失败。WeatherKit / 高德失败会走缓存或跳过，
                // 不会阻断基础闹钟。
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
            Task { [weak self] in
                try? await self?.alarmManager.ensureBasicAlarmRegistered()
                task.setTaskCompleted(success: false)
            }
        }
    }

    private func fetchFreshWeatherSummaryOrCached() async -> MorningWeatherSummary? {
        do {
            let location = try await locationProvider()
            let summary = try await weatherService.fetchMorningPrecipitationSummary(for: location)
            weatherCacheStore.save(summary)
            return summary
        } catch {
            return weatherCacheStore.loadValidSummary()
        }
    }

    private func next5AM(after now: Date) -> Date {
        var components = DateComponents()
        components.hour = 5
        components.minute = 0
        components.second = 0

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now.addingTimeInterval(24 * 60 * 60)
    }
}
