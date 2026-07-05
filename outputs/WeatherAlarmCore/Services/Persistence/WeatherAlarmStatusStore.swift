import Foundation

final class WeatherAlarmStatusStore {
    private enum Keys {
        static let latestStatus = "weather_alarm.latest_status"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = AppGroupUserDefaults.shared) {
        self.userDefaults = userDefaults
    }

    func loadLatestStatus() -> WeatherAlarmStatus? {
        guard let data = userDefaults.data(forKey: Keys.latestStatus) else {
            return nil
        }

        return try? JSONDecoder().decode(WeatherAlarmStatus.self, from: data)
    }

    func save(_ status: WeatherAlarmStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        userDefaults.set(data, forKey: Keys.latestStatus)
    }
}
