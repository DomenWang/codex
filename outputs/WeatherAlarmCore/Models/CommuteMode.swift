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

    /// 雨雪对不同通勤方式的额外影响。
    ///
    /// 这不是天气 Mock，也不是路线 Mock。它只是在拿到真实 WeatherKit 降水概率、
    /// 真实高德路线距离后，根据出行方式估算“因为雨雪需要额外预留的分钟数”。
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
