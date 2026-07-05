import Foundation

/// 用户可配置的天气提前规则。
///
/// 默认规则延续现有产品逻辑：
/// - 降水概率 > 30%，提前 20 分钟。
/// - 降水概率 > 60%，提前 40 分钟。
///
/// 这里是“规则设置”，不是 Mock 天气数据。实际是否提前仍由 WeatherKit 的真实降水概率决定。
struct WeatherAdjustmentSettings: Codable, Equatable {
    var rainThresholdPercent: Double
    var heavyRainThresholdPercent: Double
    var rainAdvanceMinutes: Int
    var heavyRainAdvanceMinutes: Int

    static let `default` = WeatherAdjustmentSettings(
        rainThresholdPercent: 30,
        heavyRainThresholdPercent: 60,
        rainAdvanceMinutes: 20,
        heavyRainAdvanceMinutes: 40
    )

    func weatherBufferMinutes(
        weatherCondition: String,
        precipitationChancePercent: Double
    ) -> Int {
        guard precipitationChancePercent > rainThresholdPercent else {
            return 0
        }

        if precipitationChancePercent > heavyRainThresholdPercent {
            return heavyRainAdvanceMinutes
        }

        return rainAdvanceMinutes
    }
}

