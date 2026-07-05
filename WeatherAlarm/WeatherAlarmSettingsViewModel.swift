import Combine
import Foundation

@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmSettingsViewModel: ObservableObject {
    @Published private(set) var settings: AlarmSettings?
    @Published private(set) var latestStatus: WeatherAlarmStatus?
    @Published var selectedWakeUpTime: Date

    private let settingsStore: AlarmSettingsStore
    private let statusStore: WeatherAlarmStatusStore
    private let calendar: Calendar

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        statusStore: WeatherAlarmStatusStore = WeatherAlarmStatusStore(),
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.calendar = calendar
        self.selectedWakeUpTime = Date()
        reload()
    }

    var baseWakeUpTimeText: String {
        guard let settings else {
            return "未设置"
        }

        return String(format: "%02d:%02d", settings.wakeUpHour, settings.wakeUpMinute)
    }

    var tomorrowStatusText: String {
        latestStatus?.summaryText ?? "尚未完成明日天气检查"
    }

    var isSmartAdjustmentEnabled: Bool {
        settings?.isEnabled ?? false
    }

    func reload() {
        settings = try? settingsStore.loadSettings()
        latestStatus = statusStore.loadLatestStatus()

        if let settings,
           let date = calendar.date(
            bySettingHour: settings.wakeUpHour,
            minute: settings.wakeUpMinute,
            second: 0,
            of: Date()
           ) {
            selectedWakeUpTime = date
        }
    }

    func saveSelectedWakeUpTime() {
        let components = calendar.dateComponents([.hour, .minute], from: selectedWakeUpTime)
        guard let hour = components.hour,
              let minute = components.minute else {
            return
        }

        settings = try? settingsStore.saveWakeUpTime(hour: hour, minute: minute)
    }

    func setSmartAdjustmentEnabled(_ isEnabled: Bool) throws {
        settings = try settingsStore.setSmartAdjustmentEnabled(isEnabled)
    }
}

