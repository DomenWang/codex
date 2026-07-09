import Foundation

enum CommuteMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case driving
    case transit
    case bicycling
    case walking

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .driving:
            return "驾车"
        case .transit:
            return "公共交通"
        case .bicycling:
            return "骑行"
        case .walking:
            return "步行"
        }
    }

    /// 根据真实 WeatherKit 降水概率和高德返回的真实路线距离，估算雨雪对不同出行方式的额外影响。
    /// 这不是天气或路线 Mock，只是业务规则。
    func weatherImpactMinutes(
        distanceMeters: Double?,
        weatherCondition: String,
        precipitationChancePercent: Double
    ) -> Int {
        guard precipitationChancePercent > 30 else {
            return 0
        }

        let isHeavy = precipitationChancePercent > 60
        let isSnow = weatherCondition.localizedCaseInsensitiveContains("snow") ||
            weatherCondition.contains("雪")
        let distanceKilometers = max(0, (distanceMeters ?? 0) / 1000)

        switch self {
        case .driving:
            return isHeavy || isSnow ? 5 : 0
        case .transit:
            return isHeavy || isSnow ? 10 : 5
        case .bicycling:
            let minutesPerKilometer = isHeavy || isSnow ? 5.0 : 2.0
            return Int(ceil(distanceKilometers * minutesPerKilometer))
        case .walking:
            let minutesPerKilometer = isHeavy || isSnow ? 7.0 : 4.0
            return Int(ceil(distanceKilometers * minutesPerKilometer))
        }
    }
}
