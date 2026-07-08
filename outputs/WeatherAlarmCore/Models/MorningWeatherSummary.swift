import Foundation

/// WeatherService 对未来 24 小时天气的业务化摘要。
///
/// `precipitationChancePercent` 使用 0...100 的百分比，方便直接套用
/// “> 30 提前 20 分钟、> 60 提前 40 分钟”的产品规则。
struct MorningWeatherSummary: Codable, Equatable {
    let weatherCondition: String
    let precipitationChancePercent: Double
    let windowStart: Date
    let windowEnd: Date
}

