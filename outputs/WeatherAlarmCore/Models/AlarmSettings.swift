import Foundation

/// 用户配置的“正常起床闹钟”。
///
/// 这里故意不提供默认起床时间，因为需求明确要求“不要写死闹钟时间”。
/// App 的设置页应在用户选择时间后，把这个模型保存到 `AlarmSettingsStore`。
struct AlarmSettings: Codable, Equatable {
    /// AlarmKit schedule 使用的稳定 ID。
    ///
    /// 同一个 ID 代表同一个业务闹钟。更新天气提前量时，用同一个 ID 重新 schedule，
    /// 系统就能把它当作同一个闹钟的更新，而不是每天创建一堆新闹钟。
    var alarmID: UUID

    /// 用户设置的正常起床时间，只保存时分，不保存日期。
    var wakeUpHour: Int
    var wakeUpMinute: Int

    /// 用户选择是否启用天气闹钟。
    var isEnabled: Bool

    /// 用户选择是否让地图/通勤耗时参与闹钟提前量。
    ///
    /// 旧版本数据没有这个字段时默认关闭，避免在用户未明确开启前使用通勤路线影响闹钟时间。
    var isCommuteAdjustmentEnabled: Bool?

    /// 可选通勤路线。
    ///
    /// 如果用户没有配置通勤路线，AlarmManager 会跳过 TransitService，
    /// 只使用天气逻辑。这里不写死任何起点/终点。
    var commuteRoute: CommuteRoute?

    /// 用户可配置的雨天提前规则。
    ///
    /// 旧版本数据没有这个字段时，业务层会使用 `WeatherAdjustmentSettings.default`。
    var weatherAdjustmentSettings: WeatherAdjustmentSettings?

    var effectiveWeatherAdjustmentSettings: WeatherAdjustmentSettings {
        weatherAdjustmentSettings ?? .default
    }

    var effectiveIsCommuteAdjustmentEnabled: Bool {
        isCommuteAdjustmentEnabled ?? false
    }

    /// 根据“今天/明天”的日期计算下一次基础起床时间。
    /// - Parameter now: 当前时间，默认使用系统当前时间。
    /// - Returns: 下一次用户设置的起床 Date。
    func nextBaseWakeUpDate(after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = wakeUpHour
        components.minute = wakeUpMinute
        components.second = 0

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }
}
