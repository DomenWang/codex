import Combine
import Foundation

@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmSettingsViewModel: ObservableObject {
    @Published private(set) var settings: AlarmSettings?
    @Published private(set) var latestStatus: WeatherAlarmStatus?
    @Published var selectedWakeUpTime: Date
    @Published var rainAdvanceMinutes: Int
    @Published var heavyRainAdvanceMinutes: Int
    @Published var commuteStartAddress: String
    @Published var commuteEndAddress: String
    @Published private(set) var commuteSyncMessage: String?
    @Published private(set) var isSyncingCommuteRoute = false

    private let settingsStore: AlarmSettingsStore
    private let statusStore: WeatherAlarmStatusStore
    private let transitService: TransitService
    private let calendar: Calendar

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        statusStore: WeatherAlarmStatusStore = WeatherAlarmStatusStore(),
        transitService: TransitService = TransitService(),
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.transitService = transitService
        self.calendar = calendar
        self.selectedWakeUpTime = Date()
        self.rainAdvanceMinutes = WeatherAdjustmentSettings.default.rainAdvanceMinutes
        self.heavyRainAdvanceMinutes = WeatherAdjustmentSettings.default.heavyRainAdvanceMinutes
        self.commuteStartAddress = ""
        self.commuteEndAddress = ""
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

    var tomorrowWeatherText: String {
        guard let latestStatus else {
            return "尚未获取明日 6:00-9:00 天气"
        }

        return "\(latestStatus.weatherCondition)，降水概率 \(Int(latestStatus.precipitationChancePercent.rounded()))%"
    }

    var suggestedAlarmTimeText: String {
        guard let latestStatus else {
            return "等待后台天气检查后生成建议"
        }

        return DateFormatter.weatherAlarmTime.string(from: latestStatus.scheduledWakeUpDate)
    }

    var commuteRouteText: String {
        guard let route = settings?.commuteRoute else {
            return "未设置"
        }

        let start = route.startName ?? "出发地"
        let end = route.endName ?? "目的地"
        let minutes = Int((route.baseDurationSeconds / 60).rounded())
        return "\(start) → \(end)，基础约 \(minutes) 分钟"
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
            let rule = settings.effectiveWeatherAdjustmentSettings
            rainAdvanceMinutes = rule.rainAdvanceMinutes
            heavyRainAdvanceMinutes = rule.heavyRainAdvanceMinutes
            commuteStartAddress = settings.commuteRoute?.startName ?? commuteStartAddress
            commuteEndAddress = settings.commuteRoute?.endName ?? commuteEndAddress
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

    func saveWeatherAdjustmentSettings() {
        if heavyRainAdvanceMinutes < rainAdvanceMinutes {
            heavyRainAdvanceMinutes = rainAdvanceMinutes
        }

        let adjustmentSettings = WeatherAdjustmentSettings(
            rainThresholdPercent: WeatherAdjustmentSettings.default.rainThresholdPercent,
            heavyRainThresholdPercent: WeatherAdjustmentSettings.default.heavyRainThresholdPercent,
            rainAdvanceMinutes: rainAdvanceMinutes,
            heavyRainAdvanceMinutes: heavyRainAdvanceMinutes
        )

        settings = try? settingsStore.saveWeatherAdjustmentSettings(adjustmentSettings)
    }

    func syncCommuteRouteWithAMap() async {
        guard !commuteStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !commuteEndAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            commuteSyncMessage = "请填写出发地和目的地"
            return
        }

        isSyncingCommuteRoute = true
        commuteSyncMessage = nil

        do {
            let route = try await transitService.syncCommuteRoute(
                startAddress: commuteStartAddress,
                endAddress: commuteEndAddress
            )
            settings = try settingsStore.saveCommuteRoute(route)
            commuteSyncMessage = "通勤路线已同步"
        } catch {
            commuteSyncMessage = "高德路线同步失败，请检查 API Key 或网络"
        }

        isSyncingCommuteRoute = false
    }
}

private extension DateFormatter {
    static let weatherAlarmTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
