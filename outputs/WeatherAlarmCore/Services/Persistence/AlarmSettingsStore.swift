import Foundation

enum AlarmSettingsStoreError: LocalizedError {
    case missingAlarmSettings
    case invalidWakeUpTime

    var errorDescription: String? {
        switch self {
        case .missingAlarmSettings:
            return "还没有保存闹钟，请先设置一个真实起床时间。"
        case .invalidWakeUpTime:
            return "已保存的起床时间无效。"
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
        static let legacyNextOrdinaryAlarmSequence = "weather_alarm.next_ordinary_sequence"
    }

    private static let ordinaryAlarmTitlePrefix = "其他闹钟"

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

        var settings = try JSONDecoder().decode(AlarmSettings.self, from: data)
        if let alarms = settings.ordinaryAlarms {
            let compactedAlarms = compactedAutomaticTitles(in: alarms)
            if compactedAlarms != alarms {
                settings.ordinaryAlarms = compactedAlarms
                try save(settings)
            }
        }
        userDefaults.removeObject(forKey: Keys.legacyNextOrdinaryAlarmSequence)
        try validate(settings)
        return settings
    }

    func save(_ settings: AlarmSettings) throws {
        try validate(settings)
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: Keys.alarmSettings)
    }

    private func validate(_ settings: AlarmSettings) throws {
        guard (0...23).contains(settings.wakeUpHour),
              (0...59).contains(settings.wakeUpMinute),
              (settings.wakeUpArrivalHour == nil || (0...23).contains(settings.wakeUpArrivalHour ?? 0)),
              (settings.wakeUpArrivalMinute == nil || (0...59).contains(settings.wakeUpArrivalMinute ?? 0)),
              settings.effectiveWakeUpRepeatWeekdays.allSatisfy({ (1...7).contains($0) }),
              settings.effectiveOrdinaryAlarms.allSatisfy({ alarm in
                  (0...23).contains(alarm.hour)
                    && (0...59).contains(alarm.minute)
                    && alarm.effectiveRepeatWeekdays.allSatisfy { (1...7).contains($0) }
                    && (alarm.arrivalHour == nil || (0...23).contains(alarm.arrivalHour ?? 0))
                    && (alarm.arrivalMinute == nil || (0...59).contains(alarm.arrivalMinute ?? 0))
              }) else {
            throw AlarmSettingsStoreError.invalidWakeUpTime
        }
    }

    func saveWakeUpTime(hour: Int, minute: Int) throws -> AlarmSettings {
        var settings = try loadSettings() ?? AlarmSettings(
            alarmID: UUID(),
            wakeUpHour: hour,
            wakeUpMinute: minute,
            wakeUpTitle: nil,
            wakeUpRepeatWeekdays: nil,
            isEnabled: false,
            isCommuteAdjustmentEnabled: false,
            commuteRoute: nil,
            weatherAdjustmentSettings: .default,
            ordinaryAlarms: nil
        )

        settings.wakeUpHour = hour
        settings.wakeUpMinute = minute
        try save(settings)
        return settings
    }

    func updateWakeUpTitle(_ title: String) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.wakeUpTitle = trimmedTitle.isEmpty ? nil : trimmedTitle
        try save(settings)
        return settings
    }

    func toggleWakeUpRepeatWeekday(_ weekday: Int) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        var weekdays = Set(settings.effectiveWakeUpRepeatWeekdays)
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }

        settings.wakeUpRepeatWeekdays = weekdays.sorted()
        try save(settings)
        return settings
    }

    func setWakeUpRepeatWeekdays(_ weekdays: [Int]) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.wakeUpRepeatWeekdays = Set(weekdays.filter { (1...7).contains($0) }).sorted()
        try save(settings)
        return settings
    }

    func updateWakeUpAppearance(themeIndex: Int, iconName: String) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.wakeUpThemeIndex = max(0, themeIndex)
        settings.wakeUpIconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(settings)
        return settings
    }

    func updateWakeUpDismissChallenge(_ challenge: OrdinaryAlarmDismissChallenge) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.wakeUpDismissChallenge = challenge
        try save(settings)
        return settings
    }

    func updateWakeUpSoundSelection(_ selection: AlarmSoundSelection) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.wakeUpSoundChoice = selection.builtInFallback
        settings.wakeUpCustomSoundID = selection.customSoundID
        try save(settings)
        return settings
    }

    func setWakeUpLoudVolumeEnabled(_ isEnabled: Bool) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.isWakeUpLoudVolumeEnabled = isEnabled
        try save(settings)
        return settings
    }

    func setWakeUpAlarmEnabled(_ isEnabled: Bool) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        settings.isWakeUpAlarmEnabled = isEnabled
        try save(settings)
        return settings
    }

    func updateWakeUpArrivalTime(hour: Int, minute: Int) throws -> AlarmSettings {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw AlarmSettingsStoreError.invalidWakeUpTime
        }

        var settings = try loadRequiredSettings()
        settings.wakeUpArrivalHour = hour
        settings.wakeUpArrivalMinute = minute
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

    func addOrdinaryAlarm(hour: Int, minute: Int) throws -> OrdinaryAlarmSettings {
        var settings = try loadRequiredSettings()
        var alarms = compactedAutomaticTitles(in: settings.effectiveOrdinaryAlarms)
        let nextThemeIndex = (alarms.map(\.effectiveThemeIndex).max() ?? 0) + 1
        let nextSequence = alarms.lazy
            .compactMap { self.automaticTitleNumber(from: $0.title) }
            .count + 1
        let alarm = OrdinaryAlarmSettings(
            hour: hour,
            minute: minute,
            title: "\(Self.ordinaryAlarmTitlePrefix)\(nextSequence)",
            themeIndex: nextThemeIndex
        )
        alarms.append(alarm)
        settings.ordinaryAlarms = alarms
        try save(settings)
        return alarm
    }

    func updateOrdinaryAlarm(_ updatedAlarm: OrdinaryAlarmSettings) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        var alarms = settings.effectiveOrdinaryAlarms
        guard let index = alarms.firstIndex(where: { $0.id == updatedAlarm.id }) else {
            return settings
        }

        alarms[index] = updatedAlarm
        settings.ordinaryAlarms = compactedAutomaticTitles(in: alarms)
        try save(settings)
        return settings
    }

    func removeOrdinaryAlarm(id: UUID) throws -> OrdinaryAlarmSettings? {
        var settings = try loadRequiredSettings()
        var alarms = settings.effectiveOrdinaryAlarms
        guard let index = alarms.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let removed = alarms.remove(at: index)
        settings.ordinaryAlarms = compactedAutomaticTitles(in: alarms)
        try save(settings)
        return removed
    }

    func restoreOrdinaryAlarm(_ alarm: OrdinaryAlarmSettings, at index: Int) throws -> AlarmSettings {
        var settings = try loadRequiredSettings()
        var alarms = settings.effectiveOrdinaryAlarms
        guard !alarms.contains(where: { $0.id == alarm.id }) else {
            return settings
        }

        alarms.insert(alarm, at: min(max(0, index), alarms.count))
        settings.ordinaryAlarms = compactedAutomaticTitles(in: alarms)
        try save(settings)
        return settings
    }

    private func compactedAutomaticTitles(
        in alarms: [OrdinaryAlarmSettings]
    ) -> [OrdinaryAlarmSettings] {
        var nextNumber = 1
        return alarms.map { alarm in
            guard automaticTitleNumber(from: alarm.title) != nil else {
                return alarm
            }

            var compactedAlarm = alarm
            compactedAlarm.title = "\(Self.ordinaryAlarmTitlePrefix)\(nextNumber)"
            nextNumber += 1
            return compactedAlarm
        }
    }

    private func automaticTitleNumber(from title: String?) -> Int? {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedTitle.hasPrefix(Self.ordinaryAlarmTitlePrefix) else {
            return nil
        }

        let suffix = trimmedTitle
            .dropFirst(Self.ordinaryAlarmTitlePrefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard !suffix.isEmpty,
              suffix.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(suffix),
              number > 0 else {
            return nil
        }

        return number
    }
}
