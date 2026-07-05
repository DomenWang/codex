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
/// 但 iOS 不保证精确 03:00 执行；`earliestBeginDate` 表示“最早可以开始”，
/// 实际唤醒时间由系统根据电量、网络、用户使用习惯等因素决定。
@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmBackgroundScheduler {
    static let taskIdentifier = "com.domenwang.weatheralarm.daily-weather-refresh"

    private let weatherService: WeatherService
    private let alarmManager: AlarmManager
    private let locationProvider: () async throws -> CLLocation
    private let calendar: Calendar

    init(
        weatherService: WeatherService = WeatherService(),
        alarmManager: AlarmManager = AlarmManager(),
        calendar: Calendar = .current,
        locationProvider: @escaping () async throws -> CLLocation
    ) {
        self.weatherService = weatherService
        self.alarmManager = alarmManager
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

    /// 提交下一次每日凌晨 3 点的刷新请求。
    ///
    /// 这不是硬编码“闹钟时间”；它只是后台天气检查的最早运行时间。
    /// 真正的用户闹钟时间仍然来自 AlarmSettingsStore。
    func scheduleNextDaily3AMRefresh(from now: Date = Date()) throws {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = next3AM(after: now)

        try BGTaskScheduler.shared.submit(request)
    }

    /// 处理 BGAppRefreshTask。
    ///
    /// 任务链路：
    /// 1. 先安排下一次 03:00 后台刷新，防止本次任务结束后忘记续约。
    /// 2. 获取真实用户位置。
    /// 3. 使用 WeatherKit 拉取未来 24 小时小时级天气。
    /// 4. 解析 6:00-9:00 降水概率。
    /// 5. 调用 AlarmManager 通过 AlarmKit schedule 更新系统闹钟。
    private func handle(_ task: BGAppRefreshTask) {
        let refreshTask = Task {
            do {
                try scheduleNextDaily3AMRefresh()

                let location = try await locationProvider()
                let summary = try await weatherService.fetchMorningPrecipitationSummary(for: location)

                try await alarmManager.updateAlarmBasedOnWeather(
                    weatherCondition: summary.weatherCondition,
                    precipitationChance: summary.precipitationChancePercent
                )

                task.setTaskCompleted(success: true)
            } catch {
                // 真实项目中建议把 error 写入持久化日志，供设置页展示最近一次后台检查失败原因。
                // 不要在这里用假天气或固定闹钟时间兜底；失败时保持现有闹钟不变更安全。
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private func next3AM(after now: Date) -> Date {
        var components = DateComponents()
        components.hour = 3
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
