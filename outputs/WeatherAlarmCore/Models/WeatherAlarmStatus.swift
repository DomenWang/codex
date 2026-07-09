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

    var summaryText: String {
        if advanceMinutes > 0 {
            return "明天\(weatherCondition)，将提前 \(advanceMinutes) 分钟响铃"
        }

        return "明天\(weatherCondition)，按基础起床时间响铃"
    }
}
