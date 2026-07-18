import AlarmKit
import AppIntents
import ActivityKit
import Foundation
import SwiftUI
import UserNotifications

enum WeatherAlarmChallengeRequestStore {
    private static var userDefaults: UserDefaults {
        AppGroupUserDefaults.shared
    }

    private enum Keys {
        static let pendingPayload = "smartwake.challenge.pending_payload_v2"
        static let pendingAlarmID = "smartwake.challenge.pending_alarm_id"
        static let pendingAlarmTitle = "smartwake.challenge.pending_alarm_title"
        static let pendingChallenge = "smartwake.challenge.pending_challenge"
        static let pendingThemeIndex = "smartwake.challenge.pending_theme_index"
        static let pendingSoundChoice = "smartwake.challenge.pending_sound_choice"
        static let pendingLoudVolumeEnabled = "smartwake.challenge.pending_loud_volume_enabled"
        static let fallbackRetryAlarmID = "smartwake.challenge.fallback_retry_alarm_id"
        static let fallbackRetryAlarmIDs = "smartwake.challenge.fallback_retry_alarm_ids"
    }

    private struct PendingPayload: Codable {
        let alarmID: UUID
        let alarmTitle: String
        let challenge: OrdinaryAlarmDismissChallenge
        let themeIndex: Int
        let soundChoice: AlarmSoundChoice
        let customSoundID: UUID?
        let loudVolumeEnabled: Bool
    }

    static func save(
        alarmID: String,
        alarmTitle: String,
        challengeRawValue: String,
        themeIndex: Int,
        soundChoiceRawValue: String,
        customSoundIDRawValue: String,
        loudVolumeEnabled: Bool
    ) {
        guard let id = UUID(uuidString: alarmID),
              let challenge = OrdinaryAlarmDismissChallenge(rawValue: challengeRawValue),
              let soundChoice = AlarmSoundChoice(rawValue: soundChoiceRawValue),
              let data = try? JSONEncoder().encode(
                PendingPayload(
                    alarmID: id,
                    alarmTitle: alarmTitle,
                    challenge: challenge,
                    themeIndex: max(0, themeIndex),
                    soundChoice: soundChoice,
                    customSoundID: UUID(uuidString: customSoundIDRawValue),
                    loudVolumeEnabled: loudVolumeEnabled
                )
              ) else {
            return
        }

        // 一次写入完整载荷，避免系统 Intent 与 App 同时读写时看到“半个挑战”。
        userDefaults.set(data, forKey: Keys.pendingPayload)
        removeLegacyPendingPayload()
        userDefaults.synchronize()
    }

    static func load() -> PendingAlarmDismissChallenge? {
        if let data = userDefaults.data(forKey: Keys.pendingPayload),
           let payload = try? JSONDecoder().decode(PendingPayload.self, from: data),
           payload.challenge != .none {
            return PendingAlarmDismissChallenge(
                alarmID: payload.alarmID,
                alarmTitle: payload.alarmTitle,
                challenge: payload.challenge,
                themeIndex: max(0, payload.themeIndex),
                soundChoice: payload.soundChoice,
                customSoundID: payload.customSoundID,
                loudVolumeEnabled: payload.loudVolumeEnabled
            )
        }

        // 兼容从旧构建升级后尚未完成的关闭挑战。
        guard let alarmIDText = userDefaults.string(forKey: Keys.pendingAlarmID),
              let alarmID = UUID(uuidString: alarmIDText),
              let challengeRawValue = userDefaults.string(forKey: Keys.pendingChallenge),
              let challenge = OrdinaryAlarmDismissChallenge(rawValue: challengeRawValue),
              challenge != .none else {
            return nil
        }

        let title = userDefaults.string(forKey: Keys.pendingAlarmTitle) ?? "闹钟"
        let themeIndex = userDefaults.object(forKey: Keys.pendingThemeIndex) as? Int ?? 0
        let soundChoiceRawValue = userDefaults.string(forKey: Keys.pendingSoundChoice)
        let soundChoice = soundChoiceRawValue.flatMap(AlarmSoundChoice.init(rawValue:)) ?? .systemDefault
        let loudVolumeEnabled = userDefaults.bool(forKey: Keys.pendingLoudVolumeEnabled)
        return PendingAlarmDismissChallenge(
            alarmID: alarmID,
            alarmTitle: title,
            challenge: challenge,
            themeIndex: max(0, themeIndex),
            soundChoice: soundChoice,
            customSoundID: nil,
            loudVolumeEnabled: loudVolumeEnabled
        )
    }

    static func clear() {
        userDefaults.removeObject(forKey: Keys.pendingPayload)
        removeLegacyPendingPayload()
        userDefaults.removeObject(forKey: Keys.fallbackRetryAlarmID)
        userDefaults.removeObject(forKey: Keys.fallbackRetryAlarmIDs)
        userDefaults.synchronize()
    }

    private static func removeLegacyPendingPayload() {
        userDefaults.removeObject(forKey: Keys.pendingAlarmID)
        userDefaults.removeObject(forKey: Keys.pendingAlarmTitle)
        userDefaults.removeObject(forKey: Keys.pendingChallenge)
        userDefaults.removeObject(forKey: Keys.pendingThemeIndex)
        userDefaults.removeObject(forKey: Keys.pendingSoundChoice)
        userDefaults.removeObject(forKey: Keys.pendingLoudVolumeEnabled)
    }

    static func saveFallbackRetryAlarmID(_ id: UUID) {
        userDefaults.set(id.uuidString, forKey: Keys.fallbackRetryAlarmID)
        var ids = Set(userDefaults.stringArray(forKey: Keys.fallbackRetryAlarmIDs) ?? [])
        ids.insert(id.uuidString)
        userDefaults.set(ids.sorted(), forKey: Keys.fallbackRetryAlarmIDs)
        userDefaults.synchronize()
    }

    static func fallbackRetryAlarmIDs() -> [UUID] {
        var idTexts = Set(userDefaults.stringArray(forKey: Keys.fallbackRetryAlarmIDs) ?? [])
        if let legacyID = userDefaults.string(forKey: Keys.fallbackRetryAlarmID) {
            idTexts.insert(legacyID)
        }

        return idTexts.compactMap(UUID.init(uuidString:))
    }

    static func clearFallbackRetryAlarmIDs() {
        userDefaults.removeObject(forKey: Keys.fallbackRetryAlarmID)
        userDefaults.removeObject(forKey: Keys.fallbackRetryAlarmIDs)
        userDefaults.synchronize()
    }
}

struct PendingAlarmDismissChallenge: Identifiable, Equatable {
    let alarmID: UUID
    let alarmTitle: String
    let challenge: OrdinaryAlarmDismissChallenge
    let themeIndex: Int
    let soundChoice: AlarmSoundChoice
    let customSoundID: UUID?
    let loudVolumeEnabled: Bool

    var id: UUID {
        alarmID
    }

    var soundSelection: AlarmSoundSelection {
        guard let customSoundID,
              CustomAlarmSoundStore.sound(id: customSoundID) != nil else {
            return .builtIn(soundChoice)
        }
        return .custom(customSoundID)
    }
}

@available(iOS 26.0, *)
struct WeatherAlarmStopLinkedAlarmsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "关闭同步闹钟"
    static let openAppWhenRun: Bool = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {
        alarmID = ""
    }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else {
            return .result()
        }

        await MainActor.run {
            AlarmManager().stopAlarmFamily(id: id)
        }
        return .result()
    }
}

@available(iOS 26.0, *)
struct WeatherAlarmDismissChallengeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "完成关闭挑战"
    static let openAppWhenRun: Bool = true
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "Alarm Title")
    var alarmTitle: String

    @Parameter(title: "Challenge")
    var challengeRawValue: String

    @Parameter(title: "Theme")
    var themeIndex: Int

    @Parameter(title: "Sound")
    var soundChoiceRawValue: String

    @Parameter(title: "Custom Sound")
    var customSoundIDRawValue: String

    @Parameter(title: "Loud Volume")
    var loudVolumeEnabled: Bool

    init() {
        alarmID = ""
        alarmTitle = ""
        challengeRawValue = OrdinaryAlarmDismissChallenge.none.rawValue
        themeIndex = 0
        soundChoiceRawValue = AlarmSoundChoice.systemDefault.rawValue
        customSoundIDRawValue = ""
        loudVolumeEnabled = false
    }

    init(
        alarmID: UUID,
        alarmTitle: String,
        challenge: OrdinaryAlarmDismissChallenge,
        themeIndex: Int,
        soundSelection: AlarmSoundSelection,
        loudVolumeEnabled: Bool
    ) {
        self.alarmID = alarmID.uuidString
        self.alarmTitle = alarmTitle
        self.challengeRawValue = challenge.rawValue
        self.themeIndex = max(0, themeIndex)
        self.soundChoiceRawValue = soundSelection.builtInFallback.rawValue
        self.customSoundIDRawValue = soundSelection.customSoundID?.uuidString ?? ""
        self.loudVolumeEnabled = loudVolumeEnabled
    }

    func perform() async throws -> some IntentResult {
        WeatherAlarmChallengeRequestStore.save(
            alarmID: alarmID,
            alarmTitle: alarmTitle,
            challengeRawValue: challengeRawValue,
            themeIndex: themeIndex,
            soundChoiceRawValue: soundChoiceRawValue,
            customSoundIDRawValue: customSoundIDRawValue,
            loudVolumeEnabled: loudVolumeEnabled
        )

        // The system alarm has already handed control to the app. Do not create a
        // second alarm here: a delayed retry can outlive its source alarm and ring
        // later with no matching row in the UI. The app-owned audio loop continues
        // until the challenge is completed.
        await AlarmManager().cancelPendingDismissChallengeFallback()

        NotificationCenter.default.post(
            name: Notification.Name("weatherAlarmDismissChallengeURLReceived"),
            object: nil
        )
        return .result(
            opensIntent: OpenURLIntent(URL(string: "weatherwake://dismiss-challenge")!)
        )
    }

    static let fallbackNotificationIdentifier = "smartwake.challenge.fallback_handoff"
}

enum WeatherAlarmManagerError: LocalizedError {
    case authorizationDenied
    case alarmDisabled
    case cannotBuildBaseWakeUpDate

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "系统闹钟权限未开启。"
        case .alarmDisabled:
            return "闹钟已被用户关闭。"
        case .cannotBuildBaseWakeUpDate:
            return "无法根据已保存设置计算响铃时间。"
        }
    }
}

/// App 层的 AlarmManager。
///
/// 名字按需求保留为 `AlarmManager`，因此访问系统框架类型时显式写
/// `AlarmKit.AlarmManager`，避免和本类混淆。
///
/// 重要边界：
/// AlarmKit 是 iOS 26 提供的系统闹钟框架，可以让本 App 创建、更新、停止
/// “由本 App 管理的系统级闹钟”。它不是私有 Clock API，不能修改用户已经在
/// Apple“时钟”App 里手动创建的任意闹钟。
@MainActor
@available(iOS 26.0, *)
final class AlarmManager {
    private static let testAlarmID = UUID(uuidString: "7A44E73B-7E99-40E9-9D37-A3A2FD0D6266")!
    private static let wakeUpAdjustmentNotificationID = UUID(uuidString: "B6652CB2-24C5-49CE-ACF2-A455B8951030")!

    private let settingsStore: AlarmSettingsStore
    private let statusStore: WeatherAlarmStatusStore
    private let transitService: TransitService
    private let entitlementSnapshotStore: PurchaseEntitlementSnapshotStore
    private let toastPresenter: ToastPresenting
    private let systemAlarmManager: AlarmKit.AlarmManager
    private let calendar: Calendar

    init(
        settingsStore: AlarmSettingsStore = AlarmSettingsStore(),
        statusStore: WeatherAlarmStatusStore = WeatherAlarmStatusStore(),
        transitService: TransitService? = nil,
        entitlementSnapshotStore: PurchaseEntitlementSnapshotStore = PurchaseEntitlementSnapshotStore(),
        toastPresenter: ToastPresenting? = nil,
        systemAlarmManager: AlarmKit.AlarmManager = .shared,
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.statusStore = statusStore
        self.transitService = transitService ?? TransitService(
            baseDurationProvider: {
                let settings = try settingsStore.loadRequiredSettings()
                guard let baseDuration = settings.commuteRoute?.baseDurationSeconds,
                      baseDuration > 0 else {
                    throw TransitServiceError.missingBaseDuration
                }

                return baseDuration
            }
        )
        self.entitlementSnapshotStore = entitlementSnapshotStore
        self.toastPresenter = toastPresenter ?? NoopToastPresenter()
        self.systemAlarmManager = systemAlarmManager
        self.calendar = calendar
    }

    /// 请求 AlarmKit 授权。
    ///
    /// 第一次调用时，系统会弹出权限说明。请同时在 Info.plist 中填写：
    /// `NSAlarmKitUsageDescription`，例如“用于根据恶劣天气提前您的起床闹钟”。
    func requestAuthorization() async throws {
        let status: AlarmKit.AlarmManager.AuthorizationState
        switch systemAlarmManager.authorizationState {
        case .authorized:
            return
        case .denied:
            throw WeatherAlarmManagerError.authorizationDenied
        case .notDetermined:
            status = try await systemAlarmManager.requestAuthorization()
        @unknown default:
            status = try await systemAlarmManager.requestAuthorization()
        }

        guard status == .authorized else {
            throw WeatherAlarmManagerError.authorizationDenied
        }
    }

    /// 保底注册用户设置的基础起床闹钟。
    ///
    /// 这一步不依赖 WeatherKit、StoreKit、登录态或第三方地图 API。后台任务应该先确保
    /// 基础闹钟存在，再尝试追加“提前响铃”的智能逻辑。
    func ensureBasicAlarmRegistered(notifiesAdjustmentChanges: Bool = false) async throws {
        let settings = try settingsStore.loadRequiredSettings()
        guard settings.effectiveIsWakeUpAlarmEnabled else {
            cancelAlarmFamily(primaryID: settings.alarmID, secondaryID: settings.wakeUpLoudAlarmID)
            LocalWakeNotificationScheduler(settingsStore: settingsStore).cancelFallbackWakeNotification()
            statusStore.removeLatestStatus()
            return
        }

        let wakeUpDates = try nextWakeUpDates(settings: settings, advanceMinutes: 0)

        let scheduledAlarmID = try await scheduleWeatherAlarm(
            id: settings.alarmID,
            baseWakeUpDate: wakeUpDates.base,
            scheduledWakeUpDate: wakeUpDates.scheduled,
            advanceMinutes: 0,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 0,
            weatherCondition: "基础闹钟",
            precipitationChance: 0,
            alarmTitle: settings.effectiveWakeUpTitle,
            alarmIconName: settings.effectiveWakeUpIconName,
            themeIndex: settings.effectiveWakeUpThemeIndex,
            dismissChallenge: settings.effectiveWakeUpDismissChallenge,
            soundSelection: settings.effectiveWakeUpSoundSelection,
            loudVolumeEnabled: settings.effectiveIsWakeUpLoudVolumeEnabled,
            loudAlarmID: settings.wakeUpLoudAlarmID,
            repeatWeekdays: settings.effectiveWakeUpRepeatWeekdays,
            adjustmentNotificationID: Self.wakeUpAdjustmentNotificationID,
            notifiesAdjustmentChanges: notifiesAdjustmentChanges
        )

        if let latestSettings = try? settingsStore.loadSettings(),
           !latestSettings.effectiveIsWakeUpAlarmEnabled {
            cancelAlarmFamily(primaryID: scheduledAlarmID, secondaryID: latestSettings.wakeUpLoudAlarmID)
            statusStore.removeLatestStatus()
        }
    }

    func ensureAllBasicAlarmsRegistered() async throws {
        try await ensureBasicAlarmRegistered()
        let settings = try settingsStore.loadRequiredSettings()

        for alarm in settings.effectiveOrdinaryAlarms where alarm.effectiveIsEnabled {
            var basicAlarm = alarm
            basicAlarm.isWeatherAdjustmentEnabled = false
            basicAlarm.isCommuteAdjustmentEnabled = false
            try await scheduleOrdinaryAlarm(
                basicAlarm,
                weatherSummary: nil,
                notifiesAdjustmentChanges: false
            )
        }
    }

    /// Schedules a near-future AlarmKit alarm for real-device verification.
    func scheduleTestAlarm(after seconds: TimeInterval = 60) async throws {
        let testDate = Date().addingTimeInterval(max(30, seconds))
        let settings = try? settingsStore.loadSettings()

        try await scheduleWeatherAlarm(
            id: Self.testAlarmID,
            baseWakeUpDate: testDate,
            scheduledWakeUpDate: testDate,
            advanceMinutes: 0,
            weatherBufferMinutes: 0,
            commuteDelayMinutes: 0,
            weatherCondition: "试响闹钟",
            precipitationChance: 0,
            alarmTitle: settings?.effectiveWakeUpTitle ?? "试响闹钟",
            themeIndex: settings?.effectiveWakeUpThemeIndex ?? 0,
            dismissChallenge: settings?.effectiveWakeUpDismissChallenge ?? .none,
            soundSelection: settings?.effectiveWakeUpSoundSelection ?? .builtIn(.systemDefault),
            loudVolumeEnabled: settings?.effectiveIsWakeUpLoudVolumeEnabled ?? false,
            savesLatestStatus: false
        )
    }

    /// 根据目标时段天气和交通感知 ETA 更新起床闹钟。
    func updateAlarmBasedOnWeather(
        weatherSummary: MorningWeatherSummary?,
        notifiesAdjustmentChanges: Bool = true
    ) async throws {
        let settings = try settingsStore.loadRequiredSettings()

        guard settings.effectiveIsWakeUpAlarmEnabled else {
            cancelAlarmFamily(primaryID: settings.alarmID, secondaryID: settings.wakeUpLoudAlarmID)
            LocalWakeNotificationScheduler(settingsStore: settingsStore).cancelFallbackWakeNotification()
            statusStore.removeLatestStatus()
            return
        }

        let canUseWeather = settings.isEnabled && entitlementSnapshotStore.canUseWeather
        let canUseCommute = settings.effectiveIsCommuteAdjustmentEnabled && entitlementSnapshotStore.canUseGaode
        guard canUseWeather || canUseCommute else {
            try await ensureBasicAlarmRegistered()
            return
        }

        guard settings.isEnabled || settings.effectiveIsCommuteAdjustmentEnabled else {
            throw WeatherAlarmManagerError.alarmDisabled
        }

        let baseWakeUpDate = try nextWakeUpDates(settings: settings, advanceMinutes: 0).base
        let arrivalDate = settings.targetWakeUpArrivalDate(for: baseWakeUpDate, calendar: calendar)
        let focusedWeather = canUseWeather
            ? weatherSummary?.focused(
                on: baseWakeUpDate,
                travelDuration: canUseCommute ? settings.commuteRoute?.baseDurationSeconds : nil
            )
            : nil
        let weatherAdvance = settings.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather)

        let commuteTimingAdjustment: CommuteTimingAdjustment
        if canUseCommute {
            commuteTimingAdjustment = await calculateCommuteTimingAdjustmentIfPossible(
                from: settings.commuteRoute,
                departureDate: baseWakeUpDate,
                arrivalDate: arrivalDate,
                weatherRisk: canUseWeather ? weatherAdvance.risk : 0
            )
        } else {
            commuteTimingAdjustment = .zero
        }

        let weatherRouteMinutes = canUseWeather && commuteTimingAdjustment.isAvailable
            ? weatherAdvance.preparationMinutes + commuteTimingAdjustment.residualWeatherMinutes
            : 0
        let arrivalAdvanceMinutes = arrivalAdvance(
            baseWakeUpDate: baseWakeUpDate,
            arrivalDate: arrivalDate,
            commuteDuration: commuteTimingAdjustment.plannedDuration,
            extraMinutes: weatherRouteMinutes
        )
        let decision = capForUpcomingAlarm(
            SmartAdvanceCalculator.calculate(
                weatherEnabled: canUseWeather,
                routeAvailable: canUseCommute && commuteTimingAdjustment.isAvailable,
                weather: weatherAdvance,
                routeDelayMinutes: commuteTimingAdjustment.delayMinutes,
                residualWeatherMinutes: canUseWeather ? commuteTimingAdjustment.residualWeatherMinutes : 0,
                arrivalAdvanceMinutes: arrivalAdvanceMinutes
            ),
            baseWakeUpDate: baseWakeUpDate
        )

        let wakeUpDates = try nextWakeUpDates(settings: settings, advanceMinutes: decision.totalMinutes)
        let appliedWeatherCondition = focusedWeather?.weatherCondition ?? ""
        let appliedPrecipitationChance = focusedWeather?.precipitationChancePercent ?? 0

        guard try settingsStore.loadRequiredSettings().effectiveIsWakeUpAlarmEnabled else {
            cancelAlarmFamily(primaryID: settings.alarmID, secondaryID: settings.wakeUpLoudAlarmID)
            statusStore.removeLatestStatus()
            return
        }

        let scheduledAlarmID = try await scheduleWeatherAlarm(
            id: settings.alarmID,
            baseWakeUpDate: wakeUpDates.base,
            scheduledWakeUpDate: wakeUpDates.scheduled,
            advanceMinutes: decision.totalMinutes,
            weatherBufferMinutes: decision.weatherMinutes,
            commuteDelayMinutes: decision.routeMinutes,
            weatherCondition: appliedWeatherCondition,
            precipitationChance: appliedPrecipitationChance,
            alarmTitle: settings.effectiveWakeUpTitle,
            alarmIconName: settings.effectiveWakeUpIconName,
            themeIndex: settings.effectiveWakeUpThemeIndex,
            dismissChallenge: settings.effectiveWakeUpDismissChallenge,
            soundSelection: settings.effectiveWakeUpSoundSelection,
            loudVolumeEnabled: settings.effectiveIsWakeUpLoudVolumeEnabled,
            loudAlarmID: settings.wakeUpLoudAlarmID,
            repeatWeekdays: settings.effectiveWakeUpRepeatWeekdays,
            adjustmentNotificationID: Self.wakeUpAdjustmentNotificationID,
            notifiesAdjustmentChanges: notifiesAdjustmentChanges
        )

        if let latestSettings = try? settingsStore.loadSettings(),
           !latestSettings.effectiveIsWakeUpAlarmEnabled {
            cancelAlarmFamily(primaryID: scheduledAlarmID, secondaryID: latestSettings.wakeUpLoudAlarmID)
            statusStore.removeLatestStatus()
        }
    }

    func scheduleOrdinaryAlarm(
        _ alarm: OrdinaryAlarmSettings,
        weatherSummary: MorningWeatherSummary?,
        notifiesAdjustmentChanges: Bool = true
    ) async throws {
        guard alarm.effectiveIsEnabled else {
            cancelAlarmFamily(primaryID: alarm.alarmID, secondaryID: alarm.loudAlarmID)
            statusStore.removeOrdinaryAlarmStatus(for: alarm.id)
            return
        }

        let settings = try settingsStore.loadRequiredSettings()
        let canUseWeather = alarm.isWeatherAdjustmentEnabled && entitlementSnapshotStore.canUseWeather
        let canUseCommute = alarm.isCommuteAdjustmentEnabled && entitlementSnapshotStore.canUseGaode
        let baseWakeUpDate = try nextWakeUpDates(alarm: alarm, advanceMinutes: 0).base
        let arrivalDate = alarm.targetArrivalDate(for: baseWakeUpDate, calendar: calendar)
        let focusedWeather = canUseWeather
            ? weatherSummary?.focused(
                on: baseWakeUpDate,
                travelDuration: canUseCommute ? alarm.commuteRoute?.baseDurationSeconds : nil
            )
            : nil
        let weatherAdvance = settings.effectiveWeatherAdjustmentSettings.weatherAdvance(for: focusedWeather)

        let commuteTimingAdjustment: CommuteTimingAdjustment
        if canUseCommute {
            commuteTimingAdjustment = await calculateCommuteTimingAdjustmentIfPossible(
                from: alarm.commuteRoute,
                departureDate: baseWakeUpDate,
                arrivalDate: arrivalDate,
                weatherRisk: canUseWeather ? weatherAdvance.risk : 0
            )
        } else {
            commuteTimingAdjustment = .zero
        }

        let weatherRouteMinutes = canUseWeather && commuteTimingAdjustment.isAvailable
            ? weatherAdvance.preparationMinutes + commuteTimingAdjustment.residualWeatherMinutes
            : 0
        let arrivalAdvanceMinutes = arrivalAdvance(
            baseWakeUpDate: baseWakeUpDate,
            arrivalDate: arrivalDate,
            commuteDuration: commuteTimingAdjustment.plannedDuration,
            extraMinutes: weatherRouteMinutes
        )
        let decision = capForUpcomingAlarm(
            SmartAdvanceCalculator.calculate(
                weatherEnabled: canUseWeather,
                routeAvailable: canUseCommute && commuteTimingAdjustment.isAvailable,
                weather: weatherAdvance,
                routeDelayMinutes: commuteTimingAdjustment.delayMinutes,
                residualWeatherMinutes: canUseWeather ? commuteTimingAdjustment.residualWeatherMinutes : 0,
                arrivalAdvanceMinutes: arrivalAdvanceMinutes
            ),
            baseWakeUpDate: baseWakeUpDate
        )
        let wakeUpDates = try nextWakeUpDates(alarm: alarm, advanceMinutes: decision.totalMinutes)
        let appliedWeatherCondition = focusedWeather?.weatherCondition ?? ""
        let appliedPrecipitationChance = focusedWeather?.precipitationChancePercent ?? 0

        guard let latestAlarm = try settingsStore.loadRequiredSettings().effectiveOrdinaryAlarms.first(where: { $0.id == alarm.id }),
              latestAlarm.effectiveIsEnabled else {
            cancelAlarmFamily(primaryID: alarm.alarmID, secondaryID: alarm.loudAlarmID)
            statusStore.removeOrdinaryAlarmStatus(for: alarm.id)
            return
        }

        let scheduledAlarmID = try await scheduleWeatherAlarm(
            id: alarm.alarmID,
            baseWakeUpDate: wakeUpDates.base,
            scheduledWakeUpDate: wakeUpDates.scheduled,
            advanceMinutes: decision.totalMinutes,
            weatherBufferMinutes: decision.weatherMinutes,
            commuteDelayMinutes: decision.routeMinutes,
            weatherCondition: appliedWeatherCondition,
            precipitationChance: appliedPrecipitationChance,
            alarmTitle: alarm.alarmPresentationTitle,
            alarmIconName: alarm.effectiveIconName,
            themeIndex: alarm.effectiveThemeIndex,
            snoozeMinutes: alarm.effectiveSnoozeMinutes,
            dismissChallenge: alarm.effectiveDismissChallenge,
            soundSelection: alarm.effectiveSoundSelection,
            loudVolumeEnabled: alarm.effectiveIsLoudVolumeEnabled,
            loudAlarmID: alarm.loudAlarmID,
            repeatWeekdays: alarm.effectiveRepeatWeekdays,
            adjustmentNotificationID: alarm.id,
            notifiesAdjustmentChanges: notifiesAdjustmentChanges,
            savesLatestStatus: false,
            isWakeUpAlarm: false
        )

        statusStore.save(
            WeatherAlarmStatus(
                generatedAt: Date(),
                baseWakeUpDate: wakeUpDates.base,
                scheduledWakeUpDate: wakeUpDates.scheduled,
                advanceMinutes: decision.totalMinutes,
                weatherBufferMinutes: decision.weatherMinutes,
                commuteDelayMinutes: decision.routeMinutes,
                weatherCondition: appliedWeatherCondition,
                precipitationChancePercent: appliedPrecipitationChance,
                alarmTitle: alarm.effectiveTitle,
                alarmIconName: alarm.effectiveIconName,
                alarmThemeIndex: alarm.effectiveThemeIndex,
                repeatWeekdays: alarm.effectiveRepeatWeekdays,
                isWakeUpAlarm: false
            ),
            forOrdinaryAlarmID: alarm.id
        )

        let latestAlarmAfterScheduling = (try? settingsStore.loadRequiredSettings())?
            .effectiveOrdinaryAlarms
            .first(where: { $0.id == alarm.id })
        if latestAlarmAfterScheduling?.effectiveIsEnabled != true {
            cancelAlarmFamily(primaryID: scheduledAlarmID, secondaryID: latestAlarmAfterScheduling?.loudAlarmID)
            statusStore.removeOrdinaryAlarmStatus(for: alarm.id)
        }
    }

    func cancelAlarm(id: UUID) {
        try? systemAlarmManager.cancel(id: id)
    }

    func stopAlarm(id: UUID) {
        try? systemAlarmManager.stop(id: id)
    }

    func cancelAlarmFamily(primaryID: UUID, secondaryID: UUID?) {
        cancelAlarm(id: primaryID)
        if let secondaryID, secondaryID != primaryID {
            cancelAlarm(id: secondaryID)
        }
    }

    func stopAlarmFamily(id: UUID) {
        for linkedID in linkedAlarmIDs(containing: id) {
            stopAlarm(id: linkedID)
        }
    }

    private func linkedAlarmIDs(containing id: UUID) -> Set<UUID> {
        guard let settings = try? settingsStore.loadSettings() else {
            return [id]
        }

        if settings.alarmID == id || settings.wakeUpLoudAlarmID == id {
            return Set([settings.alarmID, settings.wakeUpLoudAlarmID].compactMap { $0 })
        }

        if let alarm = settings.effectiveOrdinaryAlarms.first(where: {
            $0.alarmID == id || $0.loudAlarmID == id
        }) {
            return Set([alarm.alarmID, alarm.loudAlarmID].compactMap { $0 })
        }

        return [id]
    }

    /// Removes alarms left behind by previous builds or failed ID migrations.
    /// AlarmKit only exposes alarms created by this app, so user-created Clock alarms are untouched.
    @discardableResult
    func reconcileScheduledAlarmsWithCurrentSettings() -> Int {
        var validAlarmIDs = Set<UUID>()
        var validOrdinaryStatusIDs = Set<UUID>()
        if var settings = try? settingsStore.loadSettings() {
            if settings.effectiveIsWakeUpAlarmEnabled {
                validAlarmIDs.insert(settings.alarmID)
            } else {
                statusStore.removeLatestStatus()
            }
            let enabledOrdinaryAlarms = settings.effectiveOrdinaryAlarms
                .filter(\.effectiveIsEnabled)
            validAlarmIDs.formUnion(enabledOrdinaryAlarms.map(\.alarmID))
            validOrdinaryStatusIDs.formUnion(enabledOrdinaryAlarms.map(\.id))

            settings.wakeUpLoudAlarmID = nil
            var alarms = settings.effectiveOrdinaryAlarms
            for index in alarms.indices {
                alarms[index].loudAlarmID = nil
            }
            settings.ordinaryAlarms = alarms
            try? settingsStore.save(settings)
        } else {
            statusStore.removeLatestStatus()
        }
        statusStore.retainOrdinaryAlarmStatuses(for: validOrdinaryStatusIDs)

        guard systemAlarmManager.authorizationState == .authorized else {
            return 0
        }

        // Retry alarms from older builds are never valid scheduled alarms. They can
        // otherwise fire later without a corresponding alarm in the app.
        for retryAlarmID in WeatherAlarmChallengeRequestStore.fallbackRetryAlarmIDs() {
            stopAlarm(id: retryAlarmID)
            cancelAlarm(id: retryAlarmID)
        }
        WeatherAlarmChallengeRequestStore.clearFallbackRetryAlarmIDs()
        cancelPendingDismissChallengeHandoffNotification()

        guard let scheduledAlarms = try? systemAlarmManager.alarms else {
            return 0
        }

        var removedCount = 0
        for alarm in scheduledAlarms where !validAlarmIDs.contains(alarm.id) {
            if alarm.state == .alerting || alarm.state == .countdown || alarm.state == .paused {
                stopAlarm(id: alarm.id)
            }
            cancelAlarm(id: alarm.id)
            removedCount += 1
        }

        LocalWakeNotificationScheduler(settingsStore: settingsStore).cancelFallbackWakeNotification()
        return removedCount
    }

    func cancelPendingDismissChallengeFallback() {
        cancelPendingDismissChallengeHandoffNotification()

        for retryAlarmID in WeatherAlarmChallengeRequestStore.fallbackRetryAlarmIDs() {
            stopAlarm(id: retryAlarmID)
            cancelAlarm(id: retryAlarmID)
        }
        WeatherAlarmChallengeRequestStore.clearFallbackRetryAlarmIDs()
    }

    func cancelPendingDismissChallengeHandoffNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [WeatherAlarmDismissChallengeIntent.fallbackNotificationIdentifier]
        )
    }

    /// 使用 AlarmKit 真正创建或更新系统闹钟。
    ///
    /// AlarmKit 的核心调用是：
    /// `AlarmKit.AlarmManager.shared.schedule(id:configuration:)`
    ///
    /// - `id`：业务稳定 ID。传入同一个 UUID 可以更新同一个天气闹钟。
    /// - `configuration`：描述闹钟何时响、显示什么文案、携带什么 metadata。
    /// - `schedule`：这里使用固定时间点。它不是“延迟多少分钟后响”，而是明确告诉系统：
    ///   “请在 scheduledWakeUpDate 这个 Date 触发系统闹钟”。
    ///
    /// schedule 成功后，系统负责在锁屏、动态岛/实时活动等系统表面呈现闹钟。
    /// App 不需要，也不应该用本地通知去假装 AlarmKit 闹钟。
    @discardableResult
    private func scheduleWeatherAlarm(
        id: UUID,
        baseWakeUpDate: Date,
        scheduledWakeUpDate: Date,
        advanceMinutes: Int,
        weatherBufferMinutes: Int,
        commuteDelayMinutes: Int,
        weatherCondition: String,
        precipitationChance: Double,
        alarmTitle: String = "SmartWake闹钟",
        alarmIconName: String = "alarm.fill",
        themeIndex: Int = 0,
        snoozeMinutes: Int = 0,
        dismissChallenge: OrdinaryAlarmDismissChallenge = .none,
        soundSelection: AlarmSoundSelection = .builtIn(.systemDefault),
        loudVolumeEnabled: Bool = false,
        loudAlarmID: UUID? = nil,
        repeatWeekdays: [Int] = [],
        adjustmentNotificationID: UUID? = nil,
        notifiesAdjustmentChanges: Bool = false,
        savesLatestStatus: Bool = true,
        isWakeUpAlarm: Bool = true
    ) async throws -> UUID {
        let metadata = WeatherAlarmMetadata(
            baseWakeUpDate: baseWakeUpDate,
            scheduledWakeUpDate: scheduledWakeUpDate,
            advanceMinutes: advanceMinutes,
            weatherBufferMinutes: weatherBufferMinutes,
            commuteDelayMinutes: commuteDelayMinutes,
            weatherCondition: weatherCondition,
            precipitationChancePercent: precipitationChance,
            alarmTitle: alarmTitle,
            snoozeMinutes: snoozeMinutes,
            dismissChallenge: dismissChallenge
        )

        let hasDismissChallenge = dismissChallenge != .none

        let challengeButton = hasDismissChallenge ? AlarmButton(
            text: "完成挑战",
            textColor: .white,
            systemImageName: challengeSystemImage(for: dismissChallenge)
        ) : snoozeButton(minutes: snoozeMinutes)

        let alertTitle = LocalizedStringResource(stringLiteral: alarmTitle)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: alertTitle,
                secondaryButton: challengeButton,
                secondaryButtonBehavior: secondaryButtonBehavior(
                    hasDismissChallenge: hasDismissChallenge,
                    snoozeMinutes: snoozeMinutes
                )
            )
        } else {
            let stopButton = AlarmButton(
                text: hasDismissChallenge ? "完成挑战" : "停止",
                textColor: .white,
                systemImageName: hasDismissChallenge ? challengeSystemImage(for: dismissChallenge) : "stop.circle"
            )
            alert = AlarmPresentation.Alert(
                title: alertTitle,
                stopButton: stopButton,
                secondaryButton: challengeButton,
                secondaryButtonBehavior: secondaryButtonBehavior(
                    hasDismissChallenge: hasDismissChallenge,
                    snoozeMinutes: snoozeMinutes
                )
            )
        }

        let attributes = AlarmAttributes<WeatherAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: alarmTintColor(for: themeIndex)
        )

        let schedule = alarmSchedule(
            scheduledWakeUpDate: scheduledWakeUpDate,
            repeatWeekdays: repeatWeekdays,
            canUseRepeatingSchedule: advanceMinutes == 0
        )

        typealias SystemAlarmConfiguration = AlarmKit.AlarmManager.AlarmConfiguration<WeatherAlarmMetadata>

        let makeConfiguration: (UUID) -> SystemAlarmConfiguration = { intentAlarmID in
            let countdownDuration = !hasDismissChallenge && snoozeMinutes > 0
                ? Alarm.CountdownDuration(
                    preAlert: nil,
                    postAlert: TimeInterval(snoozeMinutes * 60)
                )
                : nil

            if hasDismissChallenge {
                let challengeIntent = WeatherAlarmDismissChallengeIntent(
                    alarmID: intentAlarmID,
                    alarmTitle: alarmTitle,
                    challenge: dismissChallenge,
                    themeIndex: themeIndex,
                    soundSelection: soundSelection,
                    loudVolumeEnabled: loudVolumeEnabled
                )
                return SystemAlarmConfiguration(
                    countdownDuration: countdownDuration,
                    schedule: schedule,
                    attributes: attributes,
                    stopIntent: challengeIntent,
                    secondaryIntent: challengeIntent,
                    sound: self.alarmSound(
                        for: soundSelection,
                        loudVolumeEnabled: loudVolumeEnabled
                    )
                )
            }

            return SystemAlarmConfiguration(
                countdownDuration: countdownDuration,
                schedule: schedule,
                attributes: attributes,
                stopIntent: WeatherAlarmStopLinkedAlarmsIntent(alarmID: intentAlarmID),
                secondaryIntent: nil,
                sound: self.alarmSound(
                    for: soundSelection,
                    loudVolumeEnabled: loudVolumeEnabled
                )
            )
        }

        let scheduledAlarmID = try await scheduleWithRecovery(
            id: id,
            configurationForID: makeConfiguration
        )

        if let loudAlarmID, loudAlarmID != scheduledAlarmID {
            stopAlarm(id: loudAlarmID)
            cancelAlarm(id: loudAlarmID)
        }

        persistScheduledAlarmIDs(
            originalPrimaryID: id,
            primaryID: scheduledAlarmID
        )

        // A previous AlarmKit failure may have installed a repeating notification fallback.
        // Once AlarmKit succeeds, keeping that fallback would cause a second alarm at an old time.
        LocalWakeNotificationScheduler(settingsStore: settingsStore).cancelFallbackWakeNotification()

        if notifiesAdjustmentChanges {
            await LocalWakeNotificationScheduler(settingsStore: settingsStore).notifyAlarmAdjustmentIfChanged(
                alarmID: adjustmentNotificationID ?? id,
                alarmTitle: alarmTitle,
                baseWakeUpDate: baseWakeUpDate,
                advanceMinutes: advanceMinutes,
                weatherBufferMinutes: weatherBufferMinutes,
                commuteDelayMinutes: commuteDelayMinutes
            )
        }

        if savesLatestStatus {
            let status = WeatherAlarmStatus(
                generatedAt: Date(),
                baseWakeUpDate: baseWakeUpDate,
                scheduledWakeUpDate: scheduledWakeUpDate,
                advanceMinutes: advanceMinutes,
                weatherBufferMinutes: weatherBufferMinutes,
                commuteDelayMinutes: commuteDelayMinutes,
                weatherCondition: weatherCondition,
                precipitationChancePercent: precipitationChance,
                alarmTitle: alarmTitle,
                alarmIconName: alarmIconName,
                alarmThemeIndex: themeIndex,
                repeatWeekdays: repeatWeekdays,
                isWakeUpAlarm: isWakeUpAlarm
            )
            statusStore.save(status)
            await LocalWakeNotificationScheduler(settingsStore: settingsStore).notifyRainPreparationIfNeeded(
                alarmTitle: alarmTitle,
                status: status
            )
        }

        return scheduledAlarmID
    }

    private func alarmSchedule(
        scheduledWakeUpDate: Date,
        repeatWeekdays: [Int],
        canUseRepeatingSchedule: Bool
    ) -> Alarm.Schedule {
        let normalizedWeekdays = Set(repeatWeekdays.filter { (1...7).contains($0) }).sorted()
        guard canUseRepeatingSchedule,
              !normalizedWeekdays.isEmpty else {
            return .fixed(scheduledWakeUpDate)
        }

        let components = calendar.dateComponents([.hour, .minute], from: scheduledWakeUpDate)
        let time = Alarm.Schedule.Relative.Time(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        let weekdays = normalizedWeekdays.compactMap { localeWeekday(for: $0) }
        return .relative(.init(time: time, repeats: .weekly(weekdays)))
    }

    private func localeWeekday(for calendarWeekday: Int) -> Locale.Weekday? {
        switch calendarWeekday {
        case 1:
            return .sunday
        case 2:
            return .monday
        case 3:
            return .tuesday
        case 4:
            return .wednesday
        case 5:
            return .thursday
        case 6:
            return .friday
        case 7:
            return .saturday
        default:
            return nil
        }
    }

    private func snoozeButton(minutes: Int) -> AlarmButton? {
        guard minutes > 0 else {
            return nil
        }

        return AlarmButton(
            text: "稍后 \(minutes) 分钟",
            textColor: .white,
            systemImageName: "repeat"
        )
    }

    private func secondaryButtonBehavior(
        hasDismissChallenge: Bool,
        snoozeMinutes: Int
    ) -> AlarmPresentation.Alert.SecondaryButtonBehavior? {
        if hasDismissChallenge {
            return .custom
        }

        return snoozeMinutes > 0 ? .countdown : nil
    }

    private func alarmSound(
        for selection: AlarmSoundSelection,
        loudVolumeEnabled: Bool
    ) -> AlertConfiguration.AlertSound {
        if case .custom(let id) = selection,
           let customSoundName = CustomAlarmSoundStore.alarmKitSoundName(for: id) {
            return .named(customSoundName)
        }

        // Wake alarms always use the mastered high-output asset. The device's
        // Ring & Alerts setting remains the final system volume ceiling.
        return .named(selection.builtInFallback.alarmKitSoundName(loudVolumeEnabled: true))
    }

    private func nextWakeUpDates(
        settings: AlarmSettings,
        advanceMinutes: Int
    ) throws -> (base: Date, scheduled: Date) {
        let alarm = OrdinaryAlarmSettings(
            hour: settings.wakeUpHour,
            minute: settings.wakeUpMinute,
            title: settings.effectiveWakeUpTitle,
            repeatWeekdays: settings.effectiveWakeUpRepeatWeekdays,
            snoozeMinutes: 0
        )

        return try nextWakeUpDates(alarm: alarm, advanceMinutes: advanceMinutes)
    }

    private func nextWakeUpDates(
        hour: Int,
        minute: Int,
        advanceMinutes: Int
    ) throws -> (base: Date, scheduled: Date) {
        let alarm = OrdinaryAlarmSettings(
            hour: hour,
            minute: minute,
            repeatWeekdays: [],
            snoozeMinutes: 0
        )

        return try nextWakeUpDates(alarm: alarm, advanceMinutes: advanceMinutes)
    }

    private func nextWakeUpDates(
        alarm: OrdinaryAlarmSettings,
        advanceMinutes: Int
    ) throws -> (base: Date, scheduled: Date) {
        let now = Date()
        let minimumFireDate = now.addingTimeInterval(30)
        var searchDate = now

        for _ in 0..<8 {
            guard let baseWakeUpDate = alarm.nextBaseWakeUpDate(after: searchDate, calendar: calendar) else {
                throw WeatherAlarmManagerError.cannotBuildBaseWakeUpDate
            }

            let scheduledWakeUpDate = calendar.date(
                byAdding: .minute,
                value: -advanceMinutes,
                to: baseWakeUpDate
            ) ?? baseWakeUpDate.addingTimeInterval(TimeInterval(-advanceMinutes * 60))

            if scheduledWakeUpDate > minimumFireDate {
                return (baseWakeUpDate, scheduledWakeUpDate)
            }

            searchDate = baseWakeUpDate.addingTimeInterval(1)
        }

        throw WeatherAlarmManagerError.cannotBuildBaseWakeUpDate
    }

    private func scheduleWithRecovery(
        id: UUID,
        configurationForID: (UUID) -> AlarmKit.AlarmManager.AlarmConfiguration<WeatherAlarmMetadata>
    ) async throws -> UUID {
        do {
            _ = try await systemAlarmManager.schedule(id: id, configuration: configurationForID(id))
            return id
        } catch {
            try? systemAlarmManager.cancel(id: id)
        }

        do {
            _ = try await systemAlarmManager.schedule(id: id, configuration: configurationForID(id))
            return id
        } catch {
            let replacementID = UUID()
            _ = try await systemAlarmManager.schedule(
                id: replacementID,
                configuration: configurationForID(replacementID)
            )
            return replacementID
        }
    }

    private func persistScheduledAlarmIDs(
        originalPrimaryID: UUID,
        primaryID: UUID
    ) {
        guard var settings = try? settingsStore.loadSettings() else {
            return
        }

        if settings.alarmID == originalPrimaryID {
            settings.alarmID = primaryID
            settings.wakeUpLoudAlarmID = nil
            try? settingsStore.save(settings)
            return
        }

        guard let index = settings.effectiveOrdinaryAlarms.firstIndex(where: {
            $0.alarmID == originalPrimaryID
        }) else {
            return
        }

        var alarms = settings.effectiveOrdinaryAlarms
        alarms[index].alarmID = primaryID
        alarms[index].loudAlarmID = nil
        settings.ordinaryAlarms = alarms
        try? settingsStore.save(settings)
    }

    private func alarmTintColor(for themeIndex: Int) -> Color {
        let accents: [Color] = [
            Color(red: 0.10, green: 0.54, blue: 0.95),
            Color(red: 0.16, green: 0.72, blue: 0.37),
            Color(red: 0.05, green: 0.67, blue: 0.72),
            Color(red: 0.29, green: 0.45, blue: 0.92),
            Color(red: 0.45, green: 0.68, blue: 0.12),
            Color(red: 0.04, green: 0.58, blue: 0.88),
            Color(red: 0.12, green: 0.76, blue: 0.50),
            Color(red: 0.03, green: 0.62, blue: 0.62),
            Color(red: 0.24, green: 0.50, blue: 0.86),
            Color(red: 0.20, green: 0.67, blue: 0.43),
            Color(red: 0.94, green: 0.35, blue: 0.24),
            Color(red: 0.95, green: 0.53, blue: 0.18),
            Color(red: 0.88, green: 0.28, blue: 0.45),
            Color(red: 0.86, green: 0.62, blue: 0.10),
            Color(red: 0.76, green: 0.38, blue: 0.72),
            Color(red: 0.90, green: 0.48, blue: 0.15)
        ]

        return accents[max(0, themeIndex) % accents.count]
    }

    private func challengeSystemImage(for challenge: OrdinaryAlarmDismissChallenge) -> String {
        switch challenge {
        case .none:
            return "stop.circle"
        case .shake:
            return "iphone.radiowaves.left.and.right"
        case .math:
            return "function"
        case .steps:
            return "figure.walk"
        }
    }

    /// 调用 TransitService 计算路况导致的额外提前分钟数。
    ///
    /// 错误处理策略：
    /// - API Key 没配、网络超时、服务端失败、基础时长缺失等 TransitService 错误都在这里捕获。
    /// - 捕获后不阻断 AlarmKit schedule，直接返回 0，让闹钟退化为“仅天气逻辑”。
    /// - 同时通过 ToastPresenting 通知 UI 显示“路况检测失败”。
    ///
    /// View 不直接调用网络请求；它只负责监听 ToastMessageCenter 并展示 Toast。
    private struct CommuteTimingAdjustment {
        let delayMinutes: Int
        let plannedDuration: TimeInterval?
        let residualWeatherMinutes: Int
        let isAvailable: Bool

        static let zero = CommuteTimingAdjustment(
            delayMinutes: 0,
            plannedDuration: nil,
            residualWeatherMinutes: 0,
            isAvailable: false
        )
    }

    private func calculateCommuteTimingAdjustmentIfPossible(
        from commuteRoute: CommuteRoute?,
        departureDate: Date,
        arrivalDate: Date?,
        weatherRisk: Double
    ) async -> CommuteTimingAdjustment {
        guard let commuteRoute else {
            // TODO: 在设置页提供通勤路线配置入口。未配置路线时，只使用天气逻辑。
            return .zero
        }

        do {
            let commuteResult = try await transitService.calculateCommute(
                route: commuteRoute,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
            let delaySeconds = max(0, commuteResult.plannedDuration - commuteResult.baseDuration)
            let networkDelayMinutes = Int(ceil(delaySeconds / 60))
            let residualWeatherMinutes = commuteRoute.effectiveMode.residualWeatherImpactMinutes(
                distanceMeters: commuteResult.distanceMeters,
                walkingDistanceMeters: commuteResult.walkingDistanceMeters,
                plannedDurationSeconds: commuteResult.plannedDuration,
                weatherRisk: weatherRisk,
                hasTrafficAwareETA: commuteResult.hasTrafficAwareETA
            )

            return CommuteTimingAdjustment(
                delayMinutes: networkDelayMinutes,
                plannedDuration: commuteResult.plannedDuration,
                residualWeatherMinutes: residualWeatherMinutes,
                isAvailable: true
            )
        } catch {
            toastPresenter.showToast("路况检测失败")
            return .zero
        }
    }

    private func arrivalAdvance(
        baseWakeUpDate: Date,
        arrivalDate: Date?,
        commuteDuration: TimeInterval?,
        extraMinutes: Int
    ) -> Int {
        guard let arrivalDate, let commuteDuration else {
            return 0
        }

        let latestDepartureDate = arrivalDate.addingTimeInterval(
            -commuteDuration - TimeInterval(max(0, extraMinutes) * 60)
        )
        return latestDepartureDate < baseWakeUpDate
            ? Int(ceil(baseWakeUpDate.timeIntervalSince(latestDepartureDate) / 60))
            : 0
    }

    private func capForUpcomingAlarm(
        _ decision: SmartAdvanceDecision,
        baseWakeUpDate: Date
    ) -> SmartAdvanceDecision {
        let availableMinutes = max(0, Int(floor(baseWakeUpDate.timeIntervalSince(Date().addingTimeInterval(30)) / 60)))
        guard decision.totalMinutes > availableMinutes else {
            return decision
        }

        toastPresenter.showToast("行程时间紧张，建议立即出发")
        return decision.capped(to: availableMinutes)
    }
}
