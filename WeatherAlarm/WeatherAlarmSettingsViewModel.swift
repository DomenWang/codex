import Combine
import CoreLocation
import Foundation

@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmSettingsViewModel: ObservableObject {
    @Published private(set) var settings: AlarmSettings?
    @Published private(set) var latestStatus: WeatherAlarmStatus?
    @Published private(set) var latestMorningSummary: MorningWeatherSummary?
    @Published var selectedWakeUpTime: Date
    @Published var rainAdvanceMinutes: Int
    @Published var heavyRainAdvanceMinutes: Int
    @Published var commuteStartAddress: String
    @Published var commuteEndAddress: String
    @Published var commuteCity: String
    @Published var selectedCommuteMode: CommuteMode
    @Published private(set) var commuteSyncMessage: String?
    @Published private(set) var weatherRefreshMessage: String?
    @Published private(set) var isSyncingCommuteRoute = false
    @Published private(set) var isRefreshingWeather = false

    private let settingsStore: AlarmSettingsStore
    private let statusStore: WeatherAlarmStatusStore
    private let weatherService: WeatherService
    private let weatherSummaryCacheStore: WeatherSummaryCacheStore
    private let transitService: TransitService
    private let calendar: Calendar

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        statusStore: WeatherAlarmStatusStore = WeatherAlarmStatusStore(),
        weatherService: WeatherService = WeatherService(),
        weatherSummaryCacheStore: WeatherSummaryCacheStore = WeatherSummaryCacheStore(),
        transitService: TransitService = TransitService(),
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.weatherService = weatherService
        self.weatherSummaryCacheStore = weatherSummaryCacheStore
        self.transitService = transitService
        self.calendar = calendar
        self.selectedWakeUpTime = Date()
        self.rainAdvanceMinutes = WeatherAdjustmentSettings.default.rainAdvanceMinutes
        self.heavyRainAdvanceMinutes = WeatherAdjustmentSettings.default.heavyRainAdvanceMinutes
        self.commuteStartAddress = ""
        self.commuteEndAddress = ""
        self.commuteCity = ""
        self.selectedCommuteMode = .driving
        reload()
    }

    var baseWakeUpTimeText: String {
        guard let settings else {
            return "未设置"
        }

        return String(format: "%02d:%02d", settings.wakeUpHour, settings.wakeUpMinute)
    }

    var tomorrowStatusText: String {
        if let latestStatus {
            return latestStatus.summaryText
        }

        if let latestMorningSummary {
            return "已获取明早天气，设置基础起床时间后生成闹钟建议"
        }

        return "尚未完成明日天气检查"
    }

    var tomorrowWeatherText: String {
        if let latestStatus {
            return "\(latestStatus.weatherCondition)，降水概率 \(Int(latestStatus.precipitationChancePercent.rounded()))%"
        }

        if let latestMorningSummary {
            return "\(latestMorningSummary.weatherCondition)，降水概率 \(Int(latestMorningSummary.precipitationChancePercent.rounded()))%"
        }

        return "等待授权定位后获取明早 6:00-9:00 天气"
    }

    var suggestedAlarmTimeText: String {
        guard let latestStatus else {
            return "获取天气并设置起床时间后生成建议"
        }

        return DateFormatter.weatherAlarmTime.string(from: latestStatus.scheduledWakeUpDate)
    }

    var commuteRouteText: String {
        guard let route = settings?.commuteRoute else {
            return "未保存通勤路线"
        }

        let start = route.startName ?? "出发地"
        let end = route.endName ?? "目的地"
        let minutes = Int((route.baseDurationSeconds / 60).rounded())
        let distanceText: String
        if let distance = route.baseDistanceMeters {
            distanceText = String(format: "，约 %.1f 公里", distance / 1000)
        } else {
            distanceText = ""
        }

        return "\(route.effectiveMode.displayName)：\(start) → \(end)，高德预估 \(minutes) 分钟\(distanceText)"
    }

    var isSmartAdjustmentEnabled: Bool {
        settings?.isEnabled ?? false
    }

    var isCommuteAdjustmentEnabled: Bool {
        settings?.effectiveIsCommuteAdjustmentEnabled ?? false
    }

    func reload() {
        settings = try? settingsStore.loadSettings()
        latestStatus = statusStore.loadLatestStatus()
        latestMorningSummary = weatherSummaryCacheStore.loadValidSummary()

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
            commuteCity = settings.commuteRoute?.city ?? commuteCity
            selectedCommuteMode = settings.commuteRoute?.effectiveMode ?? selectedCommuteMode
        }
    }

    func saveSelectedWakeUpTime() {
        let components = calendar.dateComponents([.hour, .minute], from: selectedWakeUpTime)
        guard let hour = components.hour,
              let minute = components.minute else {
            return
        }

        settings = try? settingsStore.saveWakeUpTime(hour: hour, minute: minute)
        buildVisibleStatusIfPossible()
    }

    func setSmartAdjustmentEnabled(_ isEnabled: Bool) throws {
        settings = try settingsStore.setSmartAdjustmentEnabled(isEnabled)
    }

    func setCommuteAdjustmentEnabled(_ isEnabled: Bool) throws {
        settings = try settingsStore.setCommuteAdjustmentEnabled(isEnabled)
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
        buildVisibleStatusIfPossible()
    }

    func refreshWeatherWithCurrentLocation(_ location: CLLocation) async -> Bool {
        isRefreshingWeather = true
        weatherRefreshMessage = nil
        defer {
            isRefreshingWeather = false
        }

        do {
            let summary = try await weatherService.fetchMorningPrecipitationSummary(for: location)
            latestMorningSummary = summary
            weatherSummaryCacheStore.save(summary)
            buildVisibleStatusIfPossible()
            weatherRefreshMessage = "已用 WeatherKit 获取真实明早天气"
            return true
        } catch {
            weatherRefreshMessage = "天气获取失败：请检查定位权限、WeatherKit 能力或网络"
            return false
        }
    }

    func markWeatherRefreshFailed(_ message: String) {
        weatherRefreshMessage = message
    }

    @discardableResult
    func syncCommuteRouteWithAMap() async -> Bool {
        guard !commuteStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !commuteEndAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            commuteSyncMessage = "请填写出发地和目的地"
            return false
        }

        isSyncingCommuteRoute = true
        commuteSyncMessage = nil
        let transitCity = inferredTransitCity()

        do {
            let route = try await transitService.syncCommuteRoute(
                startAddress: commuteStartAddress,
                endAddress: commuteEndAddress,
                mode: selectedCommuteMode,
                city: selectedCommuteMode == .transit ? transitCity : transitCity
            )
            settings = try settingsStore.saveCommuteRoute(route)
            commuteStartAddress = route.startName ?? commuteStartAddress
            commuteEndAddress = route.endName ?? commuteEndAddress
            commuteCity = route.city ?? transitCity ?? commuteCity
            commuteSyncMessage = "路线已保存，高德预估时间已同步"
            isSyncingCommuteRoute = false
            return true
        } catch TransitServiceError.missingTransitCity {
            commuteSyncMessage = "公交路线需要出发地或目的地包含城市名，例如：北京市朝阳区望京"
        } catch {
            commuteSyncMessage = "高德路线同步失败，请检查 API Key、地址或网络"
        }

        isSyncingCommuteRoute = false
        return false
    }

    private func inferredTransitCity() -> String? {
        let explicitCity = commuteCity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitCity.isEmpty {
            return explicitCity
        }

        for address in [commuteStartAddress, commuteEndAddress] {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if let cityRange = trimmed.range(of: "市") {
                let city = String(trimmed[...cityRange.lowerBound])
                if city.count >= 2 {
                    return city
                }
            }

            for municipality in ["北京", "上海", "天津", "重庆"] where trimmed.contains(municipality) {
                return "\(municipality)市"
            }
        }

        return nil
    }

    private func buildVisibleStatusIfPossible() {
        guard let settings,
              let summary = latestMorningSummary,
              let baseWakeUpDate = settings.nextBaseWakeUpDate(calendar: calendar) else {
            latestStatus = statusStore.loadLatestStatus()
            return
        }

        let weatherBuffer = settings.effectiveWeatherAdjustmentSettings.weatherBufferMinutes(
            weatherCondition: summary.weatherCondition,
            precipitationChancePercent: summary.precipitationChancePercent
        )
        let scheduledWakeUpDate = calendar.date(
            byAdding: .minute,
            value: -weatherBuffer,
            to: baseWakeUpDate
        ) ?? baseWakeUpDate.addingTimeInterval(TimeInterval(-weatherBuffer * 60))

        let status = WeatherAlarmStatus(
            generatedAt: Date(),
            baseWakeUpDate: baseWakeUpDate,
            scheduledWakeUpDate: scheduledWakeUpDate,
            advanceMinutes: weatherBuffer,
            weatherBufferMinutes: weatherBuffer,
            commuteDelayMinutes: 0,
            weatherCondition: summary.weatherCondition,
            precipitationChancePercent: summary.precipitationChancePercent
        )

        statusStore.save(status)
        latestStatus = status
    }
}

private extension DateFormatter {
    static let weatherAlarmTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
