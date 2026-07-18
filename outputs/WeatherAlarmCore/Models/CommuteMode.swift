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

    /// 地图 ETA 未覆盖的天气影响。概率已经在天气风险中作为可信度使用，不能再次判“强降水”。
    func residualWeatherImpactMinutes(
        distanceMeters: Double?,
        walkingDistanceMeters: Double?,
        plannedDurationSeconds: TimeInterval,
        weatherRisk: Double,
        hasTrafficAwareETA: Bool
    ) -> Int {
        let risk = min(1, max(0, weatherRisk))
        guard risk > 0 else {
            return 0
        }

        switch self {
        case .driving:
            guard !hasTrafficAwareETA else {
                return 0
            }
            let speedReduction = 0.02 + 0.14 * risk
            let extraSeconds = max(0, plannedDurationSeconds) * (1 / (1 - speedReduction) - 1)
            return min(40, Int(ceil(extraSeconds / 60)))
        case .transit:
            let exposedWalkingMinutes = max(0, walkingDistanceMeters ?? 0) / 80
            return min(8, Int(ceil(exposedWalkingMinutes * 0.35 * risk)))
        case .bicycling:
            return min(15, Int(ceil(max(0, plannedDurationSeconds) / 60 * 0.35 * risk)))
        case .walking:
            return min(8, Int(ceil(max(0, plannedDurationSeconds) / 60 * 0.20 * risk)))
        }
    }
}
