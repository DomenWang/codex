import Foundation

/// 最近一次真实天气/路况检查后的用户可见状态。
/// 这不是 Mock 数据；只有 WeatherKit、TransitService 或 AlarmKit 链路真实完成后才会写入。
struct WeatherAlarmStatus: Codable, Equatable {
    let generatedAt: Date
    let baseWakeUpDate: Date
    let scheduledWakeUpDate: Date
    let advanceMinutes: Int
    let weatherBufferMinutes: Int
    let commuteDelayMinutes: Int
    let weatherCondition: String
    let precipitationChancePercent: Double
    let alarmTitle: String?
    let alarmIconName: String?
    let alarmThemeIndex: Int?
    let repeatWeekdays: [Int]?
    let isWakeUpAlarm: Bool?

    init(
        generatedAt: Date,
        baseWakeUpDate: Date,
        scheduledWakeUpDate: Date,
        advanceMinutes: Int,
        weatherBufferMinutes: Int,
        commuteDelayMinutes: Int,
        weatherCondition: String,
        precipitationChancePercent: Double,
        alarmTitle: String? = nil,
        alarmIconName: String? = nil,
        alarmThemeIndex: Int? = nil,
        repeatWeekdays: [Int]? = nil,
        isWakeUpAlarm: Bool? = nil
    ) {
        self.generatedAt = generatedAt
        self.baseWakeUpDate = baseWakeUpDate
        self.scheduledWakeUpDate = scheduledWakeUpDate
        self.advanceMinutes = advanceMinutes
        self.weatherBufferMinutes = weatherBufferMinutes
        self.commuteDelayMinutes = commuteDelayMinutes
        self.weatherCondition = weatherCondition
        self.precipitationChancePercent = precipitationChancePercent
        self.alarmTitle = alarmTitle
        self.alarmIconName = alarmIconName
        self.alarmThemeIndex = alarmThemeIndex
        self.repeatWeekdays = repeatWeekdays
        self.isWakeUpAlarm = isWakeUpAlarm
    }

    var summaryText: String {
        if advanceMinutes > 0 {
            var reasons: [String] = []
            if weatherBufferMinutes > 0 {
                reasons.append("天气 \(weatherBufferMinutes) 分钟")
            }
            if commuteDelayMinutes > 0 {
                reasons.append("通勤 \(commuteDelayMinutes) 分钟")
            }

            let reasonText = reasons.isEmpty ? "" : "（\(reasons.joined(separator: "，"))）"
            return "明天\(weatherCondition)，将提前 \(advanceMinutes) 分钟响铃\(reasonText)"
        }

        return "明天\(weatherCondition)，当前未触发提前，按基础起床时间响铃"
    }

    var advanceSummaryText: String {
        advanceMinutes > 0 ? "提前 \(advanceMinutes) 分钟" : "不用提前"
    }

    func nextOccurrence(
        after now: Date,
        calendar: Calendar = .current
    ) -> WeatherAlarmStatus? {
        if scheduledWakeUpDate > now {
            return self
        }

        // AlarmKit only receives a repeating schedule when no smart advance is
        // applied. An adjusted alarm is a one-off occurrence and must not be
        // presented by the widget as if it were already scheduled next week.
        guard advanceMinutes == 0 else {
            return nil
        }

        let weekdays = Set((repeatWeekdays ?? []).filter { (1...7).contains($0) })
        guard !weekdays.isEmpty else {
            return nil
        }

        let time = calendar.dateComponents([.hour, .minute], from: baseWakeUpDate)
        let startOfToday = calendar.startOfDay(for: now)

        for dayOffset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let baseDate = calendar.date(
                    bySettingHour: time.hour ?? 0,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: day
                  ) else {
                continue
            }

            let scheduledDate = calendar.date(
                byAdding: .minute,
                value: -max(0, advanceMinutes),
                to: baseDate
            ) ?? baseDate.addingTimeInterval(TimeInterval(-max(0, advanceMinutes) * 60))

            guard scheduledDate > now else {
                continue
            }

            return WeatherAlarmStatus(
                generatedAt: generatedAt,
                baseWakeUpDate: baseDate,
                scheduledWakeUpDate: scheduledDate,
                advanceMinutes: advanceMinutes,
                weatherBufferMinutes: weatherBufferMinutes,
                commuteDelayMinutes: commuteDelayMinutes,
                weatherCondition: weatherCondition,
                precipitationChancePercent: precipitationChancePercent,
                alarmTitle: alarmTitle,
                alarmIconName: alarmIconName,
                alarmThemeIndex: alarmThemeIndex,
                repeatWeekdays: repeatWeekdays,
                isWakeUpAlarm: isWakeUpAlarm
            )
        }

        return nil
    }

    static func nextScheduled(
        from statuses: [WeatherAlarmStatus],
        after now: Date,
        calendar: Calendar = .current
    ) -> WeatherAlarmStatus? {
        statuses
            .compactMap { $0.nextOccurrence(after: now, calendar: calendar) }
            .min { $0.scheduledWakeUpDate < $1.scheduledWakeUpDate }
    }
}
