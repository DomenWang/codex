import CoreLocation
import Foundation
import WeatherKit

enum WeatherServiceError: LocalizedError {
    case missingMorningWindow
    case noHourlyForecastForMorningWindow

    var errorDescription: String? {
        switch self {
        case .missingMorningWindow:
            return "Could not calculate the next 6:00-9:00 morning weather window."
        case .noHourlyForecastForMorningWindow:
            return "WeatherKit did not return hourly forecast data for the 6:00-9:00 morning window."
        }
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

        let weather = try await appleWeatherService.weather(
            for: location,
            including: .hourly(startDate: startDate, endDate: endDate)
        )

        let morningWindow = try nextMorningWindowWithin24Hours(after: now)

        let morningForecast = weather.forecast.filter { hourWeather in
            hourWeather.date >= morningWindow.start && hourWeather.date < morningWindow.end
        }

        guard !morningForecast.isEmpty else {
            throw WeatherServiceError.noHourlyForecastForMorningWindow
        }

        let wettestHour = morningForecast.max {
            $0.precipitationChance < $1.precipitationChance
        }

        guard let wettestHour else {
            throw WeatherServiceError.noHourlyForecastForMorningWindow
        }

        return MorningWeatherSummary(
            weatherCondition: wettestHour.condition.description,
            precipitationChancePercent: wettestHour.precipitationChance * 100,
            windowStart: morningWindow.start,
            windowEnd: morningWindow.end
        )
    }

    /// 找到未来 24 小时内的下一段 6:00-9:00。
    ///
    /// 每日后台任务配置为“最早 03:00 执行”，正常情况下会解析当天 6:00-9:00。
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

