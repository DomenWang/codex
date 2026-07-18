import AlarmKit
import Foundation

/// AlarmKit 会把 metadata 和系统闹钟关联起来。
///
/// 它适合存放 App 自己恢复 UI 或解释闹钟来源所需的轻量信息。
/// 不要在这里放 API Key、隐私敏感天气详情，或者任何可以从服务端重新获取的数据。
@available(iOS 26.0, *)
nonisolated struct WeatherAlarmMetadata: AlarmMetadata {
    let baseWakeUpDate: Date
    let scheduledWakeUpDate: Date
    let advanceMinutes: Int
    let weatherBufferMinutes: Int
    let commuteDelayMinutes: Int
    let weatherCondition: String
    let precipitationChancePercent: Double
    let alarmTitle: String
    let snoozeMinutes: Int
    let dismissChallenge: OrdinaryAlarmDismissChallenge
}
