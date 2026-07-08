import Foundation

/// 最近一次真实 WeatherKit 成功结果的缓存。
///
/// 这里不伪造天气 API 成功；只有 WeatherKit 成功返回的 `MorningWeatherSummary`
/// 才会被保存。后台断网时可以用 3 天内缓存做保守降级。
final class WeatherSummaryCacheStore {
    private enum Keys {
        static let lastMorningSummary = "ww_last_weather_data"
    }

    private struct CachedSummary: Codable {
        let savedAt: Date
        let summary: MorningWeatherSummary
    }

    private let userDefaults: UserDefaults
    private let maxAge: TimeInterval

    init(
        userDefaults: UserDefaults = .standard,
        maxAge: TimeInterval = 3 * 24 * 60 * 60
    ) {
        self.userDefaults = userDefaults
        self.maxAge = maxAge
    }

    func save(_ summary: MorningWeatherSummary, now: Date = Date()) {
        let cached = CachedSummary(savedAt: now, summary: summary)
        guard let data = try? JSONEncoder().encode(cached) else {
            return
        }

        userDefaults.set(data, forKey: Keys.lastMorningSummary)
        userDefaults.synchronize()
    }

    func loadValidSummary(now: Date = Date()) -> MorningWeatherSummary? {
        guard let data = userDefaults.data(forKey: Keys.lastMorningSummary),
              let cached = try? JSONDecoder().decode(CachedSummary.self, from: data),
              now.timeIntervalSince(cached.savedAt) <= maxAge else {
            return nil
        }

        return cached.summary
    }
}
