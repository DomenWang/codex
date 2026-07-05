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
        guard let data = userDefaults.data(forKey: Keys.alarmSettings) else {
            // TODO: 在设置页引导用户选择真实起床时间后再保存 AlarmSettings。
            throw AlarmSettingsStoreError.missingAlarmSettings
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
}

