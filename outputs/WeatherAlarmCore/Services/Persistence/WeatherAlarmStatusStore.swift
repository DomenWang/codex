import Foundation
import WidgetKit

final class WeatherAlarmStatusStore {
    private enum Keys {
        static let latestStatus = "weather_alarm.latest_status"
        static let ordinaryAlarmStatuses = "weather_alarm.ordinary_alarm_statuses"
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

    func loadOrdinaryAlarmStatuses() -> [UUID: WeatherAlarmStatus] {
        guard let data = userDefaults.data(forKey: Keys.ordinaryAlarmStatuses),
              let storedStatuses = try? JSONDecoder().decode(
                [String: WeatherAlarmStatus].self,
                from: data
              ) else {
            return [:]
        }

        return storedStatuses.reduce(into: [:]) { result, entry in
            guard let alarmID = UUID(uuidString: entry.key) else {
                return
            }
            result[alarmID] = entry.value
        }
    }

    @discardableResult
    func migrateLegacyStatusIfNeeded(from legacyDefaults: UserDefaults = .standard) -> Bool {
        var didMigrate = false

        if userDefaults.data(forKey: Keys.latestStatus) == nil,
           let legacyData = legacyDefaults.data(forKey: Keys.latestStatus),
           (try? JSONDecoder().decode(WeatherAlarmStatus.self, from: legacyData)) != nil {
            userDefaults.set(legacyData, forKey: Keys.latestStatus)
            didMigrate = true
        }

        if userDefaults.data(forKey: Keys.ordinaryAlarmStatuses) == nil,
           let legacyData = legacyDefaults.data(forKey: Keys.ordinaryAlarmStatuses),
           (try? JSONDecoder().decode([String: WeatherAlarmStatus].self, from: legacyData)) != nil {
            userDefaults.set(legacyData, forKey: Keys.ordinaryAlarmStatuses)
            didMigrate = true
        }

        if didMigrate {
            WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
        }
        return didMigrate
    }

    func save(_ status: WeatherAlarmStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        userDefaults.set(data, forKey: Keys.latestStatus)
        WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
    }

    func removeLatestStatus() {
        guard userDefaults.object(forKey: Keys.latestStatus) != nil else {
            return
        }
        userDefaults.removeObject(forKey: Keys.latestStatus)
        WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
    }

    func save(_ status: WeatherAlarmStatus, forOrdinaryAlarmID alarmID: UUID) {
        var statuses = loadOrdinaryAlarmStatuses()
        statuses[alarmID] = status
        saveOrdinaryAlarmStatuses(statuses)
    }

    func removeOrdinaryAlarmStatus(for alarmID: UUID) {
        var statuses = loadOrdinaryAlarmStatuses()
        guard statuses.removeValue(forKey: alarmID) != nil else {
            return
        }
        saveOrdinaryAlarmStatuses(statuses)
    }

    func retainOrdinaryAlarmStatuses(for alarmIDs: Set<UUID>) {
        let statuses = loadOrdinaryAlarmStatuses().filter { alarmIDs.contains($0.key) }
        saveOrdinaryAlarmStatuses(statuses)
    }

    private func saveOrdinaryAlarmStatuses(_ statuses: [UUID: WeatherAlarmStatus]) {
        guard !statuses.isEmpty else {
            userDefaults.removeObject(forKey: Keys.ordinaryAlarmStatuses)
            WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
            return
        }

        let storedStatuses = Dictionary(
            uniqueKeysWithValues: statuses.map { ($0.key.uuidString, $0.value) }
        )
        guard let data = try? JSONEncoder().encode(storedStatuses) else {
            return
        }
        userDefaults.set(data, forKey: Keys.ordinaryAlarmStatuses)
        WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
    }
}
