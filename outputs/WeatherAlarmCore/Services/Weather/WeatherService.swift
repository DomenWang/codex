import CoreLocation
import Foundation
import WeatherKit

enum WeatherServiceError: LocalizedError {
    case missingMorningWindow
    case noHourlyForecastForMorningWindow
    case openMeteoMissingHourlyData

    var errorDescription: String? {
        switch self {
        case .missingMorningWindow:
            return "暂时无法计算明早的天气时间段。"
        case .noHourlyForecastForMorningWindow:
            return "暂时没有拿到明早小时级天气。"
        case .openMeteoMissingHourlyData:
            return "暂时没有拿到可用的小时级天气数据。"
        }
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let precipitationProbability: [Double]?
        let precipitation: [Double]?
        let snowfall: [Double]?
        let visibility: [Double]?
        let windGusts: [Double]?
        let weatherCode: [Int]?

        enum CodingKeys: String, CodingKey {
            case time
            case precipitationProbability = "precipitation_probability"
            case precipitation
            case snowfall
            case visibility
            case windGusts = "wind_gusts_10m"
            case weatherCode = "weather_code"
        }
    }
}

private struct HourlyWeatherSample {
    let date: Date
    let weatherCondition: String
    let precipitationChancePercent: Double
    let precipitationAmountMillimeters: Double?
    let snowfallAmountCentimeters: Double?
    let visibilityMeters: Double?
    let windGustKilometersPerHour: Double?

    var summary: HourlyWeatherSummary {
        HourlyWeatherSummary(
            date: date,
            weatherCondition: weatherCondition,
            precipitationChancePercent: precipitationChancePercent,
            precipitationAmountMillimeters: precipitationAmountMillimeters,
            snowfallAmountCentimeters: snowfallAmountCentimeters,
            visibilityMeters: visibilityMeters,
            windGustKilometersPerHour: windGustKilometersPerHour
        )
    }
}

/// 真实 WeatherKit 服务。
///
/// 这里没有任何 Mock 数据，也不会在 WeatherKit 失败时伪造成功结果。
/// 调用失败会直接 throw，让后台任务记录失败并保持闹钟不变。
final class WeatherService {
    private let appleWeatherService: WeatherKit.WeatherService
    private let calendar: Calendar

    init(
        appleWeatherService: WeatherKit.WeatherService = .shared,
        calendar: Calendar = .current
    ) {
        self.appleWeatherService = appleWeatherService
        self.calendar = calendar
    }

    /// 拉取未来 24 小时天气，并解析下一段早晨 6:00-9:00 的降水概率。
    ///
    /// - Parameter location: 用户真实位置。不要传固定经纬度来假装测试成功。
    /// - Returns: 6:00-9:00 小时预报中的最高降水概率，以及对应天气描述。
    func fetchMorningPrecipitationSummary(
        for location: CLLocation,
        now: Date = Date()
    ) async throws -> MorningWeatherSummary {
        let startDate = now
        let endDate = calendar.date(byAdding: .hour, value: 24, to: startDate) ?? startDate.addingTimeInterval(24 * 60 * 60)

        let morningWindow = try nextMorningWindowWithin24Hours(after: now)

        return try await fetchPrecipitationSummary(
            for: location,
            windowStart: morningWindow.start,
            windowEnd: morningWindow.end,
            forecastStart: startDate,
            forecastEnd: endDate
        )
    }

    func fetchPrecipitationSummary(
        for location: CLLocation,
        windowStart: Date,
        windowEnd: Date,
        forecastStart: Date? = nil,
        forecastEnd: Date? = nil
    ) async throws -> MorningWeatherSummary {
        let startDate = forecastStart ?? max(Date(), calendar.date(byAdding: .hour, value: -1, to: windowStart) ?? windowStart)
        let endDate = forecastEnd ?? calendar.date(byAdding: .hour, value: 24, to: windowEnd) ?? windowEnd.addingTimeInterval(24 * 60 * 60)

        do {
            let weather = try await appleWeatherService.weather(
                for: location,
                including: .hourly(startDate: startDate, endDate: endDate)
            )

            let fullForecast = weather.forecast.compactMap { hourWeather -> HourlyWeatherSample? in
                guard hourWeather.date >= startDate && hourWeather.date < endDate else {
                    return nil
                }

                return HourlyWeatherSample(
                    date: hourWeather.date,
                    weatherCondition: hourWeather.condition.description,
                    precipitationChancePercent: hourWeather.precipitationChance * 100,
                    precipitationAmountMillimeters: hourWeather.precipitationAmount.converted(to: .millimeters).value,
                    snowfallAmountCentimeters: hourWeather.snowfallAmount.converted(to: .centimeters).value,
                    visibilityMeters: hourWeather.visibility.converted(to: .meters).value,
                    windGustKilometersPerHour: hourWeather.wind.gust?.converted(to: .kilometersPerHour).value
                )
            }
            let windowForecast = fullForecast.filter {
                $0.date >= windowStart && $0.date < windowEnd
            }

            guard !windowForecast.isEmpty else {
                throw WeatherServiceError.noHourlyForecastForMorningWindow
            }

            let wettestHour = Self.mostSignificantSample(in: windowForecast)

            guard let wettestHour else {
                throw WeatherServiceError.noHourlyForecastForMorningWindow
            }

            return MorningWeatherSummary(
                weatherCondition: wettestHour.weatherCondition,
                precipitationChancePercent: wettestHour.precipitationChancePercent,
                precipitationAmountMillimeters: wettestHour.precipitationAmountMillimeters,
                windowStart: windowStart,
                windowEnd: windowEnd,
                hourlyForecast: windowForecast.map(\.summary),
                fullHourlyForecast: fullForecast.map(\.summary)
            )
        } catch {
            return try await fetchOpenMeteoMorningSummary(
                for: location,
                windowStart: windowStart,
                windowEnd: windowEnd,
                forecastStart: startDate,
                forecastEnd: endDate
            )
        }
    }

    /// WeatherKit 失败时的真实天气降级方案。
    ///
    /// 这不是 Mock：Open-Meteo 会使用用户真实坐标请求小时级预报。若请求失败或没有 6:00-9:00 数据，同样抛错。
    private func fetchOpenMeteoMorningSummary(
        for location: CLLocation,
        windowStart: Date,
        windowEnd: Date,
        forecastStart: Date,
        forecastEnd: Date
    ) async throws -> MorningWeatherSummary {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", location.coordinate.longitude)),
            URLQueryItem(
                name: "hourly",
                value: "precipitation_probability,precipitation,snowfall,visibility,wind_gusts_10m,weather_code"
            ),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let fullCandidates = forecast.hourly.time.enumerated().compactMap { index, timeText -> HourlyWeatherSample? in
            guard let date = formatter.date(from: timeText),
                  date >= forecastStart,
                  date < forecastEnd else {
                return nil
            }

            let chance = forecast.hourly.precipitationProbability?[safe: index] ?? 0
            let code = forecast.hourly.weatherCode?[safe: index]
            return HourlyWeatherSample(
                date: date,
                weatherCondition: Self.openMeteoConditionDescription(for: code),
                precipitationChancePercent: chance,
                precipitationAmountMillimeters: forecast.hourly.precipitation?[safe: index],
                snowfallAmountCentimeters: forecast.hourly.snowfall?[safe: index],
                visibilityMeters: forecast.hourly.visibility?[safe: index],
                windGustKilometersPerHour: forecast.hourly.windGusts?[safe: index]
            )
        }
        let candidates = fullCandidates.filter {
            $0.date >= windowStart && $0.date < windowEnd
        }

        guard let wettestHour = Self.mostSignificantSample(in: candidates) else {
            throw WeatherServiceError.openMeteoMissingHourlyData
        }

        return MorningWeatherSummary(
            weatherCondition: wettestHour.weatherCondition,
            precipitationChancePercent: wettestHour.precipitationChancePercent,
            precipitationAmountMillimeters: wettestHour.precipitationAmountMillimeters,
            windowStart: windowStart,
            windowEnd: windowEnd,
            hourlyForecast: candidates.map(\.summary),
            fullHourlyForecast: fullCandidates.map(\.summary)
        )
    }

    private static func mostSignificantSample(in samples: [HourlyWeatherSample]) -> HourlyWeatherSample? {
        samples.max { lhs, rhs in
            let lhsAmount = lhs.precipitationAmountMillimeters ?? -1
            let rhsAmount = rhs.precipitationAmountMillimeters ?? -1
            if lhsAmount == rhsAmount {
                return lhs.precipitationChancePercent < rhs.precipitationChancePercent
            }
            return lhsAmount < rhsAmount
        }
    }

    private static func openMeteoConditionDescription(for code: Int?) -> String {
        guard let code else {
            return "天气预报"
        }

        switch code {
        case 0:
            return "晴"
        case 1...3:
            return "多云"
        case 45, 48:
            return "雾"
        case 51...67, 80...82:
            return "雨"
        case 71...77, 85...86:
            return "雪"
        case 95...99:
            return "雷雨"
        default:
            return "天气预报"
        }
    }

    /// 找到未来 24 小时内的下一段 6:00-9:00。
    ///
    /// 每日后台任务配置为“最早 05:00 执行”，正常情况下会解析当天 6:00-9:00。
    /// 如果系统晚些时候才唤醒 App，而当天窗口已经过去，则会尝试明天 6:00-9:00；
    /// 若该窗口不在未来 24 小时内，则抛错，避免使用不完整数据。
    private func nextMorningWindowWithin24Hours(after now: Date) throws -> (start: Date, end: Date) {
        let futureLimit = calendar.date(byAdding: .hour, value: 24, to: now) ?? now.addingTimeInterval(24 * 60 * 60)

        for dayOffset in 0...1 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let start = calendar.date(
                    bySettingHour: 6,
                    minute: 0,
                    second: 0,
                    of: candidateDay
                  ),
                  let end = calendar.date(
                    bySettingHour: 9,
                    minute: 0,
                    second: 0,
                    of: candidateDay
                  ) else {
                continue
            }

            if end > now && start < futureLimit {
                return (start, min(end, futureLimit))
            }
        }

        throw WeatherServiceError.missingMorningWindow
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
