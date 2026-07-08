import Foundation

enum AlarmSettingsStoreError: LocalizedError {
    case missingAlarmSettings
    case invalidWakeUpTime

    var errorDescription: String? {
        switch self {
        case .missingAlarmSettings:
            return "Missing alarm settings. The user must set a real wake-up time before AlarmKit can schedule an alarm."
        case .invalidWakeUpTime:
            return "The stored wake-up time is invalid."
        }
    }
}

/// 真实的本地设置存储。
///
/// 注意：这里不是 Mock。它只从 UserDefaults 读取用户已经保存过的真实闹钟设置。
/// 如果没有设置，调用方会收到错误，后台任务会失败并保持现有闹钟不变。
final class AlarmSettingsStore {
    private enum Keys {
        static let alarmSettings = "weather_alarm.settings"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadRequiredSettings() throws -> AlarmSettings {
        guard let settings = try loadSettings() else {
            // TODO: 在设置页引导用户选择真实起床时间后再保存 AlarmSettings。
            throw AlarmSettingsStoreError.missingAlarmSettings
        }

        return settings
    }

    func loadSettings() throws -> AlarmSettings? {
        guard let data = userDefaults.data(forKey: Keys.alarmSettings) else {
            return nil
        }

        let settings = try JSONDecoder().decode(AlarmSettings.self, from: data)
        guard (0...23).contains(settings.wakeUpHour),
              (0...59).contains(settings.wakeUpMinute) else {
            throw AlarmSettingsStoreError.invalidWakeUpTime
        }

        return settings
    }

    func save(_ settings: AlarmSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: Keys.alarmSettings)
    }

    func saveWakeUpTime(hour: Int, minute: Int) throws -> AlarmSettings {
        var settings = try loadSettings() ?? AlarmSettings(
            alarmID: UUID(),
            wakeUpHour: hour,
            wakeUpMinute: minute,
            isEnabled: false,
            isCommuteAdjustmentEnabled: false,
            commuteRoute: nil,
            weatherAdjustmentSettings: .default
        )

        settings.wakeUpHour = hour
        settings.wakeUpMinute = minute
        try save(settings)
        return settings
    }

    func setSmartAdjustmentEnabled(_ isEnabled: Bool) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.isEnabled = isEnabled
        try save(settings)
        return settings
    }

    func setCommuteAdjustmentEnabled(_ isEnabled: Bool) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.isCommuteAdjustmentEnabled = isEnabled
        try save(settings)
        return settings
    }

    func saveWeatherAdjustmentSettings(_ adjustmentSettings: WeatherAdjustmentSettings) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.weatherAdjustmentSettings = adjustmentSettings
        try save(settings)
        return settings
    }

    func saveCommuteRoute(_ route: CommuteRoute) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.commuteRoute = route
        try save(settings)
        return settings
    }
}


