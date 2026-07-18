import Foundation

/// 保留旧版本的四个可配置字段，实际判断改为“强度决定危害、概率只表示可信度”。
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

    func weatherAdvance(for summary: MorningWeatherSummary?) -> WeatherAdvanceComponents {
        WeatherRiskCalculator.calculate(summary: summary, settings: self)
    }

    /// 兼容旧调用点。缺少雨强时，无论概率多高，普通降雨最多提前 10 分钟。
    func weatherBufferMinutes(
        weatherCondition: String,
        precipitationChancePercent: Double
    ) -> Int {
        let now = Date()
        let sample = HourlyWeatherSummary(
            date: now,
            weatherCondition: weatherCondition,
            precipitationChancePercent: precipitationChancePercent
        )
        let summary = MorningWeatherSummary(
            weatherCondition: weatherCondition,
            precipitationChancePercent: precipitationChancePercent,
            windowStart: now,
            windowEnd: now.addingTimeInterval(60 * 60),
            hourlyForecast: [sample]
        )
        return weatherAdvance(for: summary).totalMinutes
    }
}

struct WeatherAdvanceComponents: Equatable {
    let risk: Double
    let preparationMinutes: Int
    let genericTravelMinutes: Int
    let totalMinutes: Int

    static let zero = WeatherAdvanceComponents(
        risk: 0,
        preparationMinutes: 0,
        genericTravelMinutes: 0,
        totalMinutes: 0
    )
}

struct SmartAdvanceDecision: Equatable {
    let totalMinutes: Int
    let weatherMinutes: Int
    let routeMinutes: Int

    static let zero = SmartAdvanceDecision(totalMinutes: 0, weatherMinutes: 0, routeMinutes: 0)

    func capped(to maximumMinutes: Int) -> SmartAdvanceDecision {
        let cappedTotal = max(0, min(totalMinutes, maximumMinutes))
        guard cappedTotal < totalMinutes else {
            return self
        }

        let cappedWeather = min(weatherMinutes, cappedTotal)
        return SmartAdvanceDecision(
            totalMinutes: cappedTotal,
            weatherMinutes: cappedWeather,
            routeMinutes: max(0, cappedTotal - cappedWeather)
        )
    }
}

enum SmartAdvanceCalculator {
    /// 路线可用时，天气的通用旅途缓冲被地图 ETA/历史可靠性替代，只保留准备和暴露段影响。
    static func calculate(
        weatherEnabled: Bool,
        routeAvailable: Bool,
        weather: WeatherAdvanceComponents,
        routeDelayMinutes: Int,
        residualWeatherMinutes: Int,
        arrivalAdvanceMinutes: Int,
        maximumAutomaticAdvanceMinutes: Int = 60
    ) -> SmartAdvanceDecision {
        let weatherAdvance = weatherEnabled ? weather : .zero
        let routeDelay = max(0, routeDelayMinutes)
        let residual = max(0, residualWeatherMinutes)
        let arrival = max(0, arrivalAdvanceMinutes)

        let rawTotal: Int
        let rawWeather: Int
        if routeAvailable {
            let routeCandidate = (weatherEnabled ? weatherAdvance.preparationMinutes : 0)
                + routeDelay
                + residual
            let weatherCandidate = weatherEnabled ? weatherAdvance.totalMinutes : 0
            rawTotal = max(weatherCandidate, max(routeCandidate, arrival))
            rawWeather = weatherCandidate >= routeCandidate && weatherCandidate >= arrival
                ? weatherCandidate
                : (weatherEnabled ? weatherAdvance.preparationMinutes : 0)
        } else {
            rawWeather = weatherAdvance.totalMinutes
            rawTotal = rawWeather
        }

        let roundedTotal = min(maximumAutomaticAdvanceMinutes, roundUpToFive(rawTotal))
        let displayedWeather = min(rawWeather, roundedTotal)
        return SmartAdvanceDecision(
            totalMinutes: roundedTotal,
            weatherMinutes: displayedWeather,
            routeMinutes: max(0, roundedTotal - displayedWeather)
        )
    }

    private static func roundUpToFive(_ minutes: Int) -> Int {
        guard minutes > 0 else {
            return 0
        }
        return ((minutes + 4) / 5) * 5
    }
}

private enum WeatherRiskCalculator {
    static func calculate(
        summary: MorningWeatherSummary?,
        settings: WeatherAdjustmentSettings
    ) -> WeatherAdvanceComponents {
        guard let summary else {
            return .zero
        }

        let samples = summary.hourlyForecast?.isEmpty == false
            ? summary.hourlyForecast ?? []
            : [HourlyWeatherSummary(
                date: summary.windowStart,
                weatherCondition: summary.weatherCondition,
                precipitationChancePercent: summary.precipitationChancePercent,
                precipitationAmountMillimeters: summary.precipitationAmountMillimeters
            )]
        guard !samples.isEmpty else {
            return .zero
        }

        var maximumRisk = 0.0
        var weightedRisk = 0.0
        var totalWeight = 0.0
        var hasObjectiveHazardData = false

        for sample in samples {
            let sampleStart = sample.date
            let sampleEnd = sample.date.addingTimeInterval(60 * 60)
            let overlapStart = max(sampleStart, summary.windowStart)
            let overlapEnd = min(sampleEnd, summary.windowEnd)
            let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
            guard overlap > 0 else {
                continue
            }

            let risk = sampleRisk(sample)
            maximumRisk = max(maximumRisk, risk)
            weightedRisk += risk * overlap
            totalWeight += overlap
            hasObjectiveHazardData = hasObjectiveHazardData
                || sample.precipitationAmountMillimeters != nil
                || sample.snowfallAmountCentimeters != nil
                || (sample.visibilityMeters ?? .greatestFiniteMagnitude) < 5_000
                || (sample.windGustKilometersPerHour ?? 0) > 30
                || containsSevereWeather(sample.weatherCondition)
        }

        guard totalWeight > 0 else {
            return .zero
        }

        let meanRisk = weightedRisk / totalWeight
        let windowRisk = clamp(0.7 * maximumRisk + 0.3 * meanRisk)
        let configuredRainMinutes = max(0, settings.rainAdvanceMinutes)
        let configuredHeavyMinutes = max(configuredRainMinutes, settings.heavyRainAdvanceMinutes)
        let rawMinutes: Double
        if windowRisk <= 0.5 {
            rawMinutes = 2 * windowRisk * Double(configuredRainMinutes)
        } else {
            rawMinutes = Double(configuredRainMinutes)
                + 2 * (windowRisk - 0.5) * Double(configuredHeavyMinutes - configuredRainMinutes)
        }

        var totalMinutes = roundUpToFive(Int(ceil(rawMinutes)))
        totalMinutes = min(configuredHeavyMinutes, totalMinutes)
        if !hasObjectiveHazardData {
            totalMinutes = min(10, totalMinutes)
        }

        let preparationMinutes = min(8, Int((Double(totalMinutes) * 0.2).rounded()))
        return WeatherAdvanceComponents(
            risk: windowRisk,
            preparationMinutes: preparationMinutes,
            genericTravelMinutes: max(0, totalMinutes - preparationMinutes),
            totalMinutes: totalMinutes
        )
    }

    private static func sampleRisk(_ sample: HourlyWeatherSummary) -> Double {
        let probability = clamp(sample.precipitationChancePercent / 100)
        let hasForecastAmount = (sample.precipitationAmountMillimeters ?? 0) > 0
            || (sample.snowfallAmountCentimeters ?? 0) > 0
        let confidence = sqrt(max(probability, hasForecastAmount ? 0.25 : 0))

        let precipitationRisk: Double
        if let amount = sample.precipitationAmountMillimeters {
            precipitationRisk = interpolatedHazard(
                max(0, amount),
                anchors: [(0, 0), (0.1, 0.05), (2.5, 0.25), (7.6, 0.55), (20, 1)]
            ) * confidence
        } else if containsWetWeather(sample.weatherCondition) {
            precipitationRisk = 0.25 * sqrt(probability)
        } else {
            precipitationRisk = 0
        }

        let snowRisk = sample.snowfallAmountCentimeters.map {
            interpolatedHazard(max(0, $0), anchors: [(0, 0), (0.1, 0.15), (1, 0.5), (3, 1)]) * confidence
        } ?? 0
        let visibilityRisk = sample.visibilityMeters.map {
            interpolatedHazard(
                max(0, 5_000 - $0),
                anchors: [(0, 0), (2_000, 0.2), (4_000, 0.6), (4_800, 1)]
            )
        } ?? 0
        let windRisk = sample.windGustKilometersPerHour.map {
            interpolatedHazard(max(0, $0), anchors: [(0, 0), (30, 0), (40, 0.2), (60, 0.5), (80, 0.8), (100, 1)])
        } ?? 0
        let conditionFloor = containsSevereWeather(sample.weatherCondition)
            ? 0.55 * sqrt(max(probability, 0.5))
            : 0

        return clamp(max(precipitationRisk, snowRisk, visibilityRisk, windRisk, conditionFloor))
    }

    private static func interpolatedHazard(
        _ value: Double,
        anchors: [(value: Double, risk: Double)]
    ) -> Double {
        guard let first = anchors.first, let last = anchors.last else {
            return 0
        }
        if value <= first.value { return first.risk }
        if value >= last.value { return last.risk }

        for index in 1..<anchors.count {
            let lower = anchors[index - 1]
            let upper = anchors[index]
            guard value <= upper.value else { continue }
            let fraction = (value - lower.value) / (upper.value - lower.value)
            return lower.risk + fraction * (upper.risk - lower.risk)
        }
        return last.risk
    }

    private static func containsWetWeather(_ condition: String) -> Bool {
        let text = condition.lowercased()
        return ["rain", "drizzle", "shower", "snow", "sleet", "雨", "雪", "冰雹"].contains {
            text.contains($0)
        }
    }

    private static func containsSevereWeather(_ condition: String) -> Bool {
        let text = condition.lowercased()
        return ["heavy", "thunder", "storm", "强降水", "暴雨", "雷", "风暴"].contains {
            text.contains($0)
        }
    }

    private static func roundUpToFive(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return ((minutes + 4) / 5) * 5
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
