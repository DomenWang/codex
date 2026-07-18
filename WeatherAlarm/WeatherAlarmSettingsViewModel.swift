import Combine
import CoreLocation
import Foundation

@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmSettingsViewModel: ObservableObject {
    private enum CommuteDraftKeys {
        static let startAddress = "weather_alarm.commute_draft.start_address"
        static let endAddress = "weather_alarm.commute_draft.end_address"
    }

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
    @Published private(set) var ordinaryAlarmCommutePreviews: [UUID: OrdinaryAlarmCommutePreview] = [:]
    @Published private(set) var ordinaryAlarmScheduleStatuses: [UUID: WeatherAlarmStatus] = [:]

    private let settingsStore: AlarmSettingsStore
    private let statusStore: WeatherAlarmStatusStore
    private let weatherService: WeatherService
    private let weatherSummaryCacheStore: WeatherSummaryCacheStore
    private let transitService: TransitService
    private let calendar: Calendar
    private let userDefaults: UserDefaults

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        statusStore: WeatherAlarmStatusStore = WeatherAlarmStatusStore(),
        weatherService: WeatherService = WeatherService(),
        weatherSummaryCacheStore: WeatherSummaryCacheStore = WeatherSummaryCacheStore(),
        transitService: TransitService = TransitService(),
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard
    ) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.weatherService = weatherService
        self.weatherSummaryCacheStore = weatherSummaryCacheStore
        self.transitService = transitService
        self.calendar = calendar
        self.userDefaults = userDefaults
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

    var wakeUpTitleText: String {
        settings?.effectiveWakeUpTitle ?? "起床闹钟"
    }

    var wakeUpRepeatSummaryText: String {
        settings?.wakeUpRepeatSummaryText ?? "仅一次"
    }

    var wakeUpRepeatWeekdays: [Int] {
        settings?.effectiveWakeUpRepeatWeekdays ?? []
    }

    var wakeUpThemeIndex: Int {
        settings?.effectiveWakeUpThemeIndex ?? 0
    }

    var wakeUpIconName: String {
        settings?.effectiveWakeUpIconName ?? "alarm.fill"
    }

    var wakeUpDismissChallenge: OrdinaryAlarmDismissChallenge {
        settings?.effectiveWakeUpDismissChallenge ?? .none
    }

    var wakeUpSoundSelection: AlarmSoundSelection {
        settings?.effectiveWakeUpSoundSelection ?? .builtIn(.systemDefault)
    }

    var wakeUpSoundChoice: AlarmSoundChoice {
        settings?.effectiveWakeUpSoundChoice ?? .systemDefault
    }

    var isWakeUpLoudVolumeEnabled: Bool {
        settings?.effectiveIsWakeUpLoudVolumeEnabled ?? false
    }

    var isWakeUpAlarmEnabled: Bool {
        settings?.effectiveIsWakeUpAlarmEnabled ?? false
    }

    var tomorrowHourlyForecast: [HourlyWeatherSummary] {
        guard let latestMorningSummary else {
            return []
        }

        let fallbackForecast = latestMorningSummary.hourlyForecast ?? []
        guard let baseWakeUpDate = settings?.nextBaseWakeUpDate(calendar: calendar) else {
            return fallbackForecast
        }

        if let fullHourlyForecast = latestMorningSummary.fullHourlyForecast,
           !fullHourlyForecast.isEmpty {
            let wakeHour = calendar.dateInterval(of: .hour, for: baseWakeUpDate)?.start ?? baseWakeUpDate
            var usedHours = Set<Date>()
            let focusedForecast = (-3...3).compactMap { offset -> HourlyWeatherSummary? in
                guard let targetHour = calendar.date(byAdding: .hour, value: offset, to: wakeHour) else {
                    return nil
                }

                guard let match = fullHourlyForecast.min(by: {
                    abs($0.date.timeIntervalSince(targetHour)) < abs($1.date.timeIntervalSince(targetHour))
                }) else {
                    return nil
                }

                let matchedHour = calendar.dateInterval(of: .hour, for: match.date)?.start ?? match.date
                guard usedHours.insert(matchedHour).inserted else {
                    return nil
                }

                return match
            }

            if !focusedForecast.isEmpty {
                return focusedForecast.sorted { $0.date < $1.date }
            }
        }

        return fallbackForecast
    }

    var tomorrowStatusText: String {
        if let latestStatus {
            return latestStatus.summaryText
        }

        if latestMorningSummary != nil {
            return "已获取明早天气，设置基础起床时间后生成闹钟建议"
        }

        return "尚未完成明日天气检查"
    }

    var tomorrowWeatherText: String {
        if let latestMorningSummary {
            return "\(latestMorningSummary.weatherCondition)，降水概率 \(Int(latestMorningSummary.precipitationChancePercent.rounded()))%"
        }

        if let latestStatus {
            return "\(latestStatus.weatherCondition)，降水概率 \(Int(latestStatus.precipitationChancePercent.rounded()))%"
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
        commuteRouteText(for: settings?.commuteRoute)
    }

    func commuteRouteText(for route: CommuteRoute?) -> String {
        guard let route else {
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

        let walkingText: String
        if route.effectiveMode == .transit,
           let walkingDistance = route.baseWalkingDistanceMeters {
            walkingText = String(format: "，步行约 %.1f 公里", walkingDistance / 1000)
        } else {
            walkingText = ""
        }

        return "\(route.effectiveMode.displayName)：\(start) → \(end)，预计 \(minutes) 分钟\(distanceText)\(walkingText)"
    }

    func ordinaryAlarmRoute(id: UUID) -> CommuteRoute? {
        ordinaryAlarm(id: id)?.commuteRoute
    }

    var isSmartAdjustmentEnabled: Bool {
        settings?.isEnabled ?? false
    }

    var isCommuteAdjustmentEnabled: Bool {
        settings?.effectiveIsCommuteAdjustmentEnabled ?? false
    }

    var ordinaryAlarms: [OrdinaryAlarmSettings] {
        settings?.effectiveOrdinaryAlarms ?? []
    }

    func reload() {
        settings = try? settingsStore.loadSettings()
        latestStatus = statusStore.loadLatestStatus()
        reloadOrdinaryAlarmScheduleStatuses()
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
            commuteStartAddress = savedDraftAddress(forKey: CommuteDraftKeys.startAddress)
                ?? settings.commuteRoute?.startName
                ?? commuteStartAddress
            commuteEndAddress = savedDraftAddress(forKey: CommuteDraftKeys.endAddress)
                ?? settings.commuteRoute?.endName
                ?? commuteEndAddress
            commuteCity = settings.commuteRoute?.city ?? commuteCity
            selectedCommuteMode = settings.commuteRoute?.effectiveMode ?? selectedCommuteMode
        } else {
            commuteStartAddress = savedDraftAddress(forKey: CommuteDraftKeys.startAddress) ?? commuteStartAddress
            commuteEndAddress = savedDraftAddress(forKey: CommuteDraftKeys.endAddress) ?? commuteEndAddress
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

    func setWakeUpAlarmEnabled(_ isEnabled: Bool) throws {
        settings = try settingsStore.setWakeUpAlarmEnabled(isEnabled)
        buildVisibleStatusIfPossible()
    }

    func updateWakeUpTitle(_ title: String) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.updateWakeUpTitle(title)
    }

    func toggleWakeUpRepeatWeekday(_ weekday: Int) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.toggleWakeUpRepeatWeekday(weekday)
        buildVisibleStatusIfPossible()
    }

    func setWakeUpRepeatWeekdays(_ weekdays: [Int]) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.setWakeUpRepeatWeekdays(weekdays)
        buildVisibleStatusIfPossible()
    }

    func updateWakeUpAppearance(themeIndex: Int, iconName: String) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.updateWakeUpAppearance(themeIndex: themeIndex, iconName: iconName)
    }

    func updateWakeUpDismissChallenge(_ challenge: OrdinaryAlarmDismissChallenge) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.updateWakeUpDismissChallenge(challenge)
    }

    func updateWakeUpSoundSelection(_ selection: AlarmSoundSelection) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.updateWakeUpSoundSelection(selection)
    }

    func setWakeUpLoudVolumeEnabled(_ isEnabled: Bool) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        settings = try settingsStore.setWakeUpLoudVolumeEnabled(isEnabled)
    }

    func wakeUpArrivalDate() -> Date {
        calendar.date(
            bySettingHour: settings?.wakeUpArrivalHour ?? 9,
            minute: settings?.wakeUpArrivalMinute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    func updateWakeUpArrivalTime(_ date: Date) throws {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour,
              let minute = components.minute else {
            return
        }

        settings = try settingsStore.updateWakeUpArrivalTime(hour: hour, minute: minute)
    }

    func ordinaryAlarm(id: UUID) -> OrdinaryAlarmSettings? {
        settings?.effectiveOrdinaryAlarms.first { $0.id == id }
    }

    func ordinaryAlarmDate(for alarm: OrdinaryAlarmSettings) -> Date {
        calendar.date(
            bySettingHour: alarm.hour,
            minute: alarm.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    func ordinaryAlarmArrivalDate(for alarm: OrdinaryAlarmSettings) -> Date {
        calendar.date(
            bySettingHour: alarm.arrivalHour ?? 9,
            minute: alarm.arrivalMinute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    func weatherPreview(for alarm: OrdinaryAlarmSettings) -> HourlyWeatherSummary? {
        guard alarm.isWeatherAdjustmentEnabled,
              let baseDate = alarm.nextBaseWakeUpDate(calendar: calendar),
              let latestMorningSummary,
              let hourlyForecast = latestMorningSummary.fullHourlyForecast ?? latestMorningSummary.hourlyForecast,
              !hourlyForecast.isEmpty else {
            return nil
        }

        guard let nearestHour = hourlyForecast.min(by: { first, second in
            abs(first.date.timeIntervalSince(baseDate)) < abs(second.date.timeIntervalSince(baseDate))
        }) else {
            return nil
        }

        let hasFullForecast = latestMorningSummary.fullHourlyForecast?.isEmpty == false
        let maximumAllowedDistance: TimeInterval = hasFullForecast ? 90 * 60 : 30 * 60
        guard abs(nearestHour.date.timeIntervalSince(baseDate)) <= maximumAllowedDistance else {
            return nil
        }

        return nearestHour
    }

    func advanceDisplay(for alarm: OrdinaryAlarmSettings) -> AlarmAdvanceDisplay? {
        guard alarm.effectiveIsEnabled,
              let baseWakeUpDate = alarm.nextBaseWakeUpDate(calendar: calendar) else {
            return nil
        }

        if alarm.usesSmartTiming,
           let persistedStatus = ordinaryAlarmScheduleStatuses[alarm.id],
           persistedStatus.advanceMinutes > 0,
           abs(persistedStatus.baseWakeUpDate.timeIntervalSince(baseWakeUpDate)) < 60 {
            return AlarmAdvanceDisplay(
                advanceMinutes: persistedStatus.advanceMinutes,
                weatherAdvanceMinutes: persistedStatus.weatherBufferMinutes,
                routeAdvanceMinutes: persistedStatus.commuteDelayMinutes,
                scheduledWakeUpDate: persistedStatus.scheduledWakeUpDate
            )
        }

        let focusedWeather = alarm.isWeatherAdjustmentEnabled
            ? latestMorningSummary?.focused(
                on: baseWakeUpDate,
                travelDuration: alarm.isCommuteAdjustmentEnabled ? alarm.commuteRoute?.baseDurationSeconds : nil
            )
            : nil
        let weatherAdvance = settings?.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather) ?? .zero
        let commutePreview = ordinaryAlarmCommutePreviews[alarm.id]
        let decision = SmartAdvanceCalculator.calculate(
            weatherEnabled: alarm.isWeatherAdjustmentEnabled,
            routeAvailable: alarm.isCommuteAdjustmentEnabled && commutePreview?.isAvailable == true,
            weather: weatherAdvance,
            routeDelayMinutes: commutePreview?.delayMinutes ?? 0,
            residualWeatherMinutes: commutePreview?.residualWeatherMinutes ?? 0,
            arrivalAdvanceMinutes: commutePreview?.arrivalAdvanceMinutes ?? 0
        )
        let totalAdvanceMinutes = decision.totalMinutes
        guard totalAdvanceMinutes > 0 else {
            return nil
        }

        let scheduledWakeUpDate = calendar.date(
            byAdding: .minute,
            value: -totalAdvanceMinutes,
            to: baseWakeUpDate
        ) ?? baseWakeUpDate.addingTimeInterval(TimeInterval(-totalAdvanceMinutes * 60))

        return AlarmAdvanceDisplay(
            advanceMinutes: totalAdvanceMinutes,
            weatherAdvanceMinutes: decision.weatherMinutes,
            routeAdvanceMinutes: decision.routeMinutes,
            scheduledWakeUpDate: scheduledWakeUpDate
        )
    }

    func reloadOrdinaryAlarmScheduleStatuses() {
        ordinaryAlarmScheduleStatuses = statusStore.loadOrdinaryAlarmStatuses()
    }

    func addOrdinaryAlarm() throws -> OrdinaryAlarmSettings {
        if settings == nil {
            saveSelectedWakeUpTime()
        }

        let defaultAlarmDate = Date().addingTimeInterval(3600)
        let components = calendar.dateComponents([.hour, .minute], from: defaultAlarmDate)
        let alarm = try settingsStore.addOrdinaryAlarm(
            hour: components.hour ?? 8,
            minute: components.minute ?? 0
        )
        reload()
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmTime(id: UUID, date: Date) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour,
              let minute = components.minute else {
            return nil
        }

        alarm.hour = hour
        alarm.minute = minute
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func setOrdinaryAlarmWeatherAdjustment(id: UUID, isEnabled: Bool) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.isWeatherAdjustmentEnabled = isEnabled
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func setOrdinaryAlarmCommuteAdjustment(id: UUID, isEnabled: Bool) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.isCommuteAdjustmentEnabled = isEnabled
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func setOrdinaryAlarmEnabled(id: UUID, isEnabled: Bool) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.isEnabled = isEnabled
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmTitle(id: UUID, title: String) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        alarm.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmAppearance(
        id: UUID,
        themeIndex: Int,
        iconName: String
    ) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.themeIndex = max(0, themeIndex)
        alarm.iconName = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func toggleOrdinaryAlarmRepeatWeekday(id: UUID, weekday: Int) throws -> OrdinaryAlarmSettings? {
        guard (1...7).contains(weekday),
              var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        var weekdays = Set(alarm.effectiveRepeatWeekdays)
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }

        alarm.repeatWeekdays = weekdays.sorted()
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func setOrdinaryAlarmRepeatWeekdays(id: UUID, weekdays: [Int]) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.repeatWeekdays = Set(weekdays.filter { (1...7).contains($0) }).sorted()
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmSnoozeMinutes(id: UUID, minutes: Int) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.snoozeMinutes = max(0, min(30, minutes))
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmArrivalTime(id: UUID, date: Date) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour,
              let minute = components.minute else {
            return nil
        }

        alarm.arrivalHour = hour
        alarm.arrivalMinute = minute
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmDismissChallenge(
        id: UUID,
        challenge: OrdinaryAlarmDismissChallenge
    ) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.dismissChallenge = challenge
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func updateOrdinaryAlarmSoundSelection(
        id: UUID,
        selection: AlarmSoundSelection
    ) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.soundChoice = selection.builtInFallback
        alarm.customSoundID = selection.customSoundID
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    @discardableResult
    func setOrdinaryAlarmLoudVolumeEnabled(
        id: UUID,
        isEnabled: Bool
    ) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.isLoudVolumeEnabled = isEnabled
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    func removeOrdinaryAlarm(id: UUID) throws -> OrdinaryAlarmSettings? {
        let removed = try settingsStore.removeOrdinaryAlarm(id: id)
        reload()
        return removed
    }

    func restoreOrdinaryAlarm(_ alarm: OrdinaryAlarmSettings, at index: Int) throws {
        settings = try settingsStore.restoreOrdinaryAlarm(alarm, at: index)
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
            weatherRefreshMessage = "已获取真实明早天气"
            return true
        } catch {
            weatherRefreshMessage = "天气获取失败：\(error.localizedDescription)"
            return false
        }
    }

    func markWeatherRefreshFailed(_ message: String) {
        weatherRefreshMessage = message
    }

    func refreshOrdinaryAlarmCommutePreview(id: UUID) async {
        guard let alarm = ordinaryAlarm(id: id),
              alarm.isCommuteAdjustmentEnabled,
              let route = alarm.commuteRoute else {
            ordinaryAlarmCommutePreviews[id] = nil
            return
        }

        do {
            let baseDate = alarm.nextBaseWakeUpDate(calendar: calendar) ?? Date()
            let arrivalDate = alarm.targetArrivalDate(for: baseDate, calendar: calendar)
            let focusedWeather = alarm.isWeatherAdjustmentEnabled
                ? latestMorningSummary?.focused(on: baseDate, travelDuration: route.baseDurationSeconds)
                : nil
            let weatherAdvance = settings?.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather) ?? .zero
            let result = try await transitService.calculateCommute(
                route: route,
                departureDate: baseDate,
                arrivalDate: arrivalDate
            )
            let networkDelayMinutes = Int(ceil(max(0, result.plannedDuration - result.baseDuration) / 60))
            let residualWeatherMinutes = route.effectiveMode.residualWeatherImpactMinutes(
                distanceMeters: result.distanceMeters,
                walkingDistanceMeters: result.walkingDistanceMeters,
                plannedDurationSeconds: result.plannedDuration,
                weatherRisk: alarm.isWeatherAdjustmentEnabled ? weatherAdvance.risk : 0,
                hasTrafficAwareETA: result.hasTrafficAwareETA
            )
            let totalDelayMinutes = networkDelayMinutes + residualWeatherMinutes
            let totalCommuteDuration = result.plannedDuration + TimeInterval(
                (weatherAdvance.preparationMinutes + residualWeatherMinutes) * 60
            )

            let recommendedDate = arrivalDate?.addingTimeInterval(-totalCommuteDuration)
            let arrivalAdvanceMinutes: Int
            if let recommendedDate,
               recommendedDate < baseDate {
                arrivalAdvanceMinutes = Int(ceil(baseDate.timeIntervalSince(recommendedDate) / 60))
            } else {
                arrivalAdvanceMinutes = 0
            }

            ordinaryAlarmCommutePreviews[id] = OrdinaryAlarmCommutePreview(
                trafficText: Self.trafficText(for: result.trafficLevel),
                detailText: Self.commuteDetailText(
                    route: route,
                    result: result,
                    totalDelayMinutes: totalDelayMinutes,
                    arrivalAdvanceMinutes: arrivalAdvanceMinutes
                ),
                delayMinutes: networkDelayMinutes,
                residualWeatherMinutes: residualWeatherMinutes,
                arrivalAdvanceMinutes: arrivalAdvanceMinutes,
                recommendedDepartureDate: recommendedDate,
                recommendedDepartureText: recommendedDate.map { DateFormatter.weatherAlarmTime.string(from: $0) },
                isCongested: result.trafficLevel == .congested || totalDelayMinutes > 0,
                isAvailable: true
            )
        } catch {
            ordinaryAlarmCommutePreviews[id] = OrdinaryAlarmCommutePreview(
                trafficText: "路径未更新",
                detailText: "路况查询失败，请检查路线或网络",
                delayMinutes: 0,
                residualWeatherMinutes: 0,
                arrivalAdvanceMinutes: 0,
                recommendedDepartureDate: nil,
                recommendedDepartureText: nil,
                isCongested: false,
                isAvailable: false
            )
        }
    }

    func clearOrdinaryAlarmCommutePreview(id: UUID) {
        ordinaryAlarmCommutePreviews[id] = nil
    }

    func commuteModeEvaluations(for alarmID: UUID) async -> [CommuteModeEvaluation] {
        guard let alarm = ordinaryAlarm(id: alarmID),
              alarm.isCommuteAdjustmentEnabled,
              let route = alarm.commuteRoute,
              let baseDate = alarm.nextBaseWakeUpDate(calendar: calendar),
              let arrivalDate = alarm.targetArrivalDate(for: baseDate, calendar: calendar) else {
            return []
        }

        let focusedWeather = alarm.isWeatherAdjustmentEnabled
            ? latestMorningSummary?.focused(on: baseDate, travelDuration: route.baseDurationSeconds)
            : nil
        let weatherAdvance = settings?.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather) ?? .zero
        var evaluations: [CommuteModeEvaluation] = []

        for mode in CommuteMode.allCases {
            var routeForMode = route
            routeForMode.mode = mode

            do {
                let result = try await transitService.calculateCommute(
                    route: routeForMode,
                    departureDate: baseDate,
                    arrivalDate: arrivalDate
                )
                let residualWeatherMinutes = mode.residualWeatherImpactMinutes(
                    distanceMeters: result.distanceMeters,
                    walkingDistanceMeters: result.walkingDistanceMeters,
                    plannedDurationSeconds: result.plannedDuration,
                    weatherRisk: alarm.isWeatherAdjustmentEnabled ? weatherAdvance.risk : 0,
                    hasTrafficAwareETA: result.hasTrafficAwareETA
                )
                let totalDuration = result.plannedDuration + TimeInterval(
                    (weatherAdvance.preparationMinutes + residualWeatherMinutes) * 60
                )
                let latestDepartureDate = arrivalDate.addingTimeInterval(-totalDuration)

                evaluations.append(
                    CommuteModeEvaluation(
                        mode: mode,
                        totalDuration: totalDuration,
                        latestDepartureDate: latestDepartureDate,
                        arrivalDate: arrivalDate,
                        destinationName: route.endName
                    )
                )
            } catch {
                continue
            }
        }

        return evaluations.sorted { $0.totalDuration < $1.totalDuration }
    }

    @discardableResult
    func updateOrdinaryAlarmCommuteModeSuggestion(
        id: UUID,
        mode: CommuteMode?
    ) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id) else {
            return nil
        }

        alarm.commuteModeSuggestion = mode
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        return alarm
    }

    func updateSavedCommuteRouteMode(_ mode: CommuteMode) throws {
        guard var route = settings?.commuteRoute else {
            return
        }

        route.mode = mode
        settings = try settingsStore.saveCommuteRoute(route)
        selectedCommuteMode = mode
    }

    @discardableResult
    func updateOrdinaryAlarmCommuteRouteMode(id: UUID, mode: CommuteMode) throws -> OrdinaryAlarmSettings? {
        guard var alarm = ordinaryAlarm(id: id),
              var route = alarm.commuteRoute else {
            return nil
        }

        route.mode = mode
        alarm.commuteRoute = route
        settings = try settingsStore.updateOrdinaryAlarm(alarm)
        selectedCommuteMode = mode
        return alarm
    }

    func resolveMapAddress(_ address: String) async throws -> MapResolvedLocation {
        try await transitService.resolveAddress(address)
    }

    func prepareCommuteRouteDraft(from route: CommuteRoute?) {
        commuteStartAddress = route?.startName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        commuteEndAddress = route?.endName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        commuteCity = route?.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let route {
            selectedCommuteMode = route.effectiveMode
        }
    }

    func saveCommuteAddressDraft(startAddress: String, endAddress: String, persist: Bool = true) {
        commuteStartAddress = startAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        commuteEndAddress = endAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if persist {
            userDefaults.set(commuteStartAddress, forKey: CommuteDraftKeys.startAddress)
            userDefaults.set(commuteEndAddress, forKey: CommuteDraftKeys.endAddress)
        }
    }

    @discardableResult
    func syncCommuteRouteWithMapKit() async -> Bool {
        guard !commuteStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !commuteEndAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            commuteSyncMessage = "请填写出发地和目的地"
            return false
        }

        isSyncingCommuteRoute = true
        commuteSyncMessage = nil
        let transitCity = inferredTransitCity()

        do {
            let originalStartAddress = commuteStartAddress
            let originalEndAddress = commuteEndAddress
            let route = try await transitService.syncCommuteRoute(
                startAddress: originalStartAddress,
                endAddress: originalEndAddress,
                mode: selectedCommuteMode,
                city: selectedCommuteMode == .transit ? transitCity : transitCity
            )
            settings = try settingsStore.saveCommuteRoute(route)
            commuteStartAddress = originalStartAddress
            commuteEndAddress = originalEndAddress
            userDefaults.set(commuteStartAddress, forKey: CommuteDraftKeys.startAddress)
            userDefaults.set(commuteEndAddress, forKey: CommuteDraftKeys.endAddress)
            commuteCity = route.city ?? transitCity ?? commuteCity
            commuteSyncMessage = "路线已保存，会按真实路况帮你提前"
            isSyncingCommuteRoute = false
            return true
        } catch {
            commuteSyncMessage = "路线同步失败，请检查地址或网络后再试"
        }

        isSyncingCommuteRoute = false
        return false
    }

    @discardableResult
    func syncCommuteRouteWithMapKit(forOrdinaryAlarmID alarmID: UUID) async -> Bool {
        guard !commuteStartAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !commuteEndAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            commuteSyncMessage = "请填写出发地和目的地"
            return false
        }

        isSyncingCommuteRoute = true
        commuteSyncMessage = nil
        let transitCity = inferredTransitCity()

        do {
            let originalStartAddress = commuteStartAddress
            let originalEndAddress = commuteEndAddress
            let route = try await transitService.syncCommuteRoute(
                startAddress: originalStartAddress,
                endAddress: originalEndAddress,
                mode: selectedCommuteMode,
                city: transitCity
            )
            guard var alarm = ordinaryAlarm(id: alarmID) else {
                isSyncingCommuteRoute = false
                commuteSyncMessage = "闹钟不存在，请重新打开编辑"
                return false
            }

            alarm.commuteRoute = route
            settings = try settingsStore.updateOrdinaryAlarm(alarm)
            commuteStartAddress = originalStartAddress
            commuteEndAddress = originalEndAddress
            commuteCity = route.city ?? transitCity ?? commuteCity
            commuteSyncMessage = "这条闹钟路线已保存，会单独为它计算提前"
            isSyncingCommuteRoute = false
            return true
        } catch {
            commuteSyncMessage = "路线同步失败，请检查地址或网络后再试"
        }

        isSyncingCommuteRoute = false
        return false
    }

    private func savedDraftAddress(forKey key: String) -> String? {
        let value = userDefaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
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
        guard let settings else {
            latestStatus = statusStore.loadLatestStatus()
            return
        }

        guard settings.effectiveIsWakeUpAlarmEnabled else {
            statusStore.removeLatestStatus()
            latestStatus = nil
            return
        }

        guard
              let summary = latestMorningSummary,
              let baseWakeUpDate = settings.nextBaseWakeUpDate(calendar: calendar) else {
            latestStatus = statusStore.loadLatestStatus()
            return
        }

        let focusedWeather = summary.focused(
            on: baseWakeUpDate,
            travelDuration: settings.effectiveIsCommuteAdjustmentEnabled ? settings.commuteRoute?.baseDurationSeconds : nil
        )
        let weatherBuffer = settings.isEnabled
            ? settings.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather).totalMinutes
            : 0
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
            precipitationChancePercent: summary.precipitationChancePercent,
            alarmTitle: settings.effectiveWakeUpTitle,
            alarmIconName: settings.effectiveWakeUpIconName,
            alarmThemeIndex: settings.effectiveWakeUpThemeIndex,
            repeatWeekdays: settings.effectiveWakeUpRepeatWeekdays,
            isWakeUpAlarm: true
        )

        // This is an in-app calculation preview. The shared Widget status is
        // written only after AlarmManager successfully creates the real alarm.
        latestStatus = status
    }

    private static func trafficText(for level: TrafficLevel) -> String {
        switch level {
        case .smooth:
            return "顺畅"
        case .slow:
            return "缓行"
        case .congested:
            return "拥堵"
        case .unknown:
            return "未知"
        }
    }

    private static func commuteDetailText(
        route: CommuteRoute,
        result: CommuteResult,
        totalDelayMinutes: Int,
        arrivalAdvanceMinutes: Int
    ) -> String {
        let realtimeMinutes = Int(ceil(result.realDuration / 60))
        let baseMinutes = Int(ceil(result.baseDuration / 60))
        var parts = ["\(route.effectiveMode.displayName)约 \(realtimeMinutes) 分钟"]
        if realtimeMinutes != baseMinutes {
            parts.append("常规 \(baseMinutes) 分钟")
        }
        if totalDelayMinutes > 0 {
            parts.append("路径提前 \(totalDelayMinutes) 分钟")
        }
        if arrivalAdvanceMinutes > 0 {
            parts.append("按当前闹钟出发可能迟到 \(arrivalAdvanceMinutes) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}

struct OrdinaryAlarmCommutePreview: Equatable {
    let trafficText: String
    let detailText: String
    let delayMinutes: Int
    let residualWeatherMinutes: Int
    let arrivalAdvanceMinutes: Int
    let recommendedDepartureDate: Date?
    let recommendedDepartureText: String?
    let isCongested: Bool
    let isAvailable: Bool

    init(
        trafficText: String,
        detailText: String,
        delayMinutes: Int,
        residualWeatherMinutes: Int = 0,
        arrivalAdvanceMinutes: Int,
        recommendedDepartureDate: Date?,
        recommendedDepartureText: String?,
        isCongested: Bool,
        isAvailable: Bool = true
    ) {
        self.trafficText = trafficText
        self.detailText = detailText
        self.delayMinutes = delayMinutes
        self.residualWeatherMinutes = residualWeatherMinutes
        self.arrivalAdvanceMinutes = arrivalAdvanceMinutes
        self.recommendedDepartureDate = recommendedDepartureDate
        self.recommendedDepartureText = recommendedDepartureText
        self.isCongested = isCongested
        self.isAvailable = isAvailable
    }
}

struct AlarmAdvanceDisplay: Equatable {
    let advanceMinutes: Int
    let weatherAdvanceMinutes: Int
    let routeAdvanceMinutes: Int
    let scheduledWakeUpDate: Date

    var scheduledTimeText: String {
        DateFormatter.weatherAlarmTime.string(from: scheduledWakeUpDate)
    }
}

struct CommuteModeEvaluation: Equatable {
    let mode: CommuteMode
    let totalDuration: TimeInterval
    let latestDepartureDate: Date
    let arrivalDate: Date
    let destinationName: String?

    var durationMinutes: Int {
        Int(ceil(totalDuration / 60))
    }
}

private extension DateFormatter {
    static let weatherAlarmTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
