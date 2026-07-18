import Foundation

/// WeatherService 对未来 24 小时天气的业务化摘要。
/// 概率和强度分开保存，避免把“很可能下小雨”误判成强降水。
struct HourlyWeatherSummary: Codable, Equatable, Identifiable {
    let date: Date
    let weatherCondition: String
    let precipitationChancePercent: Double
    let precipitationAmountMillimeters: Double?
    let snowfallAmountCentimeters: Double?
    let visibilityMeters: Double?
    let windGustKilometersPerHour: Double?

    init(
        date: Date,
        weatherCondition: String,
        precipitationChancePercent: Double,
        precipitationAmountMillimeters: Double? = nil,
        snowfallAmountCentimeters: Double? = nil,
        visibilityMeters: Double? = nil,
        windGustKilometersPerHour: Double? = nil
    ) {
        self.date = date
        self.weatherCondition = weatherCondition
        self.precipitationChancePercent = precipitationChancePercent
        self.precipitationAmountMillimeters = precipitationAmountMillimeters
        self.snowfallAmountCentimeters = snowfallAmountCentimeters
        self.visibilityMeters = visibilityMeters
        self.windGustKilometersPerHour = windGustKilometersPerHour
    }

    var id: Date {
        date
    }
}

struct MorningWeatherSummary: Codable, Equatable {
    let weatherCondition: String
    let precipitationChancePercent: Double
    let precipitationAmountMillimeters: Double?
    let windowStart: Date
    let windowEnd: Date
    let hourlyForecast: [HourlyWeatherSummary]?
    let fullHourlyForecast: [HourlyWeatherSummary]?

    init(
        weatherCondition: String,
        precipitationChancePercent: Double,
        precipitationAmountMillimeters: Double? = nil,
        windowStart: Date,
        windowEnd: Date,
        hourlyForecast: [HourlyWeatherSummary]? = nil,
        fullHourlyForecast: [HourlyWeatherSummary]? = nil
    ) {
        self.weatherCondition = weatherCondition
        self.precipitationChancePercent = precipitationChancePercent
        self.precipitationAmountMillimeters = precipitationAmountMillimeters
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.hourlyForecast = hourlyForecast
        self.fullHourlyForecast = fullHourlyForecast
    }

    /// 从完整小时预报中截取真正覆盖“准备出门到预计到达”的窗口。
    /// 没有路线时看 1 小时；有路线时额外留 30 分钟，并把窗口限制在 3 小时内。
    func focused(on departureDate: Date, travelDuration: TimeInterval?) -> MorningWeatherSummary {
        let duration = min(3 * 60 * 60, max(60 * 60, (travelDuration ?? 0) + 30 * 60))
        let endDate = departureDate.addingTimeInterval(duration)
        let source = fullHourlyForecast ?? hourlyForecast ?? []
        let focused = source.filter { sample in
            sample.date < endDate && sample.date.addingTimeInterval(60 * 60) > departureDate
        }

        guard !focused.isEmpty else {
            guard !source.isEmpty else {
                return self
            }
            return MorningWeatherSummary(
                weatherCondition: "天气待更新",
                precipitationChancePercent: 0,
                windowStart: departureDate,
                windowEnd: endDate,
                hourlyForecast: []
            )
        }

        let representative = focused.max { lhs, rhs in
            let lhsAmount = lhs.precipitationAmountMillimeters ?? -1
            let rhsAmount = rhs.precipitationAmountMillimeters ?? -1
            if lhsAmount == rhsAmount {
                return lhs.precipitationChancePercent < rhs.precipitationChancePercent
            }
            return lhsAmount < rhsAmount
        } ?? focused[0]

        return MorningWeatherSummary(
            weatherCondition: representative.weatherCondition,
            precipitationChancePercent: representative.precipitationChancePercent,
            precipitationAmountMillimeters: representative.precipitationAmountMillimeters,
            windowStart: departureDate,
            windowEnd: endDate,
            hourlyForecast: focused,
            fullHourlyForecast: fullHourlyForecast
        )
    }
}
