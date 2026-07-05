import AlarmKit
import Foundation
import SwiftUI

enum WeatherAlarmManagerError: LocalizedError {
    case authorizationDenied
    case alarmDisabled
    case cannotBuildBaseWakeUpDate

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "AlarmKit authorization was denied."
        case .alarmDisabled:
            return "The weather alarm is disabled by the user."
        case .cannotBuildBaseWakeUpDate:
            return "Could not build a wake-up date from stored settings."
        }
    }
}

/// App 层的 AlarmManager。
///
/// 名字按需求保留为 `AlarmManager`，因此访问系统框架类型时显式写
/// `AlarmKit.AlarmManager`，避免和本类混淆。
///
/// 重要边界：
/// AlarmKit 是 iOS 26 提供的系统闹钟框架，可以让本 App 创建、更新、停止
/// “由本 App 管理的系统级闹钟”。它不是私有 Clock API，不能修改用户已经在
/// Apple“时钟”App 里手动创建的任意闹钟。
@MainActor
@available(iOS 26.0, *)
final class AlarmManager {
    private let settingsStore: AlarmSettingsStore
    private let transitService: TransitService
    private let toastPresenter: ToastPresenting
    private let systemAlarmManager: AlarmKit.AlarmManager
    private let calendar: Calendar

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        transitService: TransitService? = nil,
        toastPresenter: ToastPresenting = NoopToastPresenter(),
        systemAlarmManager: AlarmKit.AlarmManager = .shared,
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.transitService = transitService ?? TransitService(
            baseDurationProvider: {
                let settings = try settingsStore.loadRequiredSettings()
                guard let baseDuration = settings.commuteRoute?.baseDurationSeconds,
                      baseDuration > 0 else {
                    throw TransitServiceError.missingBaseDuration
                }

                return baseDuration
            }
        )
        self.toastPresenter = toastPresenter
        self.systemAlarmManager = systemAlarmManager
        self.calendar = calendar
    }

    /// 请求 AlarmKit 授权。
    ///
    /// 第一次调用时，系统会弹出权限说明。请同时在 Info.plist 中填写：
    /// `NSAlarmKitUsageDescription`，例如“用于根据恶劣天气提前您的起床闹钟”。
    func requestAuthorization() async throws {
        let status = try await systemAlarmManager.requestAuthorization()

        guard status == .authorized else {
            throw WeatherAlarmManagerError.authorizationDenied
        }
    }

    /// 根据天气更新闹钟。
    ///
    /// - Parameters:
    ///   - weatherCondition: WeatherKit 返回的真实天气描述。
    ///   - precipitationChance: 0...100 的降水概率百分比。WeatherService 已经把 WeatherKit 的 0...1 转换为百分比。
    ///
    /// 产品规则：
    /// - 降水概率 > 60%，闹钟提前 40 分钟。
    /// - 降水概率 > 30%，闹钟提前 20 分钟。
    /// - 其他情况，不提前，仍按用户设置的真实起床时间 schedule。
    func updateAlarmBasedOnWeather(
        weatherCondition: String,
        precipitationChance: Double
    ) async throws {
        let settings = try settingsStore.loadRequiredSettings()

        guard settings.isEnabled else {
            throw WeatherAlarmManagerError.alarmDisabled
        }

        let baseWakeUpDate = settings.nextBaseWakeUpDate(calendar: calendar)
        guard let baseWakeUpDate else {
            throw WeatherAlarmManagerError.cannotBuildBaseWakeUpDate
        }

        let weatherBuffer: Int
        if precipitationChance > 60 {
            weatherBuffer = 40
        } else if precipitationChance > 30 {
            weatherBuffer = 20
        } else {
            weatherBuffer = 0
        }

        let commuteDelayMinutes = await calculateCommuteDelayMinutesIfPossible(
            from: settings.commuteRoute
        )

        // 合并算法：
        // 最终闹钟提前量 = (CommuteResult.realDuration - CommuteResult.baseDuration) / 60 + WeatherBuffer
        //
        // 如果实时通勤比基础通勤更短，提前量不能为负，因此通勤增量在 helper 中会被 clamp 到 0。
        let advanceMinutes = weatherBuffer + commuteDelayMinutes

        let scheduledWakeUpDate = calendar.date(
            byAdding: .minute,
            value: -advanceMinutes,
            to: baseWakeUpDate
        ) ?? baseWakeUpDate.addingTimeInterval(TimeInterval(-advanceMinutes * 60))

        try await scheduleWeatherAlarm(
            id: settings.alarmID,
            baseWakeUpDate: baseWakeUpDate,
            scheduledWakeUpDate: scheduledWakeUpDate,
            advanceMinutes: advanceMinutes,
            weatherBufferMinutes: weatherBuffer,
            commuteDelayMinutes: commuteDelayMinutes,
            weatherCondition: weatherCondition,
            precipitationChance: precipitationChance
        )
    }

    /// 使用 AlarmKit 真正创建或更新系统闹钟。
    ///
    /// AlarmKit 的核心调用是：
    /// `AlarmKit.AlarmManager.shared.schedule(id:configuration:)`
    ///
    /// - `id`：业务稳定 ID。传入同一个 UUID 可以更新同一个天气闹钟。
    /// - `configuration`：描述闹钟何时响、显示什么文案、携带什么 metadata。
    /// - `schedule`：这里使用固定时间点。它不是“延迟多少分钟后响”，而是明确告诉系统：
    ///   “请在 scheduledWakeUpDate 这个 Date 触发系统闹钟”。
    ///
    /// schedule 成功后，系统负责在锁屏、动态岛/实时活动等系统表面呈现闹钟。
    /// App 不需要，也不应该用本地通知去假装 AlarmKit 闹钟。
    private func scheduleWeatherAlarm(
        id: UUID,
        baseWakeUpDate: Date,
        scheduledWakeUpDate: Date,
        advanceMinutes: Int,
        weatherBufferMinutes: Int,
        commuteDelayMinutes: Int,
        weatherCondition: String,
        precipitationChance: Double
    ) async throws {
        let metadata = WeatherAlarmMetadata(
            baseWakeUpDate: baseWakeUpDate,
            scheduledWakeUpDate: scheduledWakeUpDate,
            advanceMinutes: advanceMinutes,
            weatherBufferMinutes: weatherBufferMinutes,
            commuteDelayMinutes: commuteDelayMinutes,
            weatherCondition: weatherCondition,
            precipitationChancePercent: precipitationChance
        )

        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle"
        )

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource("Weather Alarm"),
            stopButton: stopButton
        )

        let attributes = AlarmAttributes<WeatherAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: .blue
        )

        let schedule = Alarm.Schedule.fixed(scheduledWakeUpDate)

        typealias SystemAlarmConfiguration = AlarmKit.AlarmManager.AlarmConfiguration<WeatherAlarmMetadata>

        let configuration = SystemAlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes
        )

        _ = try await systemAlarmManager.schedule(
            id: id,
            configuration: configuration
        )
    }

    /// 调用 TransitService 计算路况导致的额外提前分钟数。
    ///
    /// 错误处理策略：
    /// - API Key 没配、网络超时、服务端失败、基础时长缺失等 TransitService 错误都在这里捕获。
    /// - 捕获后不阻断 AlarmKit schedule，直接返回 0，让闹钟退化为“仅天气逻辑”。
    /// - 同时通过 ToastPresenting 通知 UI 显示“路况检测失败”。
    ///
    /// View 不直接调用网络请求；它只负责监听 ToastMessageCenter 并展示 Toast。
    private func calculateCommuteDelayMinutesIfPossible(
        from commuteRoute: CommuteRoute?
    ) async -> Int {
        guard let commuteRoute else {
            // TODO: 在设置页提供通勤路线配置入口。未配置路线时，只使用天气逻辑。
            return 0
        }

        do {
            let commuteResult = try await transitService.calculateCommute(
                start: commuteRoute.startCoordinate,
                end: commuteRoute.endCoordinate
            )

            let delaySeconds = max(
                0,
                commuteResult.realDuration - commuteResult.baseDuration
            )

            return Int(ceil(delaySeconds / 60))
        } catch {
            toastPresenter.showToast("路况检测失败")
            return 0
        }
    }
}
