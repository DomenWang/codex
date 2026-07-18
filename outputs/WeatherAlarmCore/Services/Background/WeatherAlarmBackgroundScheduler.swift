import BackgroundTasks
import CoreLocation
import Foundation
import UIKit

/// BGTask 的 expirationHandler 与正常任务链可能同时结束，系统只允许完成一次。
/// 这个小型门闩让两个执行路径竞争同一个 O(1) 原子状态，避免重复完成导致未定义行为。
private final class BackgroundTaskCompletionGate: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var isCompleted = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        lock.unlock()

        task.setTaskCompleted(success: success)
    }
}

enum WeatherAlarmBackgroundError: LocalizedError {
    case missingLocation

    var errorDescription: String? {
        switch self {
        case .missingLocation:
            return "还没有拿到真实定位，后台刷新不会用固定位置代替。"
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
    private static var isRegistered = false

    private let weatherService: WeatherService
    private let alarmManager: AlarmManager
    private let settingsStore: AlarmSettingsStore
    private let entitlementSnapshotStore: PurchaseEntitlementSnapshotStore
    private let weatherCacheStore: WeatherSummaryCacheStore
    private let locationProvider: () async throws -> CLLocation
    private let calendar: Calendar

    init(
        weatherService: WeatherService = WeatherService(),
        alarmManager: AlarmManager? = nil,
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        entitlementSnapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore(),
        weatherCacheStore: WeatherSummaryCacheStore = WeatherSummaryCacheStore(),
        calendar: Calendar = .current,
        locationProvider: @escaping () async throws -> CLLocation
    ) {
        self.weatherService = weatherService
        self.alarmManager = alarmManager ?? AlarmManager()
        self.settingsStore = settingsStore
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
        guard !Self.isRegistered else {
            return
        }

        Self.isRegistered = BGTaskScheduler.shared.register(
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
    /// 这里同时纳入“开启智能功能的闹钟响前 1 小时”作为候选刷新点。
    /// BGAppRefreshTask 只能声明最早开始时间，系统不保证精确执行。
    func scheduleNextDaily5AMRefresh(from now: Date = Date()) throws {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextRefreshDate(after: now)

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
        let completionGate = BackgroundTaskCompletionGate(task: task)
        let refreshTask = Task {
            do {
                try scheduleNextDaily5AMRefresh()

                try await alarmManager.ensureBasicAlarmRegistered()

                guard entitlementSnapshotStore.canUseWeather || entitlementSnapshotStore.canUseGaode else {
                    completionGate.complete(success: true)
                    return
                }

                guard let settings = try? settingsStore.loadSettings() else {
                    completionGate.complete(success: true)
                    return
                }

                let now = Date()
                let needsWeather = hasAnyWeatherEnabledAlarm(settings)
                let summary = needsWeather && entitlementSnapshotStore.canUseWeather
                    ? await fetchFreshWeatherSummaryOrCached()
                    : nil
                await rescheduleAllSmartAlarms(
                    settings: settings,
                    with: summary,
                    excludingAlarmsDueSoonAt: now
                )
                await rescheduleSmartAlarmsDueSoon(
                    settings: settings,
                    fallbackSummary: summary,
                    now: now
                )
                completionGate.complete(success: true)
            } catch {
                // 基础闹钟注册失败时才把任务标记为失败。WeatherKit / 路线刷新失败会走缓存或跳过，
                // 不会阻断基础闹钟。
                completionGate.complete(success: false)
            }
        }

        task.expirationHandler = {
            refreshTask.cancel()
            completionGate.complete(success: false)
            Task { [weak self] in
                try? await self?.alarmManager.ensureBasicAlarmRegistered()
            }
        }
    }

    private func rescheduleAllSmartAlarms(
        settings: AlarmSettings,
        with summary: MorningWeatherSummary?,
        excludingAlarmsDueSoonAt now: Date
    ) async {
        let wakeBaseDate = settings.nextBaseWakeUpDate(after: now, calendar: calendar)
        let wakeIsDueSoon = wakeBaseDate.map { shouldRecheckAlarm(baseDate: $0, now: now) } == true
        if settings.effectiveIsWakeUpAlarmEnabled,
           settings.isEnabled,
           !wakeIsDueSoon,
           let summary {
            try? await alarmManager.updateAlarmBasedOnWeather(
                weatherSummary: summary
            )
        } else if settings.effectiveIsWakeUpAlarmEnabled,
                  !wakeIsDueSoon,
                  settings.effectiveIsCommuteAdjustmentEnabled {
            try? await alarmManager.updateAlarmBasedOnWeather(
                weatherSummary: nil
            )
        }

        for alarm in settings.effectiveOrdinaryAlarms where alarm.effectiveIsEnabled && alarm.usesSmartTiming {
            if let baseDate = alarm.nextBaseWakeUpDate(after: now, calendar: calendar),
               shouldRecheckAlarm(baseDate: baseDate, now: now) {
                continue
            }
            try? await alarmManager.scheduleOrdinaryAlarm(
                alarm,
                weatherSummary: alarm.isWeatherAdjustmentEnabled ? summary : nil
            )
        }
    }

    private func rescheduleSmartAlarmsDueSoon(
        settings: AlarmSettings,
        fallbackSummary: MorningWeatherSummary?,
        now: Date
    ) async {
        let wakeBaseDate = settings.nextBaseWakeUpDate(after: now, calendar: calendar)
        let wakeNeedsWeather = settings.effectiveIsWakeUpAlarmEnabled
            && settings.isEnabled
            && wakeBaseDate.map { shouldRecheckAlarm(baseDate: $0, now: now) } == true
        let ordinaryNeedsWeather = settings.effectiveOrdinaryAlarms.contains { alarm in
            guard alarm.effectiveIsEnabled,
                  alarm.isWeatherAdjustmentEnabled,
                  let baseDate = alarm.nextBaseWakeUpDate(after: now, calendar: calendar) else {
                return false
            }
            return shouldRecheckAlarm(baseDate: baseDate, now: now)
        }
        let location = (wakeNeedsWeather || ordinaryNeedsWeather) ? try? await locationProvider() : nil

        if settings.effectiveIsWakeUpAlarmEnabled,
           (settings.isEnabled || settings.effectiveIsCommuteAdjustmentEnabled),
           let baseDate = wakeBaseDate,
           shouldRecheckAlarm(baseDate: baseDate, now: now) {
            let targetSummary: MorningWeatherSummary? = if settings.isEnabled, let location {
                await fetchTargetWeatherSummary(for: baseDate, location: location)
            } else {
                nil
            }
            if settings.isEnabled,
               let summary = targetSummary ?? fallbackSummary {
                try? await alarmManager.updateAlarmBasedOnWeather(
                    weatherSummary: summary
                )
            } else if settings.effectiveIsCommuteAdjustmentEnabled {
                try? await alarmManager.updateAlarmBasedOnWeather(
                    weatherSummary: nil
                )
            }
        }

        for alarm in settings.effectiveOrdinaryAlarms where alarm.effectiveIsEnabled && alarm.usesSmartTiming {
            guard let baseDate = alarm.nextBaseWakeUpDate(after: now, calendar: calendar),
                  shouldRecheckAlarm(baseDate: baseDate, now: now) else {
                continue
            }

            let targetSummary: MorningWeatherSummary? = if alarm.isWeatherAdjustmentEnabled, let location {
                await fetchTargetWeatherSummary(for: baseDate, location: location)
            } else {
                nil
            }
            if alarm.isWeatherAdjustmentEnabled,
               let summary = targetSummary ?? fallbackSummary {
                try? await alarmManager.scheduleOrdinaryAlarm(
                    alarm,
                    weatherSummary: summary
                )
            } else if alarm.isCommuteAdjustmentEnabled {
                try? await alarmManager.scheduleOrdinaryAlarm(
                    alarm,
                    weatherSummary: nil
                )
            }
        }
    }

    private func hasAnyWeatherEnabledAlarm(_ settings: AlarmSettings) -> Bool {
        (settings.effectiveIsWakeUpAlarmEnabled && settings.isEnabled) || settings.effectiveOrdinaryAlarms.contains {
            $0.effectiveIsEnabled && $0.isWeatherAdjustmentEnabled
        }
    }

    private func fetchTargetWeatherSummary(for baseDate: Date, location: CLLocation) async -> MorningWeatherSummary? {
        let windowEnd = calendar.date(byAdding: .hour, value: 1, to: baseDate) ?? baseDate.addingTimeInterval(60 * 60)
        do {
            return try await weatherService.fetchPrecipitationSummary(
                for: location,
                windowStart: baseDate,
                windowEnd: windowEnd
            )
        } catch {
            return weatherCacheStore.loadValidSummary()
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

    private func nextRefreshDate(after now: Date) -> Date {
        let dailyRefreshDate = next5AM(after: now)
        let eveningReadinessDate = next10PM(after: now)
        let fixedRefreshDate = min(dailyRefreshDate, eveningReadinessDate)
        guard let smartAlarmRefreshDate = nextSmartAlarmRefreshDate(after: now) else {
            return fixedRefreshDate
        }

        return min(fixedRefreshDate, smartAlarmRefreshDate)
    }

    private func nextSmartAlarmRefreshDate(after now: Date) -> Date? {
        guard let settings = try? settingsStore.loadSettings() else {
            return nil
        }

        var candidates: [Date] = []
        if settings.effectiveIsWakeUpAlarmEnabled,
           settings.isEnabled || settings.effectiveIsCommuteAdjustmentEnabled,
           let baseDate = settings.nextBaseWakeUpDate(after: now, calendar: calendar),
           let refreshDate = refreshDate(for: baseDate, now: now) {
            candidates.append(refreshDate)
        }

        for alarm in settings.effectiveOrdinaryAlarms where alarm.effectiveIsEnabled && alarm.usesSmartTiming {
            guard let baseDate = alarm.nextBaseWakeUpDate(after: now, calendar: calendar) else {
                continue
            }

            if let refreshDate = refreshDate(for: baseDate, now: now) {
                candidates.append(refreshDate)
            }
        }

        return candidates.min()
    }

    private func refreshDate(for baseDate: Date, now: Date) -> Date? {
        let desiredDate = calendar.date(byAdding: .hour, value: -1, to: baseDate) ?? baseDate.addingTimeInterval(-60 * 60)
        guard desiredDate > now.addingTimeInterval(60) else {
            return nil
        }

        return desiredDate
    }

    private func shouldRecheckAlarm(baseDate: Date, now: Date) -> Bool {
        let recheckStartDate = calendar.date(byAdding: .hour, value: -1, to: baseDate) ?? baseDate.addingTimeInterval(-60 * 60)
        let recheckEndDate = calendar.date(byAdding: .minute, value: 15, to: baseDate) ?? baseDate.addingTimeInterval(15 * 60)
        return now >= recheckStartDate && now <= recheckEndDate
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

    private func next10PM(after now: Date) -> Date {
        var components = DateComponents()
        components.hour = 22
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
