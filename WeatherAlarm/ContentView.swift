import AVFoundation
import CoreMotion
import MapKit
import MediaPlayer
import SwiftUI
import UIKit

extension Notification.Name {
    static let weatherAlarmDismissChallengeURLReceived = Notification.Name("weatherAlarmDismissChallengeURLReceived")
}

enum SmartWakeReleasePolicy {
    static let supportURL = URL(string: "https://domenwang.github.io/smartweak-support/")!
    static let privacyURL = URL(string: "https://domenwang.github.io/smartweak-support/privacy.html")!
    static let termsURL = URL(string: "https://domenwang.github.io/smartweak-support/terms.html")!
    static let showsExperimentalFeatures = false
}

private enum SmartWakeWeatherText {
    static func precipitationAmount(_ millimeters: Double?) -> String {
        guard let millimeters, millimeters.isFinite, millimeters >= 0 else {
            return "降水量待更新"
        }

        let value = millimeters < 10
            ? String(format: "%.1f", millimeters)
            : String(format: "%.0f", millimeters)
        return "预计降水量 \(value) 毫米"
    }

    static func compactPrecipitationAmount(_ millimeters: Double?) -> String {
        guard let millimeters, millimeters.isFinite, millimeters >= 0 else {
            return "-- 毫米"
        }

        return millimeters < 10
            ? String(format: "%.1f 毫米", millimeters)
            : String(format: "%.0f 毫米", millimeters)
    }
}

@available(iOS 26.0, *)
@MainActor
struct ContentView: View {
    private static let ordinaryAlarmMigrationVersion = 1
    private static let ordinaryAlarmMigrationVersionKey = "smartwake.ordinary_alarm_schedule_migration_version"

    @EnvironmentObject private var toastCenter: ToastMessageCenter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settingsViewModel = WeatherAlarmSettingsViewModel()
    @StateObject private var locationProvider = WeatherAlarmLocationProvider()
    @ObservedObject private var subscriptionStore: StoreKitSubscriptionStore
    @StateObject private var couponStore = WeatherWakeCouponStore()
    @StateObject private var purchaseOfferStore = PurchaseOfferStore()
    private let restoreWarningNotifier = PurchaseRestoreWarningNotifier()
    @State private var activeHomeSheet: ActiveHomeSheet?
    @State private var pendingHomeSheet: ActiveHomeSheet?
    @State private var activeRouteSelection: ActiveRouteSelection?
    @State private var activeFreshEditorRouteSelection: ActiveRouteSelection?
    @State private var activeFreshEditorSheet: ActiveHomeSheet?
    @State private var pendingWakeCommuteEnable = false
    @State private var pendingCommuteEnableAlarmID: UUID?
    @State private var hasRequestedInitialWeather = false
    @State private var isSchedulingWakeAlarm = false
    @State private var isSchedulingTestAlarm = false
    @State private var schedulingOrdinaryAlarmIDs: Set<UUID> = []
    @State private var weatherHeaderRefreshID = UUID()
    @State private var pendingDismissChallenge: PendingAlarmDismissChallenge?
    @State private var didMigrateEnabledOrdinaryAlarms = false
    @State private var wakeTimeRescheduleTask: Task<Void, Never>?
    @State private var wakeArrivalRescheduleTask: Task<Void, Never>?
    @State private var ordinaryTimeRescheduleTasks: [UUID: Task<Void, Never>] = [:]
    @State private var ordinaryArrivalRescheduleTasks: [UUID: Task<Void, Never>] = [:]
    @State private var deletedAlarmUndo: DeletedAlarmUndo?
    @State private var deletedAlarmUndoMessage: String?
    @State private var deletedAlarmUndoDismissTask: Task<Void, Never>?
    @State private var pendingDismissChallengePollingTask: Task<Void, Never>?
    @StateObject private var challengeTonePlayer = AlarmChallengeTonePlayer()
    @State private var freshEditorTarget: SmartWakeFreshEditorTarget?
    @AppStorage("ww_pending_friend_coupon") private var hasPendingFriendCoupon = false

    init(subscriptionStore: StoreKitSubscriptionStore) {
        self.subscriptionStore = subscriptionStore
    }

    var body: some View {
        NavigationStack {
            SmartWakeFreshAppShell(
                wakeTimeText: wakeUpWindowSuggestedTimeText,
                wakeBaseTimeText: settingsViewModel.baseWakeUpTimeText,
                wakeAdvanceMinutes: currentWakeStatus?.advanceMinutes ?? 0,
                wakeWeatherAdvanceMinutes: currentWakeStatus?.weatherBufferMinutes ?? 0,
                wakeRouteAdvanceMinutes: currentWakeStatus?.commuteDelayMinutes ?? 0,
                alarmTitle: settingsViewModel.wakeUpTitleText,
                repeatSummary: settingsViewModel.wakeUpRepeatSummaryText,
                countdownText: freshCountdownText,
                weatherHeadline: freshWeatherHeadline,
                weatherDetail: wakeUpWindowWeatherText,
                routeDetail: freshRouteDetail,
                hourlyForecast: settingsViewModel.tomorrowHourlyForecast,
                wakeRoute: activeRouteSelection == nil && freshEditorTarget == nil
                    ? settingsViewModel.settings?.commuteRoute
                    : nil,
                totalAdvanceText: currentWakeStatus.map {
                    $0.advanceMinutes > 0 ? "总共提前 \($0.advanceMinutes) 分钟" : "不用提前"
                },
                ordinaryAlarms: settingsViewModel.ordinaryAlarms,
                ordinaryAdvanceDisplays: Dictionary(
                    uniqueKeysWithValues: settingsViewModel.ordinaryAlarms.compactMap { alarm in
                        settingsViewModel.advanceDisplay(for: alarm).map { (alarm.id, $0) }
                    }
                ),
                wakeThemeIndex: settingsViewModel.wakeUpThemeIndex,
                wakeIconName: settingsViewModel.wakeUpIconName,
                hasWeatherAccess: subscriptionStore.hasPremiumAccess,
                hasRouteAccess: subscriptionStore.hasGaodeEnhance,
                isWakeWeatherEnabled: settingsViewModel.isSmartAdjustmentEnabled,
                isWakeRouteEnabled: settingsViewModel.isCommuteAdjustmentEnabled,
                wakeEnabled: Binding(
                    get: { settingsViewModel.isWakeUpAlarmEnabled },
                    set: handleWakeUpAlarmEnabledToggle
                ),
                onEditWakeAlarm: {
                    freshEditorTarget = .wakeUp
                },
                onOpenWakeRoute: openWakeRouteFromHome,
                onEditOrdinaryAlarm: { id in
                    freshEditorTarget = .ordinary(id)
                },
                onToggleOrdinaryAlarm: handleOrdinaryAlarmEnabledToggle,
                onDeleteOrdinaryAlarm: deleteOrdinaryAlarm,
                onAddAlarm: addOrdinaryAlarmAndOpenEditor,
                onOpenPremium: {
                    showPaywall(.general)
                },
                onInvite: {
                    showHomeSheet(.invite)
                },
                onCrowdfunding: {
                    showHomeSheet(.crowdfunding)
                }
            )
            .navigationDestination(item: $activeRouteSelection) { selection in
                RouteLocationSheet(
                    selection: selection,
                    settingsViewModel: settingsViewModel,
                    onRouteSaved: handleRouteSaved
                )
            }
        }
        .sheet(item: $activeHomeSheet, onDismiss: handleHomeSheetDismissed) { sheet in
            homeSheetContent(for: sheet)
        }
        .fullScreenCover(
            item: $freshEditorTarget,
            onDismiss: handleFreshEditorDismissed
        ) { target in
            NavigationStack {
                freshEditor(for: target)
                    .navigationDestination(item: $activeFreshEditorRouteSelection) { selection in
                        RouteLocationSheet(
                            selection: selection,
                            settingsViewModel: settingsViewModel,
                            onRouteSaved: handleRouteSaved
                        )
                    }
            }
            .sheet(item: $activeFreshEditorSheet) { sheet in
                homeSheetContent(for: sheet)
            }
        }
        .task {
            settingsViewModel.reload()
            await restoreWarningNotifier.scheduleIfNeeded()
            beginPendingDismissChallengePolling()
            startInitialWeatherRefreshIfNeeded()
            await rescheduleEnabledOrdinaryAlarmsForMigration()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
                purchaseOfferStore.syncExpiredOffer()
                loadPendingDismissChallengeIfNeeded()
                beginPendingDismissChallengePolling()
                if let pendingDismissChallenge {
                    AlarmManager().cancelPendingDismissChallengeFallback()
                    challengeTonePlayer.ensurePlaying(
                        soundSelection: resolvedSoundSelection(for: pendingDismissChallenge),
                        loudVolumeEnabled: resolvedLoudVolumeEnabled(for: pendingDismissChallenge)
                    )
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherAlarmDismissChallengeURLReceived)) { _ in
            loadPendingDismissChallengeIfNeeded()
            beginPendingDismissChallengePolling()
        }
        .alert("好友送你50元代金券", isPresented: $hasPendingFriendCoupon) {
            Button("立即领取") {
                couponStore.grantUniversal50IfNeeded()
                hasPendingFriendCoupon = false
            }
        } message: {
            Text("该券仅可用于天气永久买断或路径订阅，不可用于天气月/年订阅。")
        }
        .overlay {
            if let challenge = pendingDismissChallenge {
                AlarmDismissChallengeView(challenge: challenge, tonePlayer: challengeTonePlayer) {
                    let alarmManager = AlarmManager()
                    alarmManager.stopAlarmFamily(id: challenge.alarmID)
                    alarmManager.cancelPendingDismissChallengeFallback()
                    challengeTonePlayer.stop()
                    WeatherAlarmChallengeRequestStore.clear()
                    pendingDismissChallenge = nil
                    toastCenter.showToast("\(challenge.alarmTitle) 已关闭")
                }
                .transition(.opacity)
                .zIndex(10_000)
            }
        }
        .toast(message: $toastCenter.message)
        .toast(
            message: $deletedAlarmUndoMessage,
            actionTitle: "撤销",
            action: undoDeletedAlarm
        )
    }

    private var legacyBody: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        WeatherMoodHeaderView(
                            baseTimeText: settingsViewModel.baseWakeUpTimeText,
                            suggestedTimeText: wakeUpWindowSuggestedTimeText,
                            advanceText: wakeUpWindowAdvanceText,
                            statusText: wakeUpWindowStatusText,
                            weatherText: wakeUpWindowWeatherText,
                            hourlyForecast: settingsViewModel.tomorrowHourlyForecast,
                            isRefreshing: settingsViewModel.isRefreshingWeather
                        )
                        .layoutPriority(1)
                        .id(weatherHeaderRefreshID)

                        SystemAlarmVolumeInfoPanel()

                        WakeAlarmControlPanel(
                            title: settingsViewModel.wakeUpTitleText,
                            wakeUpTimeText: settingsViewModel.baseWakeUpTimeText,
                            repeatSummaryText: settingsViewModel.wakeUpRepeatSummaryText,
                            selectedRepeatWeekdays: Set(settingsViewModel.wakeUpRepeatWeekdays),
                            themeIndex: settingsViewModel.wakeUpThemeIndex,
                            iconName: settingsViewModel.wakeUpIconName,
                            dismissChallenge: settingsViewModel.wakeUpDismissChallenge,
                            soundChoice: settingsViewModel.wakeUpSoundChoice,
                            isLoudVolumeEnabled: settingsViewModel.isWakeUpLoudVolumeEnabled,
                            weatherPreview: subscriptionStore.hasPremiumAccess ? wakeUpWeatherPreview : nil,
                            commutePreview: subscriptionStore.hasGaodeEnhance ? wakeUpCommutePreview : nil,
                            arrivalTimeText: settingsViewModel.settings?.wakeUpArrivalTimeText ?? "未设置",
                            route: settingsViewModel.settings?.commuteRoute,
                            selectedCommuteMode: settingsViewModel.settings?.commuteRoute?.effectiveMode
                                ?? settingsViewModel.selectedCommuteMode,
                            commuteStartText: routeDisplayText(
                                currentValue: settingsViewModel.commuteStartAddress,
                                fallback: settingsViewModel.settings?.commuteRoute?.startName,
                                placeholder: "点此选择出发地"
                            ),
                            commuteEndText: routeDisplayText(
                                currentValue: settingsViewModel.commuteEndAddress,
                                fallback: settingsViewModel.settings?.commuteRoute?.endName,
                                placeholder: "点此选择目的地"
                            ),
                            commuteRouteText: settingsViewModel.commuteRouteText,
                            commuteSyncMessage: settingsViewModel.commuteSyncMessage,
                            selectedWakeUpTime: $settingsViewModel.selectedWakeUpTime,
                            selectedArrivalTime: Binding(
                                get: { settingsViewModel.wakeUpArrivalDate() },
                                set: { _ in }
                            ),
                            isEnabled: Binding(
                                get: { settingsViewModel.isWakeUpAlarmEnabled },
                                set: { newValue in
                                    handleWakeUpAlarmEnabledToggle(newValue)
                                }
                            ),
                            isSmartAdjustmentEnabled: Binding(
                                get: { subscriptionStore.hasPremiumAccess && settingsViewModel.isSmartAdjustmentEnabled },
                                set: { newValue in
                                    handleSmartAdjustmentToggle(newValue)
                                }
                            ),
                            isCommuteAdjustmentEnabled: Binding(
                                get: { subscriptionStore.hasGaodeEnhance && settingsViewModel.isCommuteAdjustmentEnabled },
                                set: { newValue in
                                    handleCommuteAdjustmentToggle(newValue)
                                }
                            ),
                            isSmartAdjustmentUnlocked: subscriptionStore.hasPremiumAccess,
                            isCommuteAdjustmentUnlocked: subscriptionStore.hasGaodeEnhance,
                            isSchedulingWakeAlarm: isSchedulingWakeAlarm,
                            isSchedulingTestAlarm: isSchedulingTestAlarm,
                            onLockedWeatherTap: {
                                presentWeatherPaywall("购买后才能开启天气提前")
                            },
                            onLockedPathTap: {
                                presentPathPaywall("购买路径订阅后才能开启路径提前")
                            },
                            onTimeChanged: {
                                saveWakeUpTime()
                            },
                            onArrivalTimeChanged: { date in
                                handleWakeUpArrivalTimeChange(date)
                            },
                            onTitleChanged: { title in
                                handleWakeUpTitleChange(title)
                            },
                            onRepeatWeekdayToggle: { weekday in
                                handleWakeUpRepeatToggle(weekday)
                            },
                            onRepeatPresetSelected: { weekdays in
                                handleWakeUpRepeatPreset(weekdays)
                            },
                            onAppearanceChanged: { themeIndex, iconName in
                                handleWakeUpAppearanceChange(themeIndex: themeIndex, iconName: iconName)
                            },
                            onChallengeChanged: { challenge in
                                handleWakeUpChallengeChange(challenge)
                            },
                            onSoundChanged: { soundChoice in
                                handleWakeUpSoundChange(.builtIn(soundChoice))
                            },
                            onLoudVolumeChanged: { isEnabled in
                                handleWakeUpLoudVolumeChange(isEnabled)
                            },
                            onCommuteModeChanged: { newMode in
                                handleWakeCommuteModeChanged(newMode)
                            },
                            onSelectCommuteStart: {
                                handleRouteLocationSelection(.start)
                            },
                            onSelectCommuteEnd: {
                                handleRouteLocationSelection(.end)
                            },
                            onCollapsed: {
                                refreshWeatherHeaderPanel()
                                Task {
                                    await rescheduleWakeAlarmAfterTimeChange(
                                        showToast: false,
                                        shouldNotifyAdjustment: true
                                    )
                                }
                            },
                            onScheduleWakeAlarm: {
                                Task {
                                    await scheduleWakeAlarmFromPrimaryButton()
                                }
                            },
                            onScheduleTestAlarm: {
                                Task {
                                    await scheduleSystemTestAlarm()
                                }
                            },
                            advanceDisplay: hasAnySmartTimingAccess ? wakeUpAdvanceDisplay : nil
                        )

                        if let route = settingsViewModel.settings?.commuteRoute {
                            CommuteMapPreview(route: route)
                                .accessibilityLabel("起床闹钟路线地图")
                        }

                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    if settingsViewModel.ordinaryAlarms.isEmpty {
                        ContentUnavailableView(
                            "还没有其他闹钟",
                            systemImage: "alarm",
                            description: Text("添加一个闹钟后，点击卡片即可编辑。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 132)
                        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(settingsViewModel.ordinaryAlarms) { alarm in
                            let alarmRoute = settingsViewModel.ordinaryAlarmRoute(id: alarm.id) ?? alarm.commuteRoute
                            OrdinaryAlarmRow(
                                alarm: alarm,
                                selectedTime: Binding(
                                    get: {
                                        settingsViewModel.ordinaryAlarmDate(for: alarm)
                                    },
                                    set: { newDate in
                                        handleOrdinaryAlarmTimeChange(id: alarm.id, date: newDate)
                                    }
                                ),
                                isEnabled: Binding(
                                    get: {
                                        settingsViewModel.ordinaryAlarm(id: alarm.id)?.effectiveIsEnabled ?? alarm.effectiveIsEnabled
                                    },
                                    set: { newValue in
                                        handleOrdinaryAlarmEnabledToggle(id: alarm.id, isEnabled: newValue)
                                    }
                                ),
                                isWeatherAdjustmentEnabled: Binding(
                                    get: {
                                        subscriptionStore.hasPremiumAccess
                                            && (settingsViewModel.ordinaryAlarm(id: alarm.id)?.isWeatherAdjustmentEnabled ?? alarm.isWeatherAdjustmentEnabled)
                                    },
                                    set: { newValue in
                                        handleOrdinaryAlarmWeatherToggle(id: alarm.id, isEnabled: newValue)
                                    }
                                ),
                                isCommuteAdjustmentEnabled: Binding(
                                    get: {
                                        subscriptionStore.hasGaodeEnhance
                                            && (settingsViewModel.ordinaryAlarm(id: alarm.id)?.isCommuteAdjustmentEnabled ?? alarm.isCommuteAdjustmentEnabled)
                                    },
                                    set: { newValue in
                                        handleOrdinaryAlarmCommuteToggle(id: alarm.id, isEnabled: newValue)
                                    }
                                ),
                                isScheduling: schedulingOrdinaryAlarmIDs.contains(alarm.id),
                                scenePhase: scenePhase,
                                weatherPreview: subscriptionStore.hasPremiumAccess
                                    ? settingsViewModel.weatherPreview(for: alarm)
                                    : nil,
                                commutePreview: subscriptionStore.hasGaodeEnhance
                                    ? settingsViewModel.ordinaryAlarmCommutePreviews[alarm.id]
                                    : nil,
                                selectedArrivalTime: Binding(
                                    get: {
                                        settingsViewModel.ordinaryAlarmArrivalDate(for: alarm)
                                    },
                                    set: { newDate in
                                        handleOrdinaryAlarmArrivalTimeChange(id: alarm.id, date: newDate)
                                    }
                                ),
                                route: alarmRoute,
                                commuteStartText: routeDisplayText(
                                    currentValue: "",
                                    fallback: alarmRoute?.startName,
                                    placeholder: "点此选择出发地"
                                ),
                                commuteEndText: routeDisplayText(
                                    currentValue: "",
                                    fallback: alarmRoute?.endName,
                                    placeholder: "点此选择目的地"
                                ),
                                commuteRouteText: settingsViewModel.commuteRouteText(for: alarmRoute),
                                commuteSyncMessage: settingsViewModel.commuteSyncMessage,
                                isWeatherAdjustmentUnlocked: subscriptionStore.hasPremiumAccess,
                                isCommuteAdjustmentUnlocked: subscriptionStore.hasGaodeEnhance,
                                selectedCommuteMode: alarmRoute?.effectiveMode
                                    ?? alarm.commuteModeSuggestion
                                    ?? settingsViewModel.selectedCommuteMode,
                                onLockedWeatherTap: {
                                    presentWeatherPaywall("购买后才能开启天气提前")
                                },
                                onLockedPathTap: {
                                    presentPathPaywall("购买路径订阅后才能开启路径提前")
                                },
                                onTitleChanged: { title in
                                    handleOrdinaryAlarmTitleChange(id: alarm.id, title: title)
                                },
                                onAppearanceChanged: { themeIndex, iconName in
                                    handleOrdinaryAlarmAppearanceChange(id: alarm.id, themeIndex: themeIndex, iconName: iconName)
                                },
                                onRepeatWeekdayToggle: { weekday in
                                    handleOrdinaryAlarmRepeatToggle(id: alarm.id, weekday: weekday)
                                },
                                onRepeatPresetSelected: { weekdays in
                                    handleOrdinaryAlarmRepeatPreset(id: alarm.id, weekdays: weekdays)
                                },
                                onSnoozeChanged: { minutes in
                                    handleOrdinaryAlarmSnoozeChange(id: alarm.id, minutes: minutes)
                                },
                                onChallengeChanged: { challenge in
                                    handleOrdinaryAlarmChallengeChange(id: alarm.id, challenge: challenge)
                                },
                                onSoundChanged: { soundChoice in
                                    handleOrdinaryAlarmSoundChange(
                                        id: alarm.id,
                                        selection: .builtIn(soundChoice)
                                    )
                                },
                                onLoudVolumeChanged: { isEnabled in
                                    handleOrdinaryAlarmLoudVolumeChange(id: alarm.id, isEnabled: isEnabled)
                                },
                                onArrivalTimeChanged: { date in
                                    handleOrdinaryAlarmArrivalTimeChange(id: alarm.id, date: date)
                                },
                                onCommuteModeChanged: { newMode in
                                    handleOrdinaryCommuteModeChanged(id: alarm.id, mode: newMode)
                                },
                                onSelectCommuteStart: {
                                    handleRouteLocationSelection(.start, target: .ordinaryAlarm(alarm.id))
                                },
                                onSelectCommuteEnd: {
                                    handleRouteLocationSelection(.end, target: .ordinaryAlarm(alarm.id))
                                },
                                onSchedule: {
                                    Task {
                                        if settingsViewModel.ordinaryAlarm(id: alarm.id)?.isCommuteAdjustmentEnabled == true {
                                            await refreshCommutePreviewAndApplyArrivalDecision(for: alarm.id)
                                        } else {
                                            await rescheduleOrdinaryAlarm(id: alarm.id)
                                        }
                                    }
                                },
                                onCollapsed: {
                                    Task {
                                        await finalizeOrdinaryAlarmEdit(id: alarm.id)
                                    }
                                },
                                onAutoSave: {
                                    Task {
                                        await scheduleAutoSavedOrdinaryAlarmNotification(for: alarm.id)
                                    }
                                },
                                onRefreshCommutePreview: {
                                    Task {
                                        await refreshCommutePreviewAndApplyArrivalDecision(for: alarm.id)
                                    }
                                },
                                advanceDisplay: (subscriptionStore.hasPremiumAccess || subscriptionStore.hasGaodeEnhance)
                                    ? settingsViewModel.advanceDisplay(for: alarm)
                                    : nil
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        deleteOrdinaryAlarm(id: alarm.id)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash.fill")
                                }
                                .tint(Color(red: 0.88, green: 0.20, blue: 0.24))
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    Button {
                        addOrdinaryAlarm()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.headline.weight(.black))
                            Text("添加闹钟")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color(red: 0.05, green: 0.48, blue: 0.44), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    HomeSectionHeader(
                        title: "我的闹钟",
                        subtitle: "点击卡片编辑 · 左滑删除"
                    )
                    .textCase(nil)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HomeSectionHeader(title: "明早判断", subtitle: "数据与提前结果")

                        ForecastInsightRow(
                            title: "明早天气",
                            value: tomorrowWakeWeatherText,
                            footnote: settingsViewModel.weatherRefreshMessage ?? "按起床闹钟对应时段读取小时级预报。"
                        )

                        Divider().opacity(0.55)

                        ForecastInsightRow(
                            title: "闹钟建议",
                            value: hasAnySmartTimingAccess
                                ? settingsViewModel.suggestedAlarmTimeText
                                : settingsViewModel.baseWakeUpTimeText,
                            footnote: hasAnySmartTimingAccess
                                ? settingsViewModel.tomorrowStatusText
                                : "解锁对应功能后显示智能提前结果。"
                        )

                        Button {
                            if subscriptionStore.hasPremiumAccess {
                                Task {
                                    await refreshWeatherFromDevice(showToast: true)
                                }
                            } else {
                                presentWeatherPaywall("订阅天气功能后才能刷新天气并自动调整闹钟")
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(settingsViewModel.isRefreshingWeather ? "正在刷新" : "刷新天气")
                                Spacer()
                                if settingsViewModel.isRefreshingWeather {
                                    ProgressView()
                                }
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(red: 0.05, green: 0.38, blue: 0.36))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 42)
                            .background(Color(red: 0.84, green: 0.95, blue: 0.92), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(settingsViewModel.isRefreshingWeather)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    NavigationLink {
                        SmartTimingRuleEditor(
                            rainAdvanceMinutes: $settingsViewModel.rainAdvanceMinutes,
                            heavyRainAdvanceMinutes: $settingsViewModel.heavyRainAdvanceMinutes,
                            onRuleChanged: handleWeatherRuleChanged
                        )
                    } label: {
                        SmartTimingRulesHomeCard(
                            rainMinutes: settingsViewModel.rainAdvanceMinutes,
                            heavyRainMinutes: settingsViewModel.heavyRainAdvanceMinutes
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if SmartWakeReleasePolicy.showsExperimentalFeatures {
                    Section {
                        NavigationLink {
                            CrowdfundingView(store: subscriptionStore)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("新功能众筹中")
                                        .font(.headline)

                                    Spacer()

                                    Text("20 元起抵扣")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }

                                Text("AI 催眠、外卖提醒、提前睡觉闹钟正在路上。支持后会记入对应服务，正式上线定价时可抵扣。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                if canShowWeatherDiscountOffer {
                    PurchaseOfferCountdownBanner(offerStore: purchaseOfferStore) {
                        showPaywall(.general)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("闹钟")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showPaywall(.general)
                        } label: {
                            Label(canShowWeatherDiscountOffer ? "查看限时优惠" : "解锁智能功能", systemImage: "sparkles")
                        }

                        Button {
                            showHomeSheet(.invite)
                        } label: {
                            Label("邀请好友", systemImage: "person.2.fill")
                        }

                        if SmartWakeReleasePolicy.showsExperimentalFeatures {
                            Button {
                                showHomeSheet(.crowdfunding)
                            } label: {
                                Label("新功能计划", systemImage: "lightbulb.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(red: 0.06, green: 0.43, blue: 0.40))
                    }
                }
            }
            .sheet(item: $activeHomeSheet, onDismiss: handleHomeSheetDismissed) { sheet in
                switch sheet {
                case .paywall(let focus):
                    PaywallView(
                        store: subscriptionStore,
                        offerStore: purchaseOfferStore,
                        focus: focus
                    )
                case .invite:
                    InviteView()
                case .crowdfunding:
                    NavigationStack {
                        CrowdfundingView(store: subscriptionStore)
                    }
                }
            }
            .navigationDestination(item: $activeRouteSelection) { selection in
                RouteLocationSheet(
                    selection: selection,
                    settingsViewModel: settingsViewModel,
                    onRouteSaved: handleRouteSaved
                )
            }
            .task {
                await restoreWarningNotifier.scheduleIfNeeded()
                beginPendingDismissChallengePolling()
                startInitialWeatherRefreshIfNeeded()
                await rescheduleEnabledOrdinaryAlarmsForMigration()
            }
            .onAppear {
                settingsViewModel.reload()
                beginPendingDismissChallengePolling()
                startInitialWeatherRefreshIfNeeded()
                Task {
                    await rescheduleEnabledOrdinaryAlarmsForMigration()
                }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active {
                    settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
                    purchaseOfferStore.syncExpiredOffer()
                    loadPendingDismissChallengeIfNeeded()
                    beginPendingDismissChallengePolling()
                    if let pendingDismissChallenge {
                        AlarmManager().cancelPendingDismissChallengeFallback()
                        challengeTonePlayer.ensurePlaying(
                            soundSelection: resolvedSoundSelection(for: pendingDismissChallenge),
                            loudVolumeEnabled: resolvedLoudVolumeEnabled(for: pendingDismissChallenge)
                        )
                    }
                }
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active else {
                    return
                }
                purchaseOfferStore.refreshCountdown()
            }
            .onOpenURL { url in
                handleIncomingURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .weatherAlarmDismissChallengeURLReceived)) { _ in
                loadPendingDismissChallengeIfNeeded()
                beginPendingDismissChallengePolling()
            }
            .alert("好友送你50元代金券", isPresented: $hasPendingFriendCoupon) {
                Button("立即领取") {
                    couponStore.grantUniversal50IfNeeded()
                    hasPendingFriendCoupon = false
                }
            } message: {
                Text("该券仅可用于天气永久买断或路径订阅，不可用于天气月/年订阅。")
            }
        }
        .overlay {
            if let challenge = pendingDismissChallenge {
                AlarmDismissChallengeView(challenge: challenge, tonePlayer: challengeTonePlayer) {
                    let alarmManager = AlarmManager()
                    alarmManager.stopAlarmFamily(id: challenge.alarmID)
                    alarmManager.cancelPendingDismissChallengeFallback()
                    challengeTonePlayer.stop()
                    WeatherAlarmChallengeRequestStore.clear()
                    pendingDismissChallenge = nil
                    toastCenter.showToast("\(challenge.alarmTitle) 已关闭")
                }
                .transition(.opacity)
                .zIndex(10_000)
            }
        }
        .toast(message: $toastCenter.message)
        .toast(
            message: $deletedAlarmUndoMessage,
            actionTitle: "撤销",
            action: undoDeletedAlarm
        )
    }

    private var freshWeatherHeadline: String {
        guard let weather = wakeUpWindowFocusWeather else {
            return "明早天气待更新"
        }

        let chance = Int(weather.precipitationChancePercent.rounded())
        return "明早\(weather.weatherCondition) · 降水概率 \(chance)%"
    }

    private var freshRouteDetail: String {
        guard subscriptionStore.hasGaodeEnhance else {
            return "解锁后按通勤路况智能调整"
        }
        guard settingsViewModel.isCommuteAdjustmentEnabled else {
            return "路径提前未开启"
        }
        return wakeUpCommutePreview?.detailText
            ?? settingsViewModel.commuteRouteText
    }

    private var freshCountdownText: String {
        let nextRingDate = currentWakeStatus?.scheduledWakeUpDate
            ?? settingsViewModel.settings?.nextBaseWakeUpDate(calendar: .current)
            ?? settingsViewModel.selectedWakeUpTime
        let remainingMinutes = max(0, Int(nextRingDate.timeIntervalSinceNow / 60))
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60

        if hours > 0 {
            return "闹钟会在 \(hours) 小时 \(minutes) 分钟后响铃"
        }
        if minutes > 0 {
            return "闹钟会在 \(minutes) 分钟后响铃"
        }
        return "正在确认下一次响铃时间"
    }

    private func addOrdinaryAlarmAndOpenEditor() {
        let existingIDs = Set(settingsViewModel.ordinaryAlarms.map(\.id))
        addOrdinaryAlarm()
        if let alarm = settingsViewModel.ordinaryAlarms.first(where: { !existingIDs.contains($0.id) }) {
            freshEditorTarget = .ordinary(alarm.id)
        }
    }

    @ViewBuilder
    private func freshEditor(for target: SmartWakeFreshEditorTarget) -> some View {
        switch target {
        case .wakeUp:
            SmartWakeFreshAlarmEditor(
                screenTitle: "唤醒闹钟",
                selectedTime: $settingsViewModel.selectedWakeUpTime,
                alarmTitle: Binding(
                    get: { settingsViewModel.wakeUpTitleText },
                    set: { handleWakeUpTitleChange($0) }
                ),
                themeIndex: settingsViewModel.wakeUpThemeIndex,
                iconName: settingsViewModel.wakeUpIconName,
                snoozeMinutes: nil,
                selectedWeekdays: Set(settingsViewModel.wakeUpRepeatWeekdays),
                soundSelection: Binding(
                    get: { settingsViewModel.wakeUpSoundSelection },
                    set: { handleWakeUpSoundChange($0) }
                ),
                dismissChallenge: Binding(
                    get: { settingsViewModel.wakeUpDismissChallenge },
                    set: { handleWakeUpChallengeChange($0) }
                ),
                isLoudVolumeEnabled: Binding(
                    get: { settingsViewModel.isWakeUpLoudVolumeEnabled },
                    set: { handleWakeUpLoudVolumeChange($0) }
                ),
                isWeatherEnabled: Binding(
                    get: { settingsViewModel.isSmartAdjustmentEnabled },
                    set: { handleSmartAdjustmentToggle($0) }
                ),
                isRouteEnabled: Binding(
                    get: { settingsViewModel.isCommuteAdjustmentEnabled },
                    set: { handleCommuteAdjustmentToggle($0) }
                ),
                isAlarmEnabled: Binding(
                    get: { settingsViewModel.isWakeUpAlarmEnabled },
                    set: { handleWakeUpAlarmEnabledToggle($0) }
                ),
                selectedArrivalTime: Binding(
                    get: { settingsViewModel.wakeUpArrivalDate() },
                    set: { handleWakeUpArrivalTimeChange($0) }
                ),
                weatherUnlocked: subscriptionStore.hasPremiumAccess,
                routeUnlocked: subscriptionStore.hasGaodeEnhance,
                weatherSummary: wakeUpWindowWeatherText,
                routeSummary: freshRouteDetail,
                advanceDisplay: wakeUpAdvanceDisplay,
                route: settingsViewModel.settings?.commuteRoute,
                selectedCommuteMode: settingsViewModel.settings?.commuteRoute?.effectiveMode
                    ?? settingsViewModel.selectedCommuteMode,
                commuteStartText: routeDisplayText(
                    currentValue: settingsViewModel.commuteStartAddress,
                    fallback: settingsViewModel.settings?.commuteRoute?.startName,
                    placeholder: "点此选择出发地"
                ),
                commuteEndText: routeDisplayText(
                    currentValue: settingsViewModel.commuteEndAddress,
                    fallback: settingsViewModel.settings?.commuteRoute?.endName,
                    placeholder: "点此选择目的地"
                ),
                commuteRouteText: settingsViewModel.commuteRouteText,
                commuteSyncMessage: settingsViewModel.commuteSyncMessage,
                isSchedulingAlarm: isSchedulingWakeAlarm,
                isSchedulingTestAlarm: isSchedulingTestAlarm,
                onToggleWeekday: handleWakeUpRepeatToggle,
                onSelectWeekdays: handleWakeUpRepeatPreset,
                onAppearanceChanged: handleWakeUpAppearanceChange,
                onSnoozeChanged: nil,
                onLockedWeather: {
                    presentWeatherPaywall("购买天气功能后才能开启天气提前")
                },
                onLockedRoute: {
                    presentPathPaywall("购买路径订阅后才能开启路径提前")
                },
                onCommuteModeChanged: handleWakeCommuteModeChanged,
                onSelectCommuteStart: {
                    openFreshRouteEditor(role: .start, target: .wakeUp)
                },
                onSelectCommuteEnd: {
                    openFreshRouteEditor(role: .end, target: .wakeUp)
                },
                onScheduleTest: {
                    Task { await scheduleSystemTestAlarm() }
                },
                onDelete: nil,
                onSave: {
                    saveWakeUpTime()
                    Task {
                        await scheduleWakeAlarmFromPrimaryButton()
                    }
                }
            )

        case .ordinary(let alarmID):
            if let alarm = settingsViewModel.ordinaryAlarm(id: alarmID) {
                SmartWakeFreshAlarmEditor(
                    screenTitle: "编辑闹钟",
                    selectedTime: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)
                                .map(settingsViewModel.ordinaryAlarmDate(for:))
                                ?? settingsViewModel.ordinaryAlarmDate(for: alarm)
                        },
                        set: { handleOrdinaryAlarmTimeChange(id: alarmID, date: $0) }
                    ),
                    alarmTitle: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveTitle
                                ?? alarm.effectiveTitle
                        },
                        set: { handleOrdinaryAlarmTitleChange(id: alarmID, title: $0) }
                    ),
                    themeIndex: settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveThemeIndex
                        ?? alarm.effectiveThemeIndex,
                    iconName: settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveIconName
                        ?? alarm.effectiveIconName,
                    snoozeMinutes: settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveSnoozeMinutes
                        ?? alarm.effectiveSnoozeMinutes,
                    selectedWeekdays: Set(
                        settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveRepeatWeekdays
                            ?? alarm.effectiveRepeatWeekdays
                    ),
                    soundSelection: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveSoundSelection
                                ?? alarm.effectiveSoundSelection
                        },
                        set: { handleOrdinaryAlarmSoundChange(id: alarmID, selection: $0) }
                    ),
                    dismissChallenge: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveDismissChallenge
                                ?? alarm.effectiveDismissChallenge
                        },
                        set: { handleOrdinaryAlarmChallengeChange(id: alarmID, challenge: $0) }
                    ),
                    isLoudVolumeEnabled: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveIsLoudVolumeEnabled
                                ?? alarm.effectiveIsLoudVolumeEnabled
                        },
                        set: { handleOrdinaryAlarmLoudVolumeChange(id: alarmID, isEnabled: $0) }
                    ),
                    isWeatherEnabled: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.isWeatherAdjustmentEnabled
                                ?? alarm.isWeatherAdjustmentEnabled
                        },
                        set: { handleOrdinaryAlarmWeatherToggle(id: alarmID, isEnabled: $0) }
                    ),
                    isRouteEnabled: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.isCommuteAdjustmentEnabled
                                ?? alarm.isCommuteAdjustmentEnabled
                        },
                        set: { handleOrdinaryAlarmCommuteToggle(id: alarmID, isEnabled: $0) }
                    ),
                    isAlarmEnabled: Binding(
                        get: {
                            settingsViewModel.ordinaryAlarm(id: alarmID)?.effectiveIsEnabled
                                ?? alarm.effectiveIsEnabled
                        },
                        set: { handleOrdinaryAlarmEnabledToggle(id: alarmID, isEnabled: $0) }
                    ),
                    selectedArrivalTime: Binding(
                        get: {
                            let current = settingsViewModel.ordinaryAlarm(id: alarmID) ?? alarm
                            return settingsViewModel.ordinaryAlarmArrivalDate(for: current)
                        },
                        set: { handleOrdinaryAlarmArrivalTimeChange(id: alarmID, date: $0) }
                    ),
                    weatherUnlocked: subscriptionStore.hasPremiumAccess,
                    routeUnlocked: subscriptionStore.hasGaodeEnhance,
                    weatherSummary: freshWeatherSummary(for: alarm),
                    routeSummary: freshRouteSummary(for: alarm),
                    advanceDisplay: settingsViewModel.advanceDisplay(
                        for: settingsViewModel.ordinaryAlarm(id: alarmID) ?? alarm
                    ),
                    route: settingsViewModel.ordinaryAlarmRoute(id: alarmID) ?? alarm.commuteRoute,
                    selectedCommuteMode: settingsViewModel.ordinaryAlarmRoute(id: alarmID)?.effectiveMode
                        ?? settingsViewModel.ordinaryAlarm(id: alarmID)?.commuteModeSuggestion
                        ?? alarm.commuteModeSuggestion
                        ?? settingsViewModel.selectedCommuteMode,
                    commuteStartText: routeDisplayText(
                        currentValue: "",
                        fallback: (settingsViewModel.ordinaryAlarmRoute(id: alarmID) ?? alarm.commuteRoute)?.startName,
                        placeholder: "点此选择出发地"
                    ),
                    commuteEndText: routeDisplayText(
                        currentValue: "",
                        fallback: (settingsViewModel.ordinaryAlarmRoute(id: alarmID) ?? alarm.commuteRoute)?.endName,
                        placeholder: "点此选择目的地"
                    ),
                    commuteRouteText: settingsViewModel.commuteRouteText(
                        for: settingsViewModel.ordinaryAlarmRoute(id: alarmID) ?? alarm.commuteRoute
                    ),
                    commuteSyncMessage: settingsViewModel.commuteSyncMessage,
                    isSchedulingAlarm: schedulingOrdinaryAlarmIDs.contains(alarmID),
                    isSchedulingTestAlarm: false,
                    onToggleWeekday: {
                        handleOrdinaryAlarmRepeatToggle(id: alarmID, weekday: $0)
                    },
                    onSelectWeekdays: {
                        handleOrdinaryAlarmRepeatPreset(id: alarmID, weekdays: $0)
                    },
                    onAppearanceChanged: {
                        handleOrdinaryAlarmAppearanceChange(id: alarmID, themeIndex: $0, iconName: $1)
                    },
                    onSnoozeChanged: {
                        handleOrdinaryAlarmSnoozeChange(id: alarmID, minutes: $0)
                    },
                    onLockedWeather: {
                        presentWeatherPaywall("购买天气功能后才能开启天气提前")
                    },
                    onLockedRoute: {
                        presentPathPaywall("购买路径订阅后才能开启路径提前")
                    },
                    onCommuteModeChanged: {
                        handleOrdinaryCommuteModeChanged(id: alarmID, mode: $0)
                    },
                    onSelectCommuteStart: {
                        openFreshRouteEditor(role: .start, target: .ordinaryAlarm(alarmID))
                    },
                    onSelectCommuteEnd: {
                        openFreshRouteEditor(role: .end, target: .ordinaryAlarm(alarmID))
                    },
                    onScheduleTest: nil,
                    onDelete: {
                        deleteOrdinaryAlarm(id: alarmID)
                    },
                    onSave: {
                        Task {
                            await finalizeOrdinaryAlarmEdit(id: alarmID)
                        }
                    }
                )
            } else {
                ContentUnavailableView("闹钟不存在", systemImage: "alarm.waves.left.and.right")
            }
        }
    }

    @ViewBuilder
    private func homeSheetContent(for sheet: ActiveHomeSheet) -> some View {
        switch sheet {
        case .paywall(let focus):
            PaywallView(
                store: subscriptionStore,
                offerStore: purchaseOfferStore,
                focus: focus
            )
        case .invite:
            InviteView()
        case .crowdfunding:
            NavigationStack {
                CrowdfundingView(store: subscriptionStore)
            }
        }
    }

    private func freshWeatherSummary(for alarm: OrdinaryAlarmSettings) -> String {
        guard subscriptionStore.hasPremiumAccess else {
            return "解锁后显示降水概率、降水量和提前分钟"
        }
        guard let weather = settingsViewModel.weatherPreview(for: alarm) else {
            return "等待获取该闹钟时段的天气"
        }
        let chance = Int(weather.precipitationChancePercent.rounded())
        return "\(weather.weatherCondition) · \(chance)% · \(SmartWakeWeatherText.compactPrecipitationAmount(weather.precipitationAmountMillimeters))"
    }

    private func freshRouteSummary(for alarm: OrdinaryAlarmSettings) -> String {
        guard subscriptionStore.hasGaodeEnhance else {
            return "解锁后按路线、路况和出行方式智能调整"
        }
        let currentAlarm = settingsViewModel.ordinaryAlarm(id: alarm.id) ?? alarm
        guard currentAlarm.isCommuteAdjustmentEnabled else {
            return "路径提前未开启"
        }
        let route = settingsViewModel.ordinaryAlarmRoute(id: alarm.id) ?? currentAlarm.commuteRoute
        return settingsViewModel.commuteRouteText(for: route)
    }

    private func openFreshRouteEditor(role: RouteLocationRole, target: ActiveRouteTarget) {
        guard hasPathAccessOrPresentPaywall("购买路径订阅后才能选择出发地和目的地") else {
            return
        }

        prepareRouteDraft(for: target)
        activeFreshEditorRouteSelection = ActiveRouteSelection(
            role: role,
            target: target
        )
    }

    private func handleFreshEditorDismissed() {
        activeFreshEditorRouteSelection = nil
        activeFreshEditorSheet = nil
    }

    private func openWakeRouteFromHome() {
        switch SmartWakeRouteEntryDestination(hasRouteAccess: subscriptionStore.hasGaodeEnhance) {
        case .subscription:
            presentPathPaywall("订阅路径功能后即可设置出发地、目的地与通勤方式")
        case .routeEditor:
            handleRouteLocationSelection(.start, target: .wakeUp)
        }
    }

    private var canShowWeatherDiscountOffer: Bool {
        purchaseOfferStore.isDiscountActive && !subscriptionStore.hasPremiumAccess
    }

    private var hasAnySmartTimingAccess: Bool {
        subscriptionStore.hasPremiumAccess || subscriptionStore.hasGaodeEnhance
    }

    private var wakeUpWeatherPreview: HourlyWeatherSummary? {
        let forecast = settingsViewModel.tomorrowHourlyForecast
        guard !forecast.isEmpty else {
            return nil
        }

        let targetDate = currentWakeStatus?.baseWakeUpDate
            ?? settingsViewModel.settings?.nextBaseWakeUpDate(calendar: .current)
            ?? settingsViewModel.selectedWakeUpTime

        return forecast.min {
            abs($0.date.timeIntervalSince(targetDate)) < abs($1.date.timeIntervalSince(targetDate))
        }
    }

    private var wakeUpWindowFocusWeather: HourlyWeatherSummary? {
        settingsViewModel.tomorrowHourlyForecast.max { lhs, rhs in
            let lhsAmount = lhs.precipitationAmountMillimeters ?? -1
            let rhsAmount = rhs.precipitationAmountMillimeters ?? -1
            if lhsAmount == rhsAmount {
                return lhs.precipitationChancePercent < rhs.precipitationChancePercent
            }
            return lhsAmount < rhsAmount
        }
    }

    private var wakeUpWindowWeatherText: String {
        guard let focusWeather = wakeUpWindowFocusWeather else {
            return settingsViewModel.tomorrowWeatherText
        }

        let chance = Int(focusWeather.precipitationChancePercent.rounded())
        let amount = SmartWakeWeatherText.compactPrecipitationAmount(focusWeather.precipitationAmountMillimeters)
        return "\(focusWeather.weatherCondition) · \(chance)% · \(amount)"
    }

    private var tomorrowWakeWeatherText: String {
        if let weather = wakeUpWeatherPreview {
            let hour = DateFormatter.weatherAlarmHour.string(from: weather.date)
            let chance = Int(weather.precipitationChancePercent.rounded())
            return "明早 \(hour) \(weather.weatherCondition)，降水概率 \(chance)%，\(SmartWakeWeatherText.precipitationAmount(weather.precipitationAmountMillimeters))"
        }

        if let summary = settingsViewModel.latestMorningSummary {
            let chance = Int(summary.precipitationChancePercent.rounded())
            return "明早 \(summary.weatherCondition)，降水概率 \(chance)%，\(SmartWakeWeatherText.precipitationAmount(summary.precipitationAmountMillimeters))"
        }

        return "等待定位授权后获取明天的降水概率和预计降水量"
    }

    private var wakeUpWindowAdvanceText: String? {
        let canApplyWeather = subscriptionStore.hasPremiumAccess
            && settingsViewModel.isSmartAdjustmentEnabled
        let canApplyCommute = subscriptionStore.hasGaodeEnhance
            && settingsViewModel.isCommuteAdjustmentEnabled
        guard canApplyWeather || canApplyCommute else {
            return nil
        }

        guard let status = currentWakeStatus else {
            return "正在计算"
        }

        return status.advanceMinutes > 0 ? "\(status.advanceMinutes) 分钟" : "无需提前"
    }

    private var wakeUpWindowSuggestedTimeText: String {
        guard wakeUpWindowAdvanceText != nil,
              let status = currentWakeStatus else {
            return settingsViewModel.baseWakeUpTimeText
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: status.scheduledWakeUpDate)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private var currentWakeStatus: WeatherAlarmStatus? {
        guard let status = settingsViewModel.latestStatus,
              let nextBaseDate = settingsViewModel.settings?.nextBaseWakeUpDate(calendar: .current),
              abs(status.baseWakeUpDate.timeIntervalSince(nextBaseDate)) < 5 * 60 else {
            return nil
        }

        return status
    }

    private var wakeUpWindowStatusText: String {
        let canApplyWeather = subscriptionStore.hasPremiumAccess
            && settingsViewModel.isSmartAdjustmentEnabled
        let canApplyCommute = subscriptionStore.hasGaodeEnhance
            && settingsViewModel.isCommuteAdjustmentEnabled

        guard canApplyWeather || canApplyCommute else {
            if hasAnySmartTimingAccess {
                return "当前按基础时间响铃，开启天气或路径提前后会显示明早预计结果"
            }
            return "当前按基础时间响铃，订阅后才会显示智能调整结果"
        }

        guard let focusWeather = wakeUpWindowFocusWeather else {
            return settingsViewModel.tomorrowStatusText
        }

        let chance = Int(focusWeather.precipitationChancePercent.rounded())
        let amount = SmartWakeWeatherText.compactPrecipitationAmount(focusWeather.precipitationAmountMillimeters)
        if let latestStatus = currentWakeStatus,
           latestStatus.advanceMinutes > 0 {
            return "起床前后\(focusWeather.weatherCondition)，降水概率 \(chance)%、预计 \(amount)，将提前 \(latestStatus.advanceMinutes) 分钟响铃"
        }

        return "起床前后\(focusWeather.weatherCondition)，降水概率 \(chance)%、预计 \(amount)，当前未触发提前"
    }

    private var wakeUpCommutePreview: OrdinaryAlarmCommutePreview? {
        guard settingsViewModel.isCommuteAdjustmentEnabled,
              let route = settingsViewModel.settings?.commuteRoute else {
            return nil
        }

        let baseMinutes = max(1, Int(ceil(route.baseDurationSeconds / 60)))
        let delayMinutes = settingsViewModel.latestStatus?.commuteDelayMinutes ?? 0
        let detailText = delayMinutes > 0
            ? "\(route.effectiveMode.displayName)约 \(baseMinutes) 分钟 · 路径自动提前 \(delayMinutes) 分钟"
            : "\(route.effectiveMode.displayName)约 \(baseMinutes) 分钟"

        return OrdinaryAlarmCommutePreview(
            trafficText: delayMinutes > 0 ? "需提前" : "顺畅",
            detailText: detailText,
            delayMinutes: delayMinutes,
            arrivalAdvanceMinutes: 0,
            recommendedDepartureDate: nil,
            recommendedDepartureText: nil,
            isCongested: delayMinutes > 0
        )
    }

    private var wakeUpAdvanceDisplay: AlarmAdvanceDisplay? {
        guard let status = currentWakeStatus,
              status.advanceMinutes > 0,
              status.baseWakeUpDate > Date() else {
            return nil
        }

        return AlarmAdvanceDisplay(
            advanceMinutes: status.advanceMinutes,
            weatherAdvanceMinutes: status.weatherBufferMinutes,
            routeAdvanceMinutes: status.commuteDelayMinutes,
            scheduledWakeUpDate: status.scheduledWakeUpDate
        )
    }

    private func refreshWeatherHeaderPanel() {
        weatherHeaderRefreshID = UUID()
    }

    private func startInitialWeatherRefreshIfNeeded() {
        let hasWeatherEnabledAlarm = settingsViewModel.isSmartAdjustmentEnabled
            || settingsViewModel.ordinaryAlarms.contains {
                $0.effectiveIsEnabled && $0.isWeatherAdjustmentEnabled
            }
        guard !hasRequestedInitialWeather,
              hasWeatherEnabledAlarm,
              subscriptionStore.hasPremiumAccess else {
            return
        }

        hasRequestedInitialWeather = true
        Task {
            await refreshWeatherFromDevice(showToast: false)
        }
    }

    private func handleHomeSheetDismissed() {
        guard let nextSheet = pendingHomeSheet else {
            return
        }

        pendingHomeSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard activeHomeSheet == nil,
                  pendingDismissChallenge == nil,
                  WeatherAlarmChallengeRequestStore.load() == nil else {
                return
            }
            activeHomeSheet = nextSheet
        }
    }

    private func loadPendingDismissChallengeIfNeeded() {
        if let challenge = WeatherAlarmChallengeRequestStore.load() {
            activatePendingDismissChallenge(challenge)
        }
    }

    private func beginPendingDismissChallengePolling() {
        pendingDismissChallengePollingTask?.cancel()
        pendingDismissChallengePollingTask = Task { @MainActor in
            var delayMilliseconds = 100
            for _ in 0..<24 {
                if let challenge = WeatherAlarmChallengeRequestStore.load() {
                    activatePendingDismissChallenge(challenge)
                    break
                }

                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                if Task.isCancelled {
                    break
                }
                delayMilliseconds = min(2_000, delayMilliseconds * 2)
            }

            pendingDismissChallengePollingTask = nil
        }
    }

    private func activatePendingDismissChallenge(_ challenge: PendingAlarmDismissChallenge) {
        AlarmManager().cancelPendingDismissChallengeFallback()
        activeHomeSheet = nil
        pendingHomeSheet = nil
        activeRouteSelection = nil
        pendingDismissChallenge = challenge
        if challenge.challenge != .none {
            challengeTonePlayer.ensurePlaying(
                soundSelection: resolvedSoundSelection(for: challenge),
                loudVolumeEnabled: resolvedLoudVolumeEnabled(for: challenge)
            )
        }
    }

    private func resolvedSoundSelection(for challenge: PendingAlarmDismissChallenge) -> AlarmSoundSelection {
        guard let settings = settingsViewModel.settings else {
            return challenge.soundSelection
        }

        if settings.alarmID == challenge.alarmID || settings.wakeUpLoudAlarmID == challenge.alarmID {
            return settings.effectiveWakeUpSoundSelection
        }

        return settings.effectiveOrdinaryAlarms.first(where: {
            $0.alarmID == challenge.alarmID || $0.loudAlarmID == challenge.alarmID
        })?.effectiveSoundSelection ?? challenge.soundSelection
    }

    private func resolvedLoudVolumeEnabled(for challenge: PendingAlarmDismissChallenge) -> Bool {
        guard let settings = settingsViewModel.settings else {
            return challenge.loudVolumeEnabled
        }

        if settings.alarmID == challenge.alarmID || settings.wakeUpLoudAlarmID == challenge.alarmID {
            return settings.effectiveIsWakeUpLoudVolumeEnabled
        }

        return settings.effectiveOrdinaryAlarms.first(where: {
            $0.alarmID == challenge.alarmID || $0.loudAlarmID == challenge.alarmID
        })?.effectiveIsLoudVolumeEnabled ?? challenge.loudVolumeEnabled
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "weatherwake" else {
            return
        }

        let target = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard target == "dismiss-challenge" else {
            return
        }

        loadPendingDismissChallengeIfNeeded()
        beginPendingDismissChallengePolling()
    }

    private func refreshWeatherFromDevice(showToast: Bool) async {
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let didRefresh = await settingsViewModel.refreshWeatherWithCurrentLocation(location)
            if showToast {
                toastCenter.showToast(didRefresh ? "已刷新真实天气" : "天气获取失败")
            }
        } catch WeatherAlarmLocationProviderError.authorizationDenied {
            settingsViewModel.markWeatherRefreshFailed("定位权限未开启，无法查询真实天气")
            if showToast {
                toastCenter.showToast("请在系统设置中允许定位，才能获取真实天气")
            }
        } catch {
            settingsViewModel.markWeatherRefreshFailed("定位失败，暂时无法查询真实天气")
            if showToast {
                toastCenter.showToast("定位失败，暂时无法获取真实天气")
            }
        }
    }

    private func handleSmartAdjustmentToggle(_ isEnabled: Bool) {
        guard !isEnabled || subscriptionStore.hasPremiumAccess else {
            presentWeatherPaywall("购买天气功能后才能开启天气提前")
            return
        }

        Task {
            await updateSmartAdjustment(isEnabled)
        }
    }

    private func handleWeatherRuleChanged() {
        settingsViewModel.saveWeatherAdjustmentSettings()
        guard settingsViewModel.isSmartAdjustmentEnabled else {
            return
        }

        Task {
            await rescheduleWakeAlarmAfterTimeChange(showToast: false)
        }
    }

    private func presentWeatherPaywall(_ message: String) {
        toastCenter.showToast(message)
        showPaywall(.weather)
    }

    private func presentPathPaywall(_ message: String = "购买路径订阅后才能使用路径提前") {
        toastCenter.showToast(message)
        showPaywall(.path)
    }

    private func showPaywall(_ focus: SubscriptionPaywallFocus) {
        presentHomeSheet(.paywall(focus))
    }

    private func showHomeSheet(_ sheet: ActiveHomeSheet) {
        presentHomeSheet(sheet)
    }

    private func presentHomeSheet(_ sheet: ActiveHomeSheet) {
        guard pendingDismissChallenge == nil,
              WeatherAlarmChallengeRequestStore.load() == nil else {
            toastCenter.showToast("请先完成当前闹钟关闭任务")
            return
        }

        if freshEditorTarget != nil {
            guard activeFreshEditorSheet?.id != sheet.id else {
                return
            }
            activeFreshEditorSheet = sheet
            return
        }

        guard let activeHomeSheet else {
            pendingHomeSheet = nil
            self.activeHomeSheet = sheet
            return
        }

        guard activeHomeSheet.id != sheet.id else {
            return
        }

        pendingHomeSheet = sheet
        self.activeHomeSheet = nil
    }

    private func hasPathAccessOrPresentPaywall(_ message: String = "购买路径订阅后才能使用路径提前") -> Bool {
        guard subscriptionStore.hasGaodeEnhance else {
            presentPathPaywall(message)
            return false
        }

        return true
    }

    private func handleWakeCommuteModeChanged(_ mode: CommuteMode) {
        guard hasPathAccessOrPresentPaywall("购买路径订阅后才能切换并同步通勤路线") else {
            return
        }

        settingsViewModel.selectedCommuteMode = mode

        Task {
            await settingsViewModel.syncCommuteRouteWithMapKit()
            if settingsViewModel.isCommuteAdjustmentEnabled {
                await rescheduleWakeAlarmAfterTimeChange()
            }
        }
    }

    private func handleOrdinaryCommuteModeChanged(id: UUID, mode: CommuteMode) {
        guard hasPathAccessOrPresentPaywall("购买路径订阅后才能切换并同步通勤路线") else {
            return
        }

        settingsViewModel.selectedCommuteMode = mode

        do {
            _ = try settingsViewModel.updateOrdinaryAlarmCommuteModeSuggestion(id: id, mode: mode)
        } catch {
            toastCenter.showToast("交通方式保存失败")
            return
        }

        guard let route = settingsViewModel.ordinaryAlarmRoute(id: id) else {
            return
        }

        settingsViewModel.prepareCommuteRouteDraft(from: route)

        do {
            _ = try settingsViewModel.updateOrdinaryAlarmCommuteRouteMode(id: id, mode: mode)
        } catch {
            toastCenter.showToast("交通方式保存失败")
            return
        }

        Task {
            await settingsViewModel.syncCommuteRouteWithMapKit(forOrdinaryAlarmID: id)
            if settingsViewModel.ordinaryAlarm(id: id)?.isCommuteAdjustmentEnabled == true {
                await refreshCommutePreviewAndApplyArrivalDecision(for: id)
            }
        }
    }

    private func handleRouteSaved(_ selection: ActiveRouteSelection) {
        switch selection.target {
        case .wakeUp:
            Task {
                if pendingWakeCommuteEnable {
                    pendingWakeCommuteEnable = false
                    do {
                        try settingsViewModel.setCommuteAdjustmentEnabled(true)
                        await rescheduleWakeAlarmAfterTimeChange()
                        toastCenter.showToast("路径已保存，通勤调整已开启")
                    } catch {
                        toastCenter.showToast("路径已保存，但开启通勤调整失败")
                    }
                } else if settingsViewModel.isCommuteAdjustmentEnabled {
                    await rescheduleWakeAlarmAfterTimeChange()
                }
            }
        case .ordinaryAlarm(let alarmID):
            Task {
                if pendingCommuteEnableAlarmID == alarmID {
                    pendingCommuteEnableAlarmID = nil
                    _ = try? settingsViewModel.setOrdinaryAlarmCommuteAdjustment(
                        id: alarmID,
                        isEnabled: true
                    )
                }
                await refreshCommutePreviewAndApplyArrivalDecision(for: alarmID)
            }
        }
    }

    private func handleRouteLocationSelection(
        _ role: RouteLocationRole,
        target: ActiveRouteTarget = .wakeUp
    ) {
        guard hasPathAccessOrPresentPaywall("购买路径订阅后才能选择出发地和目的地") else {
            return
        }

        prepareRouteDraft(for: target)
        activeRouteSelection = ActiveRouteSelection(role: role, target: target)
    }

    private func prepareRouteDraft(for target: ActiveRouteTarget) {
        switch target {
        case .wakeUp:
            settingsViewModel.prepareCommuteRouteDraft(from: settingsViewModel.settings?.commuteRoute)
        case .ordinaryAlarm(let alarmID):
            settingsViewModel.prepareCommuteRouteDraft(from: settingsViewModel.ordinaryAlarmRoute(id: alarmID))
        }
    }

    private func saveWakeUpTime() {
        wakeTimeRescheduleTask?.cancel()
        wakeTimeRescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                return
            }

            settingsViewModel.saveSelectedWakeUpTime()
            refreshWeatherHeaderPanel()
            await rescheduleWakeAlarmAfterTimeChange(showToast: false)
        }
    }

    private func saveWakeUpTimeImmediately() {
        wakeTimeRescheduleTask?.cancel()
        settingsViewModel.saveSelectedWakeUpTime()
        refreshWeatherHeaderPanel()
        Task {
            await rescheduleWakeAlarmAfterTimeChange(showToast: false)
        }
    }

    private func handleWakeUpArrivalTimeChange(_ date: Date) {
        do {
            try settingsViewModel.updateWakeUpArrivalTime(date)
        } catch {
            toastCenter.showToast("到达时间保存失败")
            return
        }

        wakeArrivalRescheduleTask?.cancel()
        wakeArrivalRescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else {
                return
            }

            await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            refreshWeatherHeaderPanel()
            wakeArrivalRescheduleTask = nil
        }
    }

    private func handleWakeUpTitleChange(_ title: String) {
        do {
            try settingsViewModel.updateWakeUpTitle(title)
            Task {
                await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            }
        } catch {
            toastCenter.showToast("起床闹钟名称保存失败")
        }
    }

    private func handleWakeUpRepeatToggle(_ weekday: Int) {
        do {
            try settingsViewModel.toggleWakeUpRepeatWeekday(weekday)
            Task {
                await rescheduleWakeAlarmAfterTimeChange()
            }
        } catch {
            toastCenter.showToast("起床闹钟重复设置保存失败")
        }
    }

    private func handleWakeUpRepeatPreset(_ weekdays: [Int]) {
        do {
            try settingsViewModel.setWakeUpRepeatWeekdays(weekdays)
            Task {
                await rescheduleWakeAlarmAfterTimeChange()
            }
        } catch {
            toastCenter.showToast("起床闹钟重复设置保存失败")
        }
    }

    private func handleWakeUpAppearanceChange(themeIndex: Int, iconName: String) {
        do {
            try settingsViewModel.updateWakeUpAppearance(themeIndex: themeIndex, iconName: iconName)
            Task {
                await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            }
        } catch {
            toastCenter.showToast("起床闹钟外观保存失败")
        }
    }

    private func handleWakeUpChallengeChange(_ challenge: OrdinaryAlarmDismissChallenge) {
        do {
            try settingsViewModel.updateWakeUpDismissChallenge(challenge)
            Task {
                await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            }
        } catch {
            toastCenter.showToast("起床闹钟关闭方式保存失败")
        }
    }

    private func handleWakeUpSoundChange(_ selection: AlarmSoundSelection) {
        do {
            try settingsViewModel.updateWakeUpSoundSelection(selection)
            Task {
                await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            }
        } catch {
            toastCenter.showToast("起床闹钟铃声保存失败")
        }
    }

    private func handleWakeUpLoudVolumeChange(_ isEnabled: Bool) {
        do {
            try settingsViewModel.setWakeUpLoudVolumeEnabled(isEnabled)
            Task {
                await rescheduleWakeAlarmAfterTimeChange(showToast: false)
            }
        } catch {
            toastCenter.showToast("更大音量设置保存失败")
        }
    }

    private func handleWakeUpAlarmEnabledToggle(_ isEnabled: Bool) {
        if settingsViewModel.settings == nil {
            settingsViewModel.saveSelectedWakeUpTime()
        }

        do {
            try settingsViewModel.setWakeUpAlarmEnabled(isEnabled)

            if isEnabled {
                Task {
                    await rescheduleWakeAlarmAfterTimeChange()
                }
            } else if let settings = settingsViewModel.settings {
                wakeTimeRescheduleTask?.cancel()
                wakeTimeRescheduleTask = nil
                wakeArrivalRescheduleTask?.cancel()
                wakeArrivalRescheduleTask = nil

                let alarmManager = AlarmManager()
                alarmManager.stopAlarmFamily(id: settings.alarmID)
                alarmManager.cancelAlarmFamily(
                    primaryID: settings.alarmID,
                    secondaryID: settings.wakeUpLoudAlarmID
                )
                LocalWakeNotificationScheduler().cancelFallbackWakeNotification()
                toastCenter.showToast("\(settingsViewModel.baseWakeUpTimeText) 起床闹钟已停用")
            }

            refreshWeatherHeaderPanel()
        } catch {
            toastCenter.showToast("起床闹钟开关保存失败")
        }
    }

    private func scheduleWakeAlarmFromPrimaryButton() async {
        isSchedulingWakeAlarm = true
        defer {
            isSchedulingWakeAlarm = false
            refreshWeatherHeaderPanel()
        }

        wakeTimeRescheduleTask?.cancel()
        settingsViewModel.saveSelectedWakeUpTime()
        await rescheduleWakeAlarmAfterTimeChange(shouldNotifyAdjustment: true)
    }

    private func saveWakeUpTimeAndRescheduleAlarm() {
        saveWakeUpTimeImmediately()
    }

    private func rescheduleWakeAlarmAfterTimeChange(
        showToast: Bool = true,
        shouldNotifyAdjustment: Bool = false
    ) async {
        guard settingsViewModel.settings != nil else {
            return
        }

        guard settingsViewModel.isWakeUpAlarmEnabled else {
            if let settings = settingsViewModel.settings {
                let alarmManager = AlarmManager()
                alarmManager.cancelAlarmFamily(
                    primaryID: settings.alarmID,
                    secondaryID: settings.wakeUpLoudAlarmID
                )
            }
            LocalWakeNotificationScheduler().cancelFallbackWakeNotification()
            return
        }

        do {
            let alarmManager = AlarmManager()
            try await alarmManager.requestAuthorization()

            let shouldApplySmartTiming = settingsViewModel.isSmartAdjustmentEnabled || settingsViewModel.isCommuteAdjustmentEnabled

            if shouldApplySmartTiming {
                try await alarmManager.updateAlarmBasedOnWeather(
                    weatherSummary: settingsViewModel.latestMorningSummary,
                    notifiesAdjustmentChanges: shouldNotifyAdjustment
                )
            } else {
                try await alarmManager.ensureBasicAlarmRegistered(
                    notifiesAdjustmentChanges: shouldNotifyAdjustment
                )
            }

            settingsViewModel.reload()
            if showToast {
                toastCenter.showToast("系统闹钟时间已更新")
            }
        } catch {
            do {
                try await LocalWakeNotificationScheduler().rescheduleFallbackWakeNotification()
                toastCenter.showToast("系统闹钟暂不可用，已改用通知提醒")
            } catch {
                toastCenter.showToast("闹钟更新失败，请检查闹钟/通知权限")
            }
        }
    }

    private func scheduleSystemTestAlarm() async {
        isSchedulingTestAlarm = true
        defer {
            isSchedulingTestAlarm = false
        }

        settingsViewModel.saveSelectedWakeUpTime()

        do {
            let alarmManager = AlarmManager()
            try await alarmManager.requestAuthorization()
            try await alarmManager.scheduleTestAlarm(after: 60)
            toastCenter.showToast("1分钟后试响系统闹钟")
        } catch {
            do {
                try await LocalWakeNotificationScheduler().scheduleTestNotification(afterSeconds: 60)
                toastCenter.showToast("系统闹钟暂不可用，1分钟后用通知试响")
            } catch {
                toastCenter.showToast("试响失败，请检查闹钟/通知权限")
            }
        }
    }

    private func addOrdinaryAlarm() {
        do {
            let alarm = try settingsViewModel.addOrdinaryAlarm()
            toastCenter.showToast("已添加 \(alarm.timeText) 闹钟")
            Task {
                await rescheduleOrdinaryAlarm(id: alarm.id)
            }
        } catch {
            toastCenter.showToast("添加闹钟失败，请先设置主闹钟时间")
        }
    }

    private func handleOrdinaryAlarmTimeChange(id: UUID, date: Date) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmTime(id: id, date: date),
               alarm.effectiveIsEnabled {
                scheduleDebouncedOrdinaryAlarmReschedule(id: alarm.id)
            }
        } catch {
            toastCenter.showToast("闹钟时间保存失败")
        }
    }

    private func handleOrdinaryAlarmEnabledToggle(id: UUID, isEnabled: Bool) {
        do {
            if let alarm = try settingsViewModel.setOrdinaryAlarmEnabled(id: id, isEnabled: isEnabled) {
                if isEnabled {
                    Task {
                        await rescheduleOrdinaryAlarm(id: alarm.id)
                    }
                } else {
                    ordinaryTimeRescheduleTasks[id]?.cancel()
                    ordinaryTimeRescheduleTasks[id] = nil
                    ordinaryArrivalRescheduleTasks[id]?.cancel()
                    ordinaryArrivalRescheduleTasks[id] = nil
                    let alarmManager = AlarmManager()
                    alarmManager.stopAlarmFamily(id: alarm.alarmID)
                    alarmManager.cancelAlarmFamily(
                        primaryID: alarm.alarmID,
                        secondaryID: alarm.loudAlarmID
                    )
                    toastCenter.showToast("\(alarm.timeText) 已停用")
                }
            }
        } catch {
            toastCenter.showToast("闹钟开关保存失败")
        }
    }

    private func handleOrdinaryAlarmTitleChange(id: UUID, title: String) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmTitle(id: id, title: title),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("闹钟标签保存失败")
        }
    }

    private func handleOrdinaryAlarmAppearanceChange(id: UUID, themeIndex: Int, iconName: String) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmAppearance(
                id: id,
                themeIndex: themeIndex,
                iconName: iconName
            ),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("闹钟外观保存失败")
        }
    }

    private func handleOrdinaryAlarmRepeatToggle(id: UUID, weekday: Int) {
        do {
            if let alarm = try settingsViewModel.toggleOrdinaryAlarmRepeatWeekday(id: id, weekday: weekday),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id)
                }
            }
        } catch {
            toastCenter.showToast("重复设置保存失败")
        }
    }

    private func handleOrdinaryAlarmRepeatPreset(id: UUID, weekdays: [Int]) {
        do {
            if let alarm = try settingsViewModel.setOrdinaryAlarmRepeatWeekdays(id: id, weekdays: weekdays),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id)
                }
            }
        } catch {
            toastCenter.showToast("重复设置保存失败")
        }
    }

    private func handleOrdinaryAlarmSnoozeChange(id: UUID, minutes: Int) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmSnoozeMinutes(id: id, minutes: minutes),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("稍后提醒保存失败")
        }
    }

    private func handleOrdinaryAlarmChallengeChange(
        id: UUID,
        challenge: OrdinaryAlarmDismissChallenge
    ) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmDismissChallenge(id: id, challenge: challenge),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("关闭方式保存失败")
        }
    }

    private func handleOrdinaryAlarmSoundChange(id: UUID, selection: AlarmSoundSelection) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmSoundSelection(id: id, selection: selection),
               alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("闹钟铃声保存失败")
        }
    }

    private func handleOrdinaryAlarmLoudVolumeChange(id: UUID, isEnabled: Bool) {
        do {
            if let alarm = try settingsViewModel.setOrdinaryAlarmLoudVolumeEnabled(
                id: id,
                isEnabled: isEnabled
            ), alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("更大音量设置保存失败")
        }
    }

    private func handleOrdinaryAlarmArrivalTimeChange(id: UUID, date: Date) {
        do {
            if let alarm = try settingsViewModel.updateOrdinaryAlarmArrivalTime(id: id, date: date),
               alarm.effectiveIsEnabled,
               alarm.isCommuteAdjustmentEnabled {
                scheduleDebouncedOrdinaryArrivalReschedule(id: alarm.id)
            }
        } catch {
            toastCenter.showToast("到达时间保存失败")
        }
    }

    private func handleOrdinaryAlarmWeatherToggle(id: UUID, isEnabled: Bool) {
        guard !isEnabled || subscriptionStore.hasPremiumAccess else {
            presentWeatherPaywall("购买后才能开启天气提前")
            return
        }

        do {
            _ = try settingsViewModel.setOrdinaryAlarmWeatherAdjustment(id: id, isEnabled: isEnabled)
            Task {
                await rescheduleOrdinaryAlarm(id: id)
            }
        } catch {
            toastCenter.showToast("天气提前开关保存失败")
        }
    }

    private func handleOrdinaryAlarmCommuteToggle(id: UUID, isEnabled: Bool) {
        guard !isEnabled || hasPathAccessOrPresentPaywall("购买路径订阅后才能开启路径提前") else {
            return
        }

        guard !isEnabled || settingsViewModel.ordinaryAlarmRoute(id: id) != nil else {
            pendingCommuteEnableAlarmID = id
            if freshEditorTarget != nil {
                openFreshRouteEditor(role: .start, target: .ordinaryAlarm(id))
            } else {
                handleRouteLocationSelection(.start, target: .ordinaryAlarm(id))
            }
            return
        }

        do {
            _ = try settingsViewModel.setOrdinaryAlarmCommuteAdjustment(id: id, isEnabled: isEnabled)
            Task {
                if isEnabled {
                    await refreshCommutePreviewAndApplyArrivalDecision(for: id)
                } else {
                    await rescheduleOrdinaryAlarm(id: id)
                }
            }
        } catch {
            toastCenter.showToast("路径提前开关保存失败")
        }
    }

    private func rescheduleOrdinaryAlarm(
        id: UUID,
        showToast: Bool = true,
        shouldNotifyAdjustment: Bool = false,
        reloadScheduleStatuses: Bool = true
    ) async {
        guard let alarm = settingsViewModel.ordinaryAlarm(id: id) else {
            return
        }

        guard alarm.effectiveIsEnabled else {
            AlarmManager().cancelAlarmFamily(
                primaryID: alarm.alarmID,
                secondaryID: alarm.loudAlarmID
            )
            WeatherAlarmStatusStore().removeOrdinaryAlarmStatus(for: alarm.id)
            if reloadScheduleStatuses {
                settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
            }
            toastCenter.showToast("\(alarm.timeText) 已停用")
            return
        }

        schedulingOrdinaryAlarmIDs.insert(id)
        defer {
            schedulingOrdinaryAlarmIDs.remove(id)
        }

        do {
            let alarmManager = AlarmManager()
            try await alarmManager.requestAuthorization()
            try await alarmManager.scheduleOrdinaryAlarm(
                alarm,
                weatherSummary: settingsViewModel.latestMorningSummary,
                notifiesAdjustmentChanges: shouldNotifyAdjustment
            )
            if reloadScheduleStatuses {
                settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
            }
            if showToast {
                toastCenter.showToast("\(alarm.timeText) 闹钟已更新")
            }
        } catch {
            toastCenter.showToast("闹钟更新失败，请检查闹钟权限")
        }
    }

    private func scheduleDebouncedOrdinaryAlarmReschedule(id: UUID) {
        ordinaryTimeRescheduleTasks[id]?.cancel()
        ordinaryTimeRescheduleTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else {
                return
            }

            if settingsViewModel.ordinaryAlarm(id: id)?.isCommuteAdjustmentEnabled == true {
                await refreshCommutePreviewAndApplyArrivalDecision(for: id)
            } else {
                await rescheduleOrdinaryAlarm(id: id, showToast: false)
            }
            ordinaryTimeRescheduleTasks[id] = nil
        }
    }

    private func finalizeOrdinaryAlarmEdit(id: UUID) async {
        ordinaryTimeRescheduleTasks[id]?.cancel()
        ordinaryTimeRescheduleTasks[id] = nil
        ordinaryArrivalRescheduleTasks[id]?.cancel()
        ordinaryArrivalRescheduleTasks[id] = nil

        if settingsViewModel.ordinaryAlarm(id: id)?.isCommuteAdjustmentEnabled == true {
            await refreshCommutePreviewAndApplyArrivalDecision(for: id)
        }

        await rescheduleOrdinaryAlarm(
            id: id,
            showToast: false,
            shouldNotifyAdjustment: true
        )
    }

    private func scheduleDebouncedOrdinaryArrivalReschedule(id: UUID) {
        ordinaryArrivalRescheduleTasks[id]?.cancel()
        ordinaryArrivalRescheduleTasks[id] = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else {
                return
            }

            await refreshCommutePreviewAndApplyArrivalDecision(for: id)
            ordinaryArrivalRescheduleTasks[id] = nil
        }
    }

    private func refreshCommutePreviewAndApplyArrivalDecision(for id: UUID) async {
        guard subscriptionStore.hasGaodeEnhance else {
            settingsViewModel.clearOrdinaryAlarmCommutePreview(id: id)
            return
        }

        await settingsViewModel.refreshOrdinaryAlarmCommutePreview(id: id)
        await applyArrivalTimingDecision(for: id)
    }

    private func applyArrivalTimingDecision(for id: UUID) async {
        guard settingsViewModel.ordinaryAlarm(id: id) != nil,
              let preview = settingsViewModel.ordinaryAlarmCommutePreviews[id],
              preview.arrivalAdvanceMinutes > 0 else {
            _ = try? settingsViewModel.updateOrdinaryAlarmCommuteModeSuggestion(id: id, mode: nil)
            await rescheduleOrdinaryAlarm(id: id, showToast: false)
            return
        }

        let now = Date()
        let minimumUsableAlarmDate = now.addingTimeInterval(60)
        guard let recommendedDepartureDate = preview.recommendedDepartureDate else {
            await rescheduleOrdinaryAlarm(id: id, showToast: false)
            return
        }

        if recommendedDepartureDate > minimumUsableAlarmDate {
            _ = try? settingsViewModel.updateOrdinaryAlarmCommuteModeSuggestion(id: id, mode: nil)
            await rescheduleOrdinaryAlarm(id: id, showToast: false)
            let baseTime = settingsViewModel.ordinaryAlarm(id: id)?.timeText ?? ""
            toastCenter.showToast(
                "预计提前 \(preview.arrivalAdvanceMinutes) 分钟响铃；基础时间仍为 \(baseTime)。"
            )
            return
        }

        let currentRouteMode = settingsViewModel.ordinaryAlarmRoute(id: id)?.effectiveMode
        let evaluations = await settingsViewModel.commuteModeEvaluations(for: id)
        let viableAlternative = evaluations.first { evaluation in
            evaluation.mode != currentRouteMode
                && evaluation.latestDepartureDate > minimumUsableAlarmDate
        }

        if let viableAlternative {
            do {
                try settingsViewModel.updateOrdinaryAlarmCommuteRouteMode(id: id, mode: viableAlternative.mode)
                try settingsViewModel.updateOrdinaryAlarmCommuteModeSuggestion(
                    id: id,
                    mode: viableAlternative.mode
                )
                await settingsViewModel.refreshOrdinaryAlarmCommutePreview(id: id)
                await rescheduleOrdinaryAlarm(id: id, showToast: false)
                toastCenter.showToast(
                    "建议改\(viableAlternative.mode.displayName)：预计 \(timeText(viableAlternative.latestDepartureDate)) 响，基础时间不变。"
                )
            } catch {
                await rescheduleOrdinaryAlarm(id: id, showToast: false)
            }
            return
        }

        if let fastest = evaluations.first {
            _ = try? settingsViewModel.updateOrdinaryAlarmCommuteModeSuggestion(id: id, mode: fastest.mode)
            await rescheduleOrdinaryAlarm(id: id, showToast: false)
            let destination = fastest.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationText = destination?.isEmpty == false ? destination! : "目的地"
            toastCenter.showToast(
                "别等闹钟了：想 \(timeText(fastest.arrivalDate)) 到 \(destinationText)，现在就出发。最快\(fastest.mode.displayName)约 \(fastest.durationMinutes) 分钟。"
            )
        } else {
            await rescheduleOrdinaryAlarm(id: id, showToast: false)
            toastCenter.showToast("路线暂时算不准，先别等闹钟，建议现在出发。")
        }
    }

    private func timeText(_ date: Date) -> String {
        DateFormatter.weatherAlarmHour.string(from: date)
    }

    private func scheduleAutoSavedOrdinaryAlarmNotification(for id: UUID) async {
        guard let alarm = settingsViewModel.ordinaryAlarm(id: id) else {
            return
        }

        do {
            try await LocalWakeNotificationScheduler().scheduleAutoSavedOrdinaryAlarmNotification(
                alarmID: alarm.id,
                title: alarm.effectiveTitle,
                timeText: alarm.timeText
            )
        } catch {
            toastCenter.showToast("\(alarm.timeText) 闹钟已自动保存")
        }
    }

    private func rescheduleEnabledOrdinaryAlarmsForMigration() async {
        guard !didMigrateEnabledOrdinaryAlarms else {
            return
        }

        didMigrateEnabledOrdinaryAlarms = true
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.ordinaryAlarmMigrationVersionKey)
            < Self.ordinaryAlarmMigrationVersion else {
            return
        }

        let enabledAlarmIDs = settingsViewModel.ordinaryAlarms
            .filter(\.effectiveIsEnabled)
            .map(\.id)

        guard !enabledAlarmIDs.isEmpty else {
            defaults.set(
                Self.ordinaryAlarmMigrationVersion,
                forKey: Self.ordinaryAlarmMigrationVersionKey
            )
            return
        }

        for id in enabledAlarmIDs {
            await rescheduleOrdinaryAlarm(
                id: id,
                showToast: false,
                reloadScheduleStatuses: false
            )
        }
        settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
        defaults.set(
            Self.ordinaryAlarmMigrationVersion,
            forKey: Self.ordinaryAlarmMigrationVersionKey
        )
    }

    private func deleteOrdinaryAlarm(id: UUID) {
        do {
            let originalIndex = settingsViewModel.ordinaryAlarms.firstIndex(where: { $0.id == id }) ?? 0
            ordinaryTimeRescheduleTasks[id]?.cancel()
            ordinaryTimeRescheduleTasks[id] = nil
            ordinaryArrivalRescheduleTasks[id]?.cancel()
            ordinaryArrivalRescheduleTasks[id] = nil
            let removed = try settingsViewModel.removeOrdinaryAlarm(id: id)
            if let removed {
                AlarmManager().cancelAlarmFamily(
                    primaryID: removed.alarmID,
                    secondaryID: removed.loudAlarmID
                )
                WeatherAlarmStatusStore().removeOrdinaryAlarmStatus(for: removed.id)
                settingsViewModel.reloadOrdinaryAlarmScheduleStatuses()
                let undo = DeletedAlarmUndo(alarm: removed, originalIndex: originalIndex)
                toastCenter.clear()
                deletedAlarmUndoDismissTask?.cancel()
                deletedAlarmUndo = undo
                deletedAlarmUndoMessage = "已删除 \(removed.timeText) \(removed.effectiveTitle)"
                deletedAlarmUndoDismissTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, deletedAlarmUndo?.id == undo.id else {
                        return
                    }
                    deletedAlarmUndo = nil
                    deletedAlarmUndoMessage = nil
                }
            }
        } catch {
            toastCenter.showToast("删除闹钟失败")
        }
    }

    private func undoDeletedAlarm() {
        guard let undo = deletedAlarmUndo else {
            return
        }

        deletedAlarmUndoDismissTask?.cancel()
        deletedAlarmUndo = nil
        deletedAlarmUndoMessage = nil
        do {
            try settingsViewModel.restoreOrdinaryAlarm(undo.alarm, at: undo.originalIndex)
            toastCenter.showToast("已恢复 \(undo.alarm.timeText) \(undo.alarm.effectiveTitle)", duration: .seconds(3))
            if undo.alarm.effectiveIsEnabled {
                Task {
                    await rescheduleOrdinaryAlarm(id: undo.alarm.id, showToast: false)
                }
            }
        } catch {
            toastCenter.showToast("恢复闹钟失败")
        }
    }

    private func testWakeAlarm() async {
        do {
            try await LocalWakeNotificationScheduler().scheduleTestNotification()
            toastCenter.showToast("5秒后试响通知")
        } catch {
            toastCenter.showToast("试响失败，请开启通知权限")
        }
    }

    private func updateSmartAdjustment(_ isEnabled: Bool) async {
        guard isEnabled else {
            do {
                try settingsViewModel.setSmartAdjustmentEnabled(false)
                await rescheduleWakeAlarmAfterTimeChange()
            } catch {
                toastCenter.showToast("设置保存失败")
            }
            return
        }

        guard subscriptionStore.hasPremiumAccess else {
            presentWeatherPaywall("购买后才能开启智能天气调整")
            return
        }

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        do {
            try await AlarmManager().requestAuthorization()
            try settingsViewModel.setSmartAdjustmentEnabled(true)
            await rescheduleWakeAlarmAfterTimeChange()
            toastCenter.showToast("智能天气调整已开启，闹钟已重新计算")
        } catch {
            do {
                try await LocalWakeNotificationScheduler().rescheduleFallbackWakeNotification()
                toastCenter.showToast("系统闹钟未开启，已先用通知提醒兜底")
            } catch {
                toastCenter.showToast("闹钟权限未开启，无法自动调整")
            }
        }
    }

    private func handleCommuteAdjustmentToggle(_ isEnabled: Bool) {
        guard isEnabled else {
            do {
                try settingsViewModel.setCommuteAdjustmentEnabled(false)
                Task {
                    await rescheduleWakeAlarmAfterTimeChange()
                }
            } catch {
                toastCenter.showToast("设置保存失败")
            }
            return
        }

        guard subscriptionStore.hasGaodeEnhance else {
            presentPathPaywall("购买路径订阅后才能开启地图通勤调整")
            return
        }

        guard settingsViewModel.settings != nil else {
            toastCenter.showToast("请先设置基础起床时间")
            return
        }

        guard settingsViewModel.settings?.commuteRoute != nil else {
            pendingWakeCommuteEnable = true
            if freshEditorTarget != nil {
                openFreshRouteEditor(role: .start, target: .wakeUp)
            } else {
                handleRouteLocationSelection(.start, target: .wakeUp)
            }
            return
        }

        do {
            try settingsViewModel.setCommuteAdjustmentEnabled(true)
            Task {
                await rescheduleWakeAlarmAfterTimeChange()
                toastCenter.showToast("地图通勤调整已开启，闹钟已重新计算")
            }
        } catch {
            toastCenter.showToast("设置保存失败")
        }
    }

    private func routeDisplayText(currentValue: String, fallback: String?, placeholder: String) -> String {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        if let fallback,
           !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }

        return placeholder
    }
}

enum ActiveHomeSheet: Identifiable {
    case paywall(SubscriptionPaywallFocus)
    case invite
    case crowdfunding

    var id: String {
        switch self {
        case .paywall(let focus):
            return "paywall-\(focus.id)"
        case .invite:
            return "invite"
        case .crowdfunding:
            return "crowdfunding"
        }
    }
}

enum RouteLocationRole: String, Identifiable, Hashable {
    case start
    case end

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .start:
            return "选择出发地"
        case .end:
            return "选择目的地"
        }
    }

    var fieldTitle: String {
        switch self {
        case .start:
            return "出发地"
        case .end:
            return "目的地"
        }
    }

    var placeholder: String {
        switch self {
        case .start:
            return "输入出发地，例如：北京市朝阳区望京 SOHO"
        case .end:
            return "输入目的地，例如：北京市海淀区中关村"
        }
    }
}

enum ActiveRouteTarget: Hashable {
    case wakeUp
    case ordinaryAlarm(UUID)
}

enum SmartWakeRouteEntryDestination: Equatable {
    case subscription
    case routeEditor

    init(hasRouteAccess: Bool) {
        self = hasRouteAccess ? .routeEditor : .subscription
    }
}

struct ActiveRouteSelection: Identifiable, Hashable {
    let role: RouteLocationRole
    let target: ActiveRouteTarget

    var id: String {
        switch target {
        case .wakeUp:
            return "wake-up-\(role.rawValue)"
        case .ordinaryAlarm(let alarmID):
            return "\(alarmID.uuidString)-\(role.rawValue)"
        }
    }
}

private struct DeletedAlarmUndo: Identifiable {
    let id = UUID()
    let alarm: OrdinaryAlarmSettings
    let originalIndex: Int
}

#Preview {
    if #available(iOS 26.0, *) {
        ContentView(subscriptionStore: StoreKitSubscriptionStore())
            .environmentObject(ToastMessageCenter())
    }
}

private struct PremiumToggleRow: View {
    let title: String
    let subtitle: String
    let isUnlocked: Bool
    var onLockedTap: () -> Void = {}
    @Binding var isOn: Bool

    var body: some View {
        Group {
            if isUnlocked {
                Toggle(isOn: $isOn) {
                    content
                }
                .toggleStyle(.switch)
            } else {
                Button {
                    onLockedTap()
                } label: {
                    HStack(spacing: 10) {
                        content

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(isUnlocked ? "已解锁" : "未解锁")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isUnlocked ? .green : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((isUnlocked ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SystemAlarmVolumeInfoPanel: View {
    @AppStorage("smartwake.low_volume_warning_disabled") private var isLowVolumeWarningDisabled = false
    @State private var displayedVolume: Float?
    @State private var setMaximumRequestID: UUID?
    @State private var isLowVolumeAlertPresented = false
    @State private var didOfferLowVolumeFix = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.44))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text("闹钟音量")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.11, blue: 0.18))

                    Text(volumeSummary)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)
                }

                SystemVolumeSliderView(
                    volume: $displayedVolume,
                    setMaximumRequestID: setMaximumRequestID
                )
                .frame(height: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
        }
        .onChange(of: displayedVolume) { _, newVolume in
            guard !isLowVolumeWarningDisabled,
                  !didOfferLowVolumeFix,
                  let newVolume,
                  newVolume < 0.5 else {
                return
            }

            didOfferLowVolumeFix = true
            isLowVolumeAlertPresented = true
        }
        .alert("当前音量低于 50%", isPresented: $isLowVolumeAlertPresented) {
            Button("没事", role: .cancel) {}
            Button("永不提醒") {
                isLowVolumeWarningDisabled = true
            }
            Button("一键调到最大") {
                setMaximumRequestID = UUID()
            }
        } message: {
            Text("可以一键调大当前音量。系统闹钟最终音量仍由 iPhone 的铃声与提醒音量决定。")
        }
    }

    private var volumeSummary: String {
        guard let displayedVolume else {
            return "同步中…"
        }

        return "\(Int((displayedVolume * 100).rounded()))%"
    }
}

@MainActor
private struct SystemVolumeSliderView: UIViewRepresentable {
    @Binding var volume: Float?
    let setMaximumRequestID: UUID?

    private static let blueGreenTrackImage: UIImage = {
        let size = CGSize(width: 240, height: 5)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2).addClip()

            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.08, green: 0.66, blue: 0.96, alpha: 1).cgColor,
                    UIColor(red: 0.08, green: 0.85, blue: 0.61, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) else {
                return
            }

            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end: CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
        }
        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2),
            resizingMode: .stretch
        )
    }()

    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        DispatchQueue.main.async {
            context.coordinator.captureSlider(in: volumeView)
        }
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        context.coordinator.captureSlider(in: uiView)
        context.coordinator.setMaximumIfRequested(setMaximumRequestID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(volume: $volume)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var volume: Binding<Float?>
        private weak var slider: UISlider?
        private var handledMaximumRequestID: UUID?
        private var initialReadScheduled = false

        init(volume: Binding<Float?>) {
            self.volume = volume
        }

        func captureSlider(in view: UIView) {
            guard let foundSlider = findSlider(in: view) else {
                return
            }

            if slider !== foundSlider {
                slider = foundSlider
                foundSlider.addTarget(self, action: #selector(volumeDidChange), for: .valueChanged)
            }
            foundSlider.setMinimumTrackImage(
                SystemVolumeSliderView.blueGreenTrackImage,
                for: .normal
            )
            foundSlider.maximumTrackTintColor = UIColor.systemGray5.withAlphaComponent(0.62)
            foundSlider.thumbTintColor = .white
            scheduleInitialReadIfNeeded()
        }

        @objc
        private func volumeDidChange() {
            volume.wrappedValue = slider?.value
        }

        private func scheduleInitialReadIfNeeded() {
            guard !initialReadScheduled else {
                return
            }

            initialReadScheduled = true
            // MPVolumeView briefly reports 0 while its private slider is being
            // hydrated. Wait for that initialization before publishing a value;
            // otherwise the UI and low-volume warning can disagree with the slider.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.publishStableInitialValue()
            }
        }

        private func publishStableInitialValue() {
            guard let slider else {
                initialReadScheduled = false
                return
            }

            let candidate = slider.value
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak slider] in
                guard let self, let slider else {
                    return
                }

                let confirmedValue = slider.value
                guard abs(confirmedValue - candidate) <= 0.01 else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.publishStableInitialValue()
                    }
                    return
                }

                if self.volume.wrappedValue != confirmedValue {
                    self.volume.wrappedValue = confirmedValue
                }
            }
        }

        func setMaximumIfRequested(_ requestID: UUID?) {
            guard let requestID,
                  requestID != handledMaximumRequestID,
                  let slider else {
                return
            }

            handledMaximumRequestID = requestID
            slider.setValue(1, animated: true)
            slider.sendActions(for: .valueChanged)
        }

        private func findSlider(in view: UIView) -> UISlider? {
            if let slider = view as? UISlider {
                return slider
            }

            return view.subviews.lazy.compactMap(findSlider).first
        }
    }
}

private struct WakeAlarmControlPanel: View {
    let title: String
    let wakeUpTimeText: String
    let repeatSummaryText: String
    let selectedRepeatWeekdays: Set<Int>
    let themeIndex: Int
    let iconName: String
    let dismissChallenge: OrdinaryAlarmDismissChallenge
    let soundChoice: AlarmSoundChoice
    let isLoudVolumeEnabled: Bool
    let weatherPreview: HourlyWeatherSummary?
    let commutePreview: OrdinaryAlarmCommutePreview?
    let arrivalTimeText: String
    let route: CommuteRoute?
    let selectedCommuteMode: CommuteMode
    let commuteStartText: String
    let commuteEndText: String
    let commuteRouteText: String
    let commuteSyncMessage: String?
    let advanceDisplay: AlarmAdvanceDisplay?
    @Binding var selectedWakeUpTime: Date
    @Binding var selectedArrivalTime: Date
    @Binding var isEnabled: Bool
    @Binding var isSmartAdjustmentEnabled: Bool
    @Binding var isCommuteAdjustmentEnabled: Bool
    let isSmartAdjustmentUnlocked: Bool
    let isCommuteAdjustmentUnlocked: Bool
    let isSchedulingWakeAlarm: Bool
    let isSchedulingTestAlarm: Bool
    let onLockedWeatherTap: () -> Void
    let onLockedPathTap: () -> Void
    let onTimeChanged: () -> Void
    let onArrivalTimeChanged: (Date) -> Void
    let onTitleChanged: (String) -> Void
    let onRepeatWeekdayToggle: (Int) -> Void
    let onRepeatPresetSelected: ([Int]) -> Void
    let onAppearanceChanged: (Int, String) -> Void
    let onChallengeChanged: (OrdinaryAlarmDismissChallenge) -> Void
    let onSoundChanged: (AlarmSoundChoice) -> Void
    let onLoudVolumeChanged: (Bool) -> Void
    let onCommuteModeChanged: (CommuteMode) -> Void
    let onSelectCommuteStart: () -> Void
    let onSelectCommuteEnd: () -> Void
    let onCollapsed: () -> Void
    let onScheduleWakeAlarm: () -> Void
    let onScheduleTestAlarm: () -> Void
    private let initiallyExpanded: Bool
    @State private var isExpanded = false
    @State private var isTimePickerExpanded = false
    @State private var isAppearanceExpanded = false
    @State private var isArrivalTimePickerExpanded = false
    @State private var isEditorPresented = false
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        wakeUpTimeText: String,
        repeatSummaryText: String,
        selectedRepeatWeekdays: Set<Int>,
        themeIndex: Int,
        iconName: String,
        dismissChallenge: OrdinaryAlarmDismissChallenge,
        soundChoice: AlarmSoundChoice,
        isLoudVolumeEnabled: Bool,
        weatherPreview: HourlyWeatherSummary?,
        commutePreview: OrdinaryAlarmCommutePreview?,
        arrivalTimeText: String,
        route: CommuteRoute?,
        selectedCommuteMode: CommuteMode,
        commuteStartText: String,
        commuteEndText: String,
        commuteRouteText: String,
        commuteSyncMessage: String?,
        selectedWakeUpTime: Binding<Date>,
        selectedArrivalTime: Binding<Date>,
        isEnabled: Binding<Bool> = .constant(true),
        isSmartAdjustmentEnabled: Binding<Bool>,
        isCommuteAdjustmentEnabled: Binding<Bool>,
        isSmartAdjustmentUnlocked: Bool,
        isCommuteAdjustmentUnlocked: Bool,
        isSchedulingWakeAlarm: Bool,
        isSchedulingTestAlarm: Bool,
        onLockedWeatherTap: @escaping () -> Void,
        onLockedPathTap: @escaping () -> Void,
        onTimeChanged: @escaping () -> Void,
        onArrivalTimeChanged: @escaping (Date) -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onRepeatWeekdayToggle: @escaping (Int) -> Void,
        onRepeatPresetSelected: @escaping ([Int]) -> Void,
        onAppearanceChanged: @escaping (Int, String) -> Void,
        onChallengeChanged: @escaping (OrdinaryAlarmDismissChallenge) -> Void,
        onSoundChanged: @escaping (AlarmSoundChoice) -> Void,
        onLoudVolumeChanged: @escaping (Bool) -> Void,
        onCommuteModeChanged: @escaping (CommuteMode) -> Void,
        onSelectCommuteStart: @escaping () -> Void,
        onSelectCommuteEnd: @escaping () -> Void,
        onCollapsed: @escaping () -> Void,
        onScheduleWakeAlarm: @escaping () -> Void,
        onScheduleTestAlarm: @escaping () -> Void,
        advanceDisplay: AlarmAdvanceDisplay? = nil,
        initiallyExpanded: Bool = false
    ) {
        self.title = title
        self.wakeUpTimeText = wakeUpTimeText
        self.repeatSummaryText = repeatSummaryText
        self.selectedRepeatWeekdays = selectedRepeatWeekdays
        self.themeIndex = themeIndex
        self.iconName = iconName
        self.dismissChallenge = dismissChallenge
        self.soundChoice = soundChoice
        self.isLoudVolumeEnabled = isLoudVolumeEnabled
        self.weatherPreview = weatherPreview
        self.commutePreview = commutePreview
        self.arrivalTimeText = arrivalTimeText
        self.route = route
        self.selectedCommuteMode = selectedCommuteMode
        self.commuteStartText = commuteStartText
        self.commuteEndText = commuteEndText
        self.commuteRouteText = commuteRouteText
        self.commuteSyncMessage = commuteSyncMessage
        self.advanceDisplay = advanceDisplay
        self._selectedWakeUpTime = selectedWakeUpTime
        self._selectedArrivalTime = selectedArrivalTime
        self._isEnabled = isEnabled
        self._isSmartAdjustmentEnabled = isSmartAdjustmentEnabled
        self._isCommuteAdjustmentEnabled = isCommuteAdjustmentEnabled
        self.isSmartAdjustmentUnlocked = isSmartAdjustmentUnlocked
        self.isCommuteAdjustmentUnlocked = isCommuteAdjustmentUnlocked
        self.isSchedulingWakeAlarm = isSchedulingWakeAlarm
        self.isSchedulingTestAlarm = isSchedulingTestAlarm
        self.onLockedWeatherTap = onLockedWeatherTap
        self.onLockedPathTap = onLockedPathTap
        self.onTimeChanged = onTimeChanged
        self.onArrivalTimeChanged = onArrivalTimeChanged
        self.onTitleChanged = onTitleChanged
        self.onRepeatWeekdayToggle = onRepeatWeekdayToggle
        self.onRepeatPresetSelected = onRepeatPresetSelected
        self.onAppearanceChanged = onAppearanceChanged
        self.onChallengeChanged = onChallengeChanged
        self.onSoundChanged = onSoundChanged
        self.onLoudVolumeChanged = onLoudVolumeChanged
        self.onCommuteModeChanged = onCommuteModeChanged
        self.onSelectCommuteStart = onSelectCommuteStart
        self.onSelectCommuteEnd = onSelectCommuteEnd
        self.onCollapsed = onCollapsed
        self.onScheduleWakeAlarm = onScheduleWakeAlarm
        self.onScheduleTestAlarm = onScheduleTestAlarm
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
        _isTimePickerExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            AlarmSummaryHeader(
                iconName: iconName,
                iconColor: isEnabled ? AlarmTheme.accentColor(for: themeIndex) : .secondary,
                title: title,
                timeText: wakeUpTimeText,
                subtitle: !isEnabled
                    ? "已停用"
                    : isSchedulingWakeAlarm || isSchedulingTestAlarm
                        ? "正在写入系统闹钟"
                        : repeatSummaryText,
                isWeatherEnabled: isSmartAdjustmentEnabled,
                isCommuteEnabled: isCommuteAdjustmentEnabled,
                weatherPreview: weatherPreview,
                commutePreview: commutePreview,
                advanceDisplay: advanceDisplay,
                isAlarmEnabled: $isEnabled,
                onCardTapped: {
                    if !initiallyExpanded {
                        isEditorPresented = true
                    }
                }
            )

            if isExpanded {
                if isTimePickerExpanded {
                    LargeAlarmTimePicker(
                        title: "响铃时间",
                        selection: $selectedWakeUpTime,
                        onTimeChanged: onTimeChanged
                    )
                }

                TextField(
                    "名称，例如：起床、上班、晨跑",
                    text: Binding(
                        get: { title == "起床闹钟" ? "" : title },
                        set: { onTitleChanged($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                DisclosureButton(
                    title: "更改闹钟版式",
                    systemImage: "paintpalette.fill",
                    isExpanded: isAppearanceExpanded
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isAppearanceExpanded.toggle()
                    }
                }

                if isAppearanceExpanded {
                    AlarmAppearancePicker(
                        selectedThemeIndex: Binding(
                            get: { themeIndex },
                            set: { onAppearanceChanged($0, iconName) }
                        ),
                        selectedIconName: Binding(
                            get: { iconName },
                            set: { onAppearanceChanged(themeIndex, $0) }
                        )
                    )
                }

                AlarmRepeatEditor(
                    selectedWeekdays: selectedRepeatWeekdays,
                    summaryText: repeatSummaryText,
                    onToggleWeekday: onRepeatWeekdayToggle,
                    onPresetSelected: onRepeatPresetSelected
                )

                AlarmMenuPickerRow(
                    title: "关闭方式",
                    systemImage: "lock.open.fill",
                    selection: Binding(
                        get: { dismissChallenge },
                        set: { onChallengeChanged($0) }
                    )
                ) {
                    ForEach(OrdinaryAlarmDismissChallenge.allCases) { challenge in
                        Text(challenge.displayName).tag(challenge)
                    }
                }

                AlarmSoundNavigationRow(
                    selection: soundChoice,
                    isLoudVersionEnabled: isLoudVolumeEnabled,
                    onSelectionChanged: onSoundChanged
                )

                AlarmLoudVolumeToggleRow(
                    isOn: Binding(
                        get: { isLoudVolumeEnabled },
                        set: { onLoudVolumeChanged($0) }
                    )
                )

                VStack(spacing: 4) {
                    PremiumToggleRow(
                        title: "天气提前",
                        subtitle: "明早有雨雪时，自动提前这个系统闹钟。",
                        isUnlocked: isSmartAdjustmentUnlocked,
                        onLockedTap: onLockedWeatherTap,
                        isOn: $isSmartAdjustmentEnabled
                    )

                    Divider()

                    PremiumToggleRow(
                        title: "路径提前",
                        subtitle: "按路况、雨天步行和骑行速度变化，自动调整响铃时间。",
                        isUnlocked: isCommuteAdjustmentUnlocked,
                        onLockedTap: onLockedPathTap,
                        isOn: $isCommuteAdjustmentEnabled
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isCommuteAdjustmentEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isArrivalTimePickerExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Label("到达目的地时间", systemImage: "flag.checkered")
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Text(arrivalTimeText)
                                    .font(.headline.weight(.bold))
                                    .monospacedDigit()

                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .rotationEffect(.degrees(isArrivalTimePickerExpanded ? 180 : 0))
                            }
                            .foregroundStyle(Color(red: 0.46, green: 0.23, blue: 0.07))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.92, blue: 0.76).opacity(0.88),
                                        Color(red: 1.00, green: 0.78, blue: 0.64).opacity(0.64)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)

                        if isArrivalTimePickerExpanded {
                            DatePicker(
                                "到达目的地时间",
                                selection: Binding(
                                    get: { selectedArrivalTime },
                                    set: {
                                        selectedArrivalTime = $0
                                        onArrivalTimeChanged($0)
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                CommuteRouteSettingsPanel(
                    route: route,
                    isUnlocked: isCommuteAdjustmentUnlocked,
                    selectedCommuteMode: selectedCommuteMode,
                    startText: commuteStartText,
                    endText: commuteEndText,
                    routeText: commuteRouteText,
                    syncMessage: commuteSyncMessage,
                    onModeChanged: onCommuteModeChanged,
                    onSelectStart: onSelectCommuteStart,
                    onSelectEnd: onSelectCommuteEnd
                )

                Button {
                    onScheduleWakeAlarm()
                    if initiallyExpanded {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    }
                } label: {
                    HStack {
                        if isSchedulingWakeAlarm {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isSchedulingWakeAlarm ? "正在更新系统闹钟" : "开启/更新系统闹钟")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSchedulingWakeAlarm || !isEnabled)

                Button {
                    onScheduleTestAlarm()
                } label: {
                    HStack {
                        if isSchedulingTestAlarm {
                            ProgressView()
                        } else {
                            Image(systemName: "speaker.wave.3.fill")
                        }
                        Text(isSchedulingTestAlarm ? "正在安排试响" : "1分钟后试响系统闹钟")
                    }
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .disabled(isSchedulingTestAlarm)
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            // 卡片位于 List 的懒加载容器中，不能在卡片内部注册 navigationDestination。
            // 独立编辑页用系统 sheet 承载，既不会被懒加载吞掉，也保留系统下拉退出手势。
            NavigationStack {
                editorDestination
            }
            .presentationDragIndicator(.visible)
        }
        .padding(.vertical, 6)
        .padding(12)
        .background {
            AlarmCardGradient(themeIndex: themeIndex)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .opacity(isEnabled ? 1 : 0.58)
    }

    private var editorDestination: some View {
        ScrollView {
            WakeAlarmControlPanel(
                title: title,
                wakeUpTimeText: wakeUpTimeText,
                repeatSummaryText: repeatSummaryText,
                selectedRepeatWeekdays: selectedRepeatWeekdays,
                themeIndex: themeIndex,
                iconName: iconName,
                dismissChallenge: dismissChallenge,
                soundChoice: soundChoice,
                isLoudVolumeEnabled: isLoudVolumeEnabled,
                weatherPreview: weatherPreview,
                commutePreview: commutePreview,
                arrivalTimeText: arrivalTimeText,
                route: route,
                selectedCommuteMode: selectedCommuteMode,
                commuteStartText: commuteStartText,
                commuteEndText: commuteEndText,
                commuteRouteText: commuteRouteText,
                commuteSyncMessage: commuteSyncMessage,
                selectedWakeUpTime: $selectedWakeUpTime,
                selectedArrivalTime: $selectedArrivalTime,
                isEnabled: $isEnabled,
                isSmartAdjustmentEnabled: $isSmartAdjustmentEnabled,
                isCommuteAdjustmentEnabled: $isCommuteAdjustmentEnabled,
                isSmartAdjustmentUnlocked: isSmartAdjustmentUnlocked,
                isCommuteAdjustmentUnlocked: isCommuteAdjustmentUnlocked,
                isSchedulingWakeAlarm: isSchedulingWakeAlarm,
                isSchedulingTestAlarm: isSchedulingTestAlarm,
                onLockedWeatherTap: onLockedWeatherTap,
                onLockedPathTap: onLockedPathTap,
                onTimeChanged: onTimeChanged,
                onArrivalTimeChanged: onArrivalTimeChanged,
                onTitleChanged: onTitleChanged,
                onRepeatWeekdayToggle: onRepeatWeekdayToggle,
                onRepeatPresetSelected: onRepeatPresetSelected,
                onAppearanceChanged: onAppearanceChanged,
                onChallengeChanged: onChallengeChanged,
                onSoundChanged: onSoundChanged,
                onLoudVolumeChanged: onLoudVolumeChanged,
                onCommuteModeChanged: onCommuteModeChanged,
                onSelectCommuteStart: {
                    dismissEditorThenOpenRoute(onSelectCommuteStart)
                },
                onSelectCommuteEnd: {
                    dismissEditorThenOpenRoute(onSelectCommuteEnd)
                },
                onCollapsed: onCollapsed,
                onScheduleWakeAlarm: onScheduleWakeAlarm,
                onScheduleTestAlarm: onScheduleTestAlarm,
                advanceDisplay: advanceDisplay,
                initiallyExpanded: true
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("编辑起床闹钟")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dismissEditorThenOpenRoute(_ action: @escaping () -> Void) {
        isEditorPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            action()
        }
    }
}

private struct AlarmSummaryHeader: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let timeText: String
    let subtitle: String
    let isWeatherEnabled: Bool
    let isCommuteEnabled: Bool
    let weatherPreview: HourlyWeatherSummary?
    let commutePreview: OrdinaryAlarmCommutePreview?
    let advanceDisplay: AlarmAdvanceDisplay?
    let isAlarmEnabled: Binding<Bool>?
    let onCardTapped: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCardTapped) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(timeText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: iconName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(iconColor)
                            .frame(width: 24, height: 24)
                            .background(iconColor.opacity(0.11), in: Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.primary.opacity(0.82))
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let advanceDisplay {
                        ViewThatFits(in: .horizontal) {
                            advanceStatusLine(advanceDisplay, lineLimit: 1, fixedHorizontally: true)
                            advanceStatusLine(advanceDisplay, lineLimit: 2, fixedHorizontally: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(iconColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if isWeatherEnabled || isCommuteEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            if isWeatherEnabled {
                                if let weatherPreview {
                                    SmartAlarmPreviewLine(
                                        systemImage: WeatherDisplayIcon.systemName(for: weatherPreview.weatherCondition),
                                        title: "天气 \(weatherPreview.weatherCondition) · \(adjustmentSummary(minutes: advanceDisplay?.weatherAdvanceMinutes ?? 0))",
                                        detail: precipitationDetail(for: weatherPreview)
                                    )
                                } else {
                                    SmartAlarmPreviewLine(
                                        systemImage: "cloud.sun.fill",
                                        title: "天气",
                                        detail: "降水量待更新"
                                    )
                                }
                            }

                            if isCommuteEnabled {
                                if let commutePreview {
                                    SmartAlarmPreviewLine(
                                        systemImage: commutePreview.isCongested ? "car.fill" : "map.fill",
                                        title: "路径\(commutePreview.trafficText) · \(adjustmentSummary(minutes: routeAdvanceMinutes(for: commutePreview)))",
                                        detail: commuteModeDurationText(for: commutePreview)
                                    )
                                } else {
                                    SmartAlarmPreviewLine(
                                        systemImage: "map.fill",
                                        title: "路径",
                                        detail: "等待路况更新"
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("打开此闹钟的编辑页面")

            if let isAlarmEnabled {
                Toggle("启用闹钟", isOn: isAlarmEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(iconColor)
                    .fixedSize()
                    .accessibilityLabel("启用闹钟")
            }
        }
        .contentShape(Rectangle())
    }

    private func advanceStatusLine(
        _ advanceDisplay: AlarmAdvanceDisplay,
        lineLimit: Int,
        fixedHorizontally: Bool
    ) -> some View {
        HStack(alignment: lineLimit == 1 ? .center : .firstTextBaseline, spacing: 5) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)

            Text(advanceStatusText(advanceDisplay))
                .font(.caption.weight(.bold))
                .foregroundStyle(iconColor)
                .lineLimit(nil)
                .fixedSize(horizontal: fixedHorizontally, vertical: true)
        }
    }

    private func advanceStatusText(_ display: AlarmAdvanceDisplay) -> String {
        display.advanceMinutes > 0
            ? "总共提前 \(display.advanceMinutes) 分钟"
            : "不用提前"
    }

    private func adjustmentSummary(minutes: Int) -> String {
        minutes > 0 ? "提前 \(minutes) 分钟" : "不用提前"
    }

    private func routeAdvanceMinutes(for preview: OrdinaryAlarmCommutePreview) -> Int {
        max(
            0,
            advanceDisplay?.routeAdvanceMinutes
                ?? (preview.delayMinutes + preview.residualWeatherMinutes)
        )
    }

    private func commuteModeDurationText(for preview: OrdinaryAlarmCommutePreview) -> String {
        let firstLine = preview.detailText
            .components(separatedBy: " · ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine?.isEmpty == false ? firstLine! : "通勤时间等待更新"
    }

    private func precipitationDetail(for weather: HourlyWeatherSummary) -> String {
        let chance = Int(weather.precipitationChancePercent.rounded())
        return "降水概率 \(chance)% · \(SmartWakeWeatherText.precipitationAmount(weather.precipitationAmountMillimeters))"
    }

}

private struct AlarmMenuPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Picker(title, selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct AlarmSoundNavigationRow: View {
    let selection: AlarmSoundChoice
    let isLoudVersionEnabled: Bool
    let onSelectionChanged: (AlarmSoundChoice) -> Void

    var body: some View {
        NavigationLink {
            AlarmSoundSelectionView(
                initialSelection: selection,
                isLoudVersionEnabled: isLoudVersionEnabled,
                onSelectionChanged: onSelectionChanged
            )
        } label: {
            HStack(spacing: 10) {
                Label("铃声", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text(selection.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct AlarmSoundSelectionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var previewPlayer = AlarmSoundPreviewPlayer()
    @State private var selection: AlarmSoundChoice
    let isLoudVersionEnabled: Bool
    let onSelectionChanged: (AlarmSoundChoice) -> Void

    init(
        initialSelection: AlarmSoundChoice,
        isLoudVersionEnabled: Bool,
        onSelectionChanged: @escaping (AlarmSoundChoice) -> Void
    ) {
        _selection = State(initialValue: initialSelection)
        self.isLoudVersionEnabled = isLoudVersionEnabled
        self.onSelectionChanged = onSelectionChanged
    }

    var body: some View {
        List {
            ForEach(AlarmSoundCollection.allCases) { collection in
                Section {
                    ForEach(AlarmSoundChoice.allCases.filter { $0.collection == collection }) { sound in
                        Button {
                            selection = sound
                            onSelectionChanged(sound)
                            UISelectionFeedbackGenerator().selectionChanged()
                            previewPlayer.play(sound, loudVersion: isLoudVersionEnabled)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: collection.symbolName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.06, green: 0.43, blue: 0.40))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sound.displayName)
                                        .foregroundStyle(.primary)
                                    Text(sound.soundDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selection == sound {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color(red: 0.06, green: 0.43, blue: 0.40))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Label(collection.rawValue, systemImage: collection.symbolName)
                }
            }

            Section {} footer: {
                Text("点击任一铃声会立即试听；离开本页或切到后台时自动停止。")
            }
        }
        .navigationTitle("铃声")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            previewPlayer.stop()
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                previewPlayer.stop()
            }
        }
    }
}

@MainActor
private final class AlarmSoundPreviewPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ sound: AlarmSoundChoice, loudVersion: Bool) {
        stop()

        let fileName = sound.bundledFileName(loudVolumeEnabled: loudVersion)
        let url = Bundle.main.url(forResource: fileName, withExtension: nil)
            ?? Bundle.main.url(
                forResource: fileName,
                withExtension: nil,
                subdirectory: sound.bundledSubdirectory
            )
        guard let url,
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        player.numberOfLoops = 0
        player.volume = 1
        player.prepareToPlay()
        player.play()
        self.player = player

        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else {
                return
            }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private struct DisclosureButton: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct LargeAlarmTimePicker: View {
    let title: String
    @Binding var selection: Date
    let onTimeChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: $selection,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .onChange(of: selection) {
                onTimeChanged()
            }
        }
        .padding(12)
        .background(.white.opacity(0.50), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

@MainActor
private final class AlarmChallengeTonePlayer: ObservableObject {
    private var players: [AVAudioPlayer] = []
    private var currentSoundSelection: AlarmSoundSelection?
    private var currentLoudVolumeEnabled = false
    private var recoveryTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        recoveryTask?.cancel()
    }

    func start(soundSelection: AlarmSoundSelection, loudVolumeEnabled: Bool) {
        stop()
        currentSoundSelection = soundSelection
        currentLoudVolumeEnabled = loudVolumeEnabled
        configureAudioSession()

        let url: URL?
        switch soundSelection {
        case .builtIn(let soundChoice):
            let fileName = soundChoice.bundledFileName(loudVolumeEnabled: true)
            url = Bundle.main.url(forResource: fileName, withExtension: nil)
                ?? Bundle.main.url(
                    forResource: fileName,
                    withExtension: nil,
                    subdirectory: soundChoice.bundledSubdirectory
                )
        case .custom(let id):
            url = CustomAlarmSoundStore.audioURL(for: id)
        }

        guard let url else {
            return
        }

        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            return
        }

        player.numberOfLoops = -1
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        players = [player]
        scheduleRecoveryChecks()
    }

    func ensurePlaying(soundSelection: AlarmSoundSelection, loudVolumeEnabled: Bool) {
        if currentSoundSelection != soundSelection
            || currentLoudVolumeEnabled != loudVolumeEnabled
            || players.isEmpty {
            start(soundSelection: soundSelection, loudVolumeEnabled: loudVolumeEnabled)
            return
        }

        configureAudioSession()
        players.filter { !$0.isPlaying }.forEach { $0.play() }
        scheduleRecoveryChecks()
    }

    func stop() {
        recoveryTask?.cancel()
        recoveryTask = nil
        currentSoundSelection = nil
        currentLoudVolumeEnabled = false
        players.forEach { $0.stop() }
        players.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func scheduleRecoveryChecks() {
        recoveryTask?.cancel()
        recoveryTask = Task { @MainActor [weak self] in
            for delay in [250, 800, 1_800] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled,
                      let self,
                      self.currentSoundSelection != nil else {
                    return
                }

                self.configureAudioSession()
                self.players.filter { !$0.isPlaying }.forEach { $0.play() }
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType),
              type == .ended,
              currentSoundSelection != nil else {
            return
        }

        configureAudioSession()
        players.filter { !$0.isPlaying }.forEach { $0.play() }
        scheduleRecoveryChecks()
    }
}

private struct AlarmDismissChallengeView: View {
    let challenge: PendingAlarmDismissChallenge
    let tonePlayer: AlarmChallengeTonePlayer
    let onComplete: () -> Void

    @State private var shakeCount = 0
    @State private var lastShakeDate = Date.distantPast
    @State private var motionManager = CMMotionManager()
    @State private var pedometer = CMPedometer()
    @State private var stepCount = 0
    @State private var mathA = Int.random(in: 7...19)
    @State private var mathB = Int.random(in: 6...17)
    @State private var answerText = ""
    @State private var errorText: String?

    private var targetShakeCount: Int { 8 }
    private var targetStepCount: Int { 12 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: challengeIconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(AlarmTheme.accentColor(for: challenge.themeIndex))
                    .frame(width: 86, height: 86)
                    .background(AlarmTheme.accentColor(for: challenge.themeIndex).opacity(0.14), in: Circle())

                VStack(spacing: 8) {
                    Text(challenge.alarmTitle)
                        .font(.title2.weight(.bold))

                    Text(challenge.challenge.displayName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                challengeContent

                if let errorText {
                    Text(errorText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(24)
            .background {
                AlarmCardGradient(themeIndex: challenge.themeIndex)
                    .opacity(0.28)
                    .ignoresSafeArea()
            }
            .navigationTitle("关闭闹钟")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            startChallengeIfNeeded()
        }
        .onDisappear {
            motionManager.stopAccelerometerUpdates()
            pedometer.stopUpdates()
        }
    }

    @ViewBuilder
    private var challengeContent: some View {
        switch challenge.challenge {
        case .none:
            Button("关闭闹钟", action: completeChallenge)
                .buttonStyle(.borderedProminent)

        case .shake:
            VStack(spacing: 14) {
                Text("\(shakeCount)/\(targetShakeCount)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("拿起手机连续摇一摇")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(shakeCount), total: Double(targetShakeCount))

                Button("完成关闭") {
                    if shakeCount >= targetShakeCount {
                        completeChallenge()
                    } else {
                        errorText = "还需要再摇 \(targetShakeCount - shakeCount) 次"
                    }
                }
                .buttonStyle(.borderedProminent)
            }

        case .math:
            VStack(spacing: 14) {
                Text("\(mathA) + \(mathB) = ?")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                TextField("输入答案", text: $answerText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.weight(.semibold))

                Button("提交并关闭") {
                    if Int(answerText.trimmingCharacters(in: .whitespacesAndNewlines)) == mathA + mathB {
                        completeChallenge()
                    } else {
                        errorText = "答案不对，再算一次"
                        answerText = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }

        case .steps:
            VStack(spacing: 14) {
                Text("\(stepCount)/\(targetStepCount)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("起身走几步后才能关闭")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(stepCount), total: Double(targetStepCount))

                Button("完成关闭") {
                    if stepCount >= targetStepCount || !CMPedometer.isStepCountingAvailable() {
                        completeChallenge()
                    } else {
                        errorText = "还需要再走 \(targetStepCount - stepCount) 步"
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func completeChallenge() {
        tonePlayer.stop()
        onComplete()
    }

    private var challengeIconName: String {
        switch challenge.challenge {
        case .none:
            return "stop.circle.fill"
        case .shake:
            return "iphone.radiowaves.left.and.right"
        case .math:
            return "function"
        case .steps:
            return "figure.walk.circle.fill"
        }
    }

    private func startChallengeIfNeeded() {
        errorText = nil
        switch challenge.challenge {
        case .shake:
            startShakeDetection()
        case .steps:
            startStepCounting()
        case .none, .math:
            break
        }
    }

    private func startShakeDetection() {
        guard motionManager.isAccelerometerAvailable else {
            errorText = "当前设备无法读取摇动动作"
            return
        }

        motionManager.accelerometerUpdateInterval = 0.12
        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let acceleration = data?.acceleration else {
                return
            }

            let magnitude = sqrt(
                acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
            )
            let now = Date()
            if magnitude > 2.15,
               now.timeIntervalSince(lastShakeDate) > 0.32 {
                lastShakeDate = now
                shakeCount = min(targetShakeCount, shakeCount + 1)
            }
        }
    }

    private func startStepCounting() {
        guard CMPedometer.isStepCountingAvailable() else {
            errorText = "当前设备不支持计步，可直接完成关闭"
            return
        }

        pedometer.startUpdates(from: Date()) { data, _ in
            guard let data else {
                return
            }

            DispatchQueue.main.async {
                stepCount = min(targetStepCount, data.numberOfSteps.intValue)
            }
        }
    }
}

enum AlarmTheme {
    private static let palettes: [[Color]] = [
        [
            Color(red: 0.73, green: 0.90, blue: 1.00),
            Color(red: 0.86, green: 0.99, blue: 0.94)
        ],
        [
            Color(red: 0.76, green: 0.98, blue: 0.86),
            Color(red: 0.91, green: 1.00, blue: 0.75)
        ],
        [
            Color(red: 0.67, green: 0.95, blue: 0.98),
            Color(red: 0.78, green: 1.00, blue: 0.89)
        ],
        [
            Color(red: 0.78, green: 0.86, blue: 1.00),
            Color(red: 0.88, green: 0.98, blue: 1.00)
        ],
        [
            Color(red: 0.93, green: 1.00, blue: 0.72),
            Color(red: 0.79, green: 0.98, blue: 0.88)
        ],
        [
            Color(red: 0.61, green: 0.88, blue: 1.00),
            Color(red: 0.75, green: 0.98, blue: 0.98)
        ],
        [
            Color(red: 0.65, green: 1.00, blue: 0.78),
            Color(red: 0.82, green: 0.95, blue: 1.00)
        ],
        [
            Color(red: 0.80, green: 0.96, blue: 1.00),
            Color(red: 0.70, green: 0.98, blue: 0.83)
        ],
        [
            Color(red: 0.84, green: 0.91, blue: 1.00),
            Color(red: 0.83, green: 1.00, blue: 0.95)
        ],
        [
            Color(red: 0.86, green: 1.00, blue: 0.82),
            Color(red: 0.71, green: 0.94, blue: 1.00)
        ],
        [
            Color(red: 1.00, green: 0.78, blue: 0.68),
            Color(red: 1.00, green: 0.93, blue: 0.78)
        ],
        [
            Color(red: 1.00, green: 0.86, blue: 0.70),
            Color(red: 1.00, green: 0.96, blue: 0.84)
        ],
        [
            Color(red: 1.00, green: 0.72, blue: 0.82),
            Color(red: 1.00, green: 0.90, blue: 0.76)
        ],
        [
            Color(red: 1.00, green: 0.91, blue: 0.60),
            Color(red: 0.94, green: 1.00, blue: 0.78)
        ],
        [
            Color(red: 0.98, green: 0.74, blue: 0.62),
            Color(red: 0.91, green: 0.82, blue: 1.00)
        ],
        [
            Color(red: 1.00, green: 0.82, blue: 0.58),
            Color(red: 0.82, green: 0.98, blue: 0.86)
        ]
    ]

    private static let accents: [Color] = [
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

    static let iconNames: [String] = [
        "alarm.fill",
        "sunrise.fill",
        "briefcase.fill",
        "figure.run",
        "cup.and.saucer.fill",
        "pills.fill",
        "book.fill",
        "fork.knife",
        "moon.stars.fill",
        "heart.fill"
    ]

    static func colors(for index: Int) -> [Color] {
        palettes[index % palettes.count]
    }

    static func accentColor(for index: Int) -> Color {
        accents[index % accents.count]
    }

    /// 色卡只改变展示顺序，不改变已保存的 themeIndex 与实际颜色映射。
    /// 冷调蓝、青、紫在前，绿色过渡居中，粉、红、橙、黄等暖色在后。
    static let rainbowOrderedThemeIndices = [
        0, 5, 8, 3, 14, 2, 7, 6,
        1, 9, 4, 12, 10, 11, 15, 13
    ]

    static var allThemeIndices: [Int] {
        rainbowOrderedThemeIndices
    }
}

private struct AlarmCardGradient: View {
    let themeIndex: Int

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
        .overlay {
            LinearGradient(
                colors: [
                    AlarmTheme.colors(for: themeIndex)[0].opacity(0.18),
                    AlarmTheme.colors(for: themeIndex)[1].opacity(0.06),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(AlarmTheme.accentColor(for: themeIndex))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct SmartAlarmPreviewLine: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.44))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.primary.opacity(0.78))

                Text(detail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@available(iOS 26.0, *)
private struct PurchaseOfferCountdownBanner: View {
    @ObservedObject var offerStore: PurchaseOfferStore
    let onTap: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button(action: onTap) {
                HStack(spacing: 13) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.86, green: 0.62, blue: 1.00),
                                        Color(red: 0.47, green: 0.36, blue: 1.00)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)

                        VStack(spacing: -1) {
                            Text("Sale")
                                .font(.caption2.weight(.black))
                            Text("50%")
                                .font(.caption.weight(.black))
                        }
                        .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("仅限现在")
                                .font(.caption.weight(.black))
                                .foregroundStyle(Color(red: 0.64, green: 0.88, blue: 0.82))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.10), in: Capsule())

                            Text("只含天气")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.78))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("298元")
                                .font(.system(size: 25, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 1.00, green: 0.58, blue: 0.70),
                                            Color(red: 0.78, green: 0.52, blue: 1.00)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text("598元")
                                .font(.subheadline.weight(.bold))
                                .strikethrough(true, color: .white.opacity(0.72))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(spacing: 3) {
                        Text(Self.formattedTime(offerStore.remainingSeconds))
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)

                        Text("后结束")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color(red: 1.00, green: 0.18, blue: 0.32), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.04, green: 0.07, blue: 0.28),
                            Color(red: 0.08, green: 0.10, blue: 0.42),
                            Color(red: 0.10, green: 0.08, blue: 0.31)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(red: 0.42, green: 0.38, blue: 1.00).opacity(0.55), lineWidth: 1)
                }
                .shadow(color: Color(red: 0.04, green: 0.05, blue: 0.22).opacity(0.24), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
        }
    }

    private static func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct AlarmLoudVolumeToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("更大音量")
                        .font(.subheadline.weight(.semibold))

                    Text("增强响铃存在感，比普通系统闹钟更醒耳。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

private struct AlarmAppearancePicker: View {
    @Binding var selectedThemeIndex: Int
    @Binding var selectedIconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("外观", systemImage: "paintpalette.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AlarmTheme.allThemeIndices, id: \.self) { index in
                        Button {
                            selectedThemeIndex = index
                        } label: {
                            ZStack {
                                AlarmCardGradient(themeIndex: index)
                                    .frame(width: 42, height: 42)
                                    .clipShape(Circle())

                                if selectedThemeIndex == index {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(AlarmTheme.accentColor(for: index), in: Circle())
                                }
                            }
                            .overlay {
                                Circle()
                                    .stroke(
                                        selectedThemeIndex == index ? AlarmTheme.accentColor(for: index) : .white.opacity(0.72),
                                        lineWidth: selectedThemeIndex == index ? 3 : 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("颜色 \(index + 1)")
                    }
                }
                .padding(.vertical, 2)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AlarmTheme.iconNames, id: \.self) { iconName in
                        Button {
                            selectedIconName = iconName
                        } label: {
                            Image(systemName: iconName)
                                .font(.headline)
                                .foregroundStyle(selectedIconName == iconName ? .white : AlarmTheme.accentColor(for: selectedThemeIndex))
                                .frame(width: 38, height: 38)
                                .background(
                                    selectedIconName == iconName
                                        ? AlarmTheme.accentColor(for: selectedThemeIndex)
                                        : Color.white.opacity(0.64),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("图标")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct OrdinaryAlarmRow: View {
    let alarm: OrdinaryAlarmSettings
    @Binding var selectedTime: Date
    @Binding var isEnabled: Bool
    @Binding var isWeatherAdjustmentEnabled: Bool
    @Binding var isCommuteAdjustmentEnabled: Bool
    let isScheduling: Bool
    let scenePhase: ScenePhase
    let weatherPreview: HourlyWeatherSummary?
    let commutePreview: OrdinaryAlarmCommutePreview?
    let advanceDisplay: AlarmAdvanceDisplay?
    @Binding var selectedArrivalTime: Date
    let route: CommuteRoute?
    let commuteStartText: String
    let commuteEndText: String
    let commuteRouteText: String
    let commuteSyncMessage: String?
    let isWeatherAdjustmentUnlocked: Bool
    let isCommuteAdjustmentUnlocked: Bool
    let selectedCommuteMode: CommuteMode
    let onLockedWeatherTap: () -> Void
    let onLockedPathTap: () -> Void
    let onTitleChanged: (String) -> Void
    let onAppearanceChanged: (Int, String) -> Void
    let onRepeatWeekdayToggle: (Int) -> Void
    let onRepeatPresetSelected: ([Int]) -> Void
    let onSnoozeChanged: (Int) -> Void
    let onChallengeChanged: (OrdinaryAlarmDismissChallenge) -> Void
    let onSoundChanged: (AlarmSoundChoice) -> Void
    let onLoudVolumeChanged: (Bool) -> Void
    let onArrivalTimeChanged: (Date) -> Void
    let onCommuteModeChanged: (CommuteMode) -> Void
    let onSelectCommuteStart: () -> Void
    let onSelectCommuteEnd: () -> Void
    let onSchedule: () -> Void
    let onCollapsed: () -> Void
    let onAutoSave: () -> Void
    let onRefreshCommutePreview: () -> Void
    private let initiallyExpanded: Bool
    @State private var isExpanded = false
    @State private var isTimePickerExpanded = false
    @State private var isAppearanceExpanded = false
    @State private var isArrivalTimePickerExpanded = false
    @State private var didAutoSaveCurrentEdit = false
    @State private var isEditorPresented = false
    @Environment(\.dismiss) private var dismiss

    init(
        alarm: OrdinaryAlarmSettings,
        selectedTime: Binding<Date>,
        isEnabled: Binding<Bool>,
        isWeatherAdjustmentEnabled: Binding<Bool>,
        isCommuteAdjustmentEnabled: Binding<Bool>,
        isScheduling: Bool,
        scenePhase: ScenePhase,
        weatherPreview: HourlyWeatherSummary?,
        commutePreview: OrdinaryAlarmCommutePreview?,
        selectedArrivalTime: Binding<Date>,
        route: CommuteRoute?,
        commuteStartText: String,
        commuteEndText: String,
        commuteRouteText: String,
        commuteSyncMessage: String?,
        isWeatherAdjustmentUnlocked: Bool,
        isCommuteAdjustmentUnlocked: Bool,
        selectedCommuteMode: CommuteMode,
        onLockedWeatherTap: @escaping () -> Void,
        onLockedPathTap: @escaping () -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onAppearanceChanged: @escaping (Int, String) -> Void,
        onRepeatWeekdayToggle: @escaping (Int) -> Void,
        onRepeatPresetSelected: @escaping ([Int]) -> Void,
        onSnoozeChanged: @escaping (Int) -> Void,
        onChallengeChanged: @escaping (OrdinaryAlarmDismissChallenge) -> Void,
        onSoundChanged: @escaping (AlarmSoundChoice) -> Void,
        onLoudVolumeChanged: @escaping (Bool) -> Void,
        onArrivalTimeChanged: @escaping (Date) -> Void,
        onCommuteModeChanged: @escaping (CommuteMode) -> Void,
        onSelectCommuteStart: @escaping () -> Void,
        onSelectCommuteEnd: @escaping () -> Void,
        onSchedule: @escaping () -> Void,
        onCollapsed: @escaping () -> Void = {},
        onAutoSave: @escaping () -> Void,
        onRefreshCommutePreview: @escaping () -> Void,
        advanceDisplay: AlarmAdvanceDisplay? = nil,
        initiallyExpanded: Bool = false
    ) {
        self.alarm = alarm
        self._selectedTime = selectedTime
        self._isEnabled = isEnabled
        self._isWeatherAdjustmentEnabled = isWeatherAdjustmentEnabled
        self._isCommuteAdjustmentEnabled = isCommuteAdjustmentEnabled
        self.isScheduling = isScheduling
        self.scenePhase = scenePhase
        self.weatherPreview = weatherPreview
        self.commutePreview = commutePreview
        self.advanceDisplay = advanceDisplay
        self._selectedArrivalTime = selectedArrivalTime
        self.route = route
        self.commuteStartText = commuteStartText
        self.commuteEndText = commuteEndText
        self.commuteRouteText = commuteRouteText
        self.commuteSyncMessage = commuteSyncMessage
        self.isWeatherAdjustmentUnlocked = isWeatherAdjustmentUnlocked
        self.isCommuteAdjustmentUnlocked = isCommuteAdjustmentUnlocked
        self.selectedCommuteMode = selectedCommuteMode
        self.onLockedWeatherTap = onLockedWeatherTap
        self.onLockedPathTap = onLockedPathTap
        self.onTitleChanged = onTitleChanged
        self.onAppearanceChanged = onAppearanceChanged
        self.onRepeatWeekdayToggle = onRepeatWeekdayToggle
        self.onRepeatPresetSelected = onRepeatPresetSelected
        self.onSnoozeChanged = onSnoozeChanged
        self.onChallengeChanged = onChallengeChanged
        self.onSoundChanged = onSoundChanged
        self.onLoudVolumeChanged = onLoudVolumeChanged
        self.onArrivalTimeChanged = onArrivalTimeChanged
        self.onCommuteModeChanged = onCommuteModeChanged
        self.onSelectCommuteStart = onSelectCommuteStart
        self.onSelectCommuteEnd = onSelectCommuteEnd
        self.onSchedule = onSchedule
        self.onCollapsed = onCollapsed
        self.onAutoSave = onAutoSave
        self.onRefreshCommutePreview = onRefreshCommutePreview
        self.initiallyExpanded = initiallyExpanded
        _isExpanded = State(initialValue: initiallyExpanded)
        _isTimePickerExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AlarmSummaryHeader(
                iconName: alarm.effectiveIconName,
                iconColor: isEnabled ? AlarmTheme.accentColor(for: alarm.effectiveThemeIndex) : .secondary,
                title: alarm.effectiveTitle,
                timeText: alarm.timeText,
                subtitle: isEnabled ? alarm.repeatSummaryText : "已停用",
                isWeatherEnabled: isWeatherAdjustmentEnabled,
                isCommuteEnabled: isCommuteAdjustmentEnabled,
                weatherPreview: weatherPreview,
                commutePreview: commutePreview,
                advanceDisplay: advanceDisplay,
                isAlarmEnabled: $isEnabled,
                onCardTapped: {
                    if !initiallyExpanded {
                        isEditorPresented = true
                    }
                }
            )

            if isExpanded {
                if isTimePickerExpanded {
                    LargeAlarmTimePicker(
                        title: "响铃时间",
                        selection: $selectedTime,
                        onTimeChanged: {}
                    )
                }

                TextField(
                    "标签，例如：晨跑、上班、吃药",
                    text: Binding(
                        get: { alarm.effectiveTitle == "其他闹钟" ? "" : alarm.effectiveTitle },
                        set: { onTitleChanged($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                DisclosureButton(
                    title: "更改闹钟版式",
                    systemImage: "paintpalette.fill",
                    isExpanded: isAppearanceExpanded
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        isAppearanceExpanded.toggle()
                    }
                }

                if isAppearanceExpanded {
                    AlarmAppearancePicker(
                        selectedThemeIndex: Binding(
                            get: { alarm.effectiveThemeIndex },
                            set: { onAppearanceChanged($0, alarm.effectiveIconName) }
                        ),
                        selectedIconName: Binding(
                            get: { alarm.effectiveIconName },
                            set: { onAppearanceChanged(alarm.effectiveThemeIndex, $0) }
                        )
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    AlarmRepeatEditor(
                        selectedWeekdays: Set(alarm.effectiveRepeatWeekdays),
                        summaryText: alarm.repeatSummaryText,
                        onToggleWeekday: onRepeatWeekdayToggle,
                        onPresetSelected: onRepeatPresetSelected
                    )
                }

                AlarmMenuPickerRow(
                    title: "稍后提醒",
                    systemImage: "repeat.circle.fill",
                    selection: Binding(
                        get: { alarm.effectiveSnoozeMinutes },
                        set: { onSnoozeChanged($0) }
                    )
                ) {
                    ForEach([0, 5, 9, 10, 15, 30], id: \.self) { minutes in
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分钟").tag(minutes)
                    }
                }

                AlarmMenuPickerRow(
                    title: "关闭方式",
                    systemImage: "lock.open.fill",
                    selection: Binding(
                        get: { alarm.effectiveDismissChallenge },
                        set: { onChallengeChanged($0) }
                    )
                ) {
                    ForEach(OrdinaryAlarmDismissChallenge.allCases) { challenge in
                        Text(challenge.displayName).tag(challenge)
                    }
                }

                AlarmSoundNavigationRow(
                    selection: alarm.effectiveSoundChoice,
                    isLoudVersionEnabled: alarm.effectiveIsLoudVolumeEnabled,
                    onSelectionChanged: onSoundChanged
                )

                AlarmLoudVolumeToggleRow(
                    isOn: Binding(
                        get: { alarm.effectiveIsLoudVolumeEnabled },
                        set: { onLoudVolumeChanged($0) }
                    )
                )

                VStack(spacing: 4) {
                    PremiumToggleRow(
                        title: "天气提前",
                        subtitle: "明早有雨雪时，自动提前这个闹钟。",
                        isUnlocked: isWeatherAdjustmentUnlocked,
                        onLockedTap: onLockedWeatherTap,
                        isOn: $isWeatherAdjustmentEnabled
                    )

                    Divider()

                    PremiumToggleRow(
                        title: "路径提前",
                        subtitle: "按堵车、公交雨天步行和骑行降速调整响铃时间。",
                        isUnlocked: isCommuteAdjustmentUnlocked,
                        onLockedTap: onLockedPathTap,
                        isOn: $isCommuteAdjustmentEnabled
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isCommuteAdjustmentEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isArrivalTimePickerExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Label("到达目的地时间", systemImage: "flag.checkered")
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Text(alarm.arrivalTimeText)
                                    .font(.headline.weight(.bold))
                                    .monospacedDigit()

                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .rotationEffect(.degrees(isArrivalTimePickerExpanded ? 180 : 0))
                            }
                            .foregroundStyle(Color(red: 0.46, green: 0.23, blue: 0.07))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.00, green: 0.92, blue: 0.76).opacity(0.88),
                                        Color(red: 1.00, green: 0.78, blue: 0.64).opacity(0.64)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)

                        if isArrivalTimePickerExpanded {
                            DatePicker(
                                "到达目的地时间",
                                selection: Binding(
                                    get: { selectedArrivalTime },
                                    set: {
                                        selectedArrivalTime = $0
                                        onArrivalTimeChanged($0)
                                    }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, minHeight: 112)
                            .background(.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if let commutePreview {
                            SmartAlarmPreviewLine(
                                systemImage: commutePreview.isCongested ? "car.fill" : "map.fill",
                                title: "路径 \(commutePreview.trafficText)",
                                detail: commutePreview.detailText
                            )
                        }
                    }
                }

                CommuteRouteSettingsPanel(
                    route: route,
                    isUnlocked: isCommuteAdjustmentUnlocked,
                    selectedCommuteMode: selectedCommuteMode,
                    startText: commuteStartText,
                    endText: commuteEndText,
                    routeText: commuteRouteText,
                    syncMessage: commuteSyncMessage,
                    onModeChanged: { newMode in
                        onCommuteModeChanged(newMode)
                    },
                    onSelectStart: onSelectCommuteStart,
                    onSelectEnd: onSelectCommuteEnd
                )

                Button {
                    onCollapsed()
                    if initiallyExpanded {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isExpanded = false
                        }
                    }
                } label: {
                    HStack {
                        if isScheduling {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text(isScheduling ? "正在更新闹钟" : "更新此闹钟")
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScheduling || !isEnabled)

            }
        }
        .task(id: isCommuteAdjustmentEnabled) {
            if isCommuteAdjustmentEnabled {
                onRefreshCommutePreview()
            } else {
                isArrivalTimePickerExpanded = false
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            NavigationStack {
                editorDestination
            }
            .presentationDragIndicator(.visible)
        }
        .onChange(of: isExpanded) {
            if isExpanded {
                didAutoSaveCurrentEdit = false
            }
        }
        .onChange(of: scenePhase) {
            guard scenePhase != .active,
                  isExpanded,
                  !didAutoSaveCurrentEdit else {
                return
            }

            didAutoSaveCurrentEdit = true
            onSchedule()
            onAutoSave()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded = false
            }
        }
        .padding(.vertical, 8)
        .padding(12)
        .background {
            AlarmCardGradient(themeIndex: alarm.effectiveThemeIndex)
                .overlay {
                    if isExpanded {
                        Color.white.opacity(0.34)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .opacity(isEnabled ? 1 : 0.58)
    }

    private var editorDestination: some View {
        ScrollView {
            OrdinaryAlarmRow(
                alarm: alarm,
                selectedTime: $selectedTime,
                isEnabled: $isEnabled,
                isWeatherAdjustmentEnabled: $isWeatherAdjustmentEnabled,
                isCommuteAdjustmentEnabled: $isCommuteAdjustmentEnabled,
                isScheduling: isScheduling,
                scenePhase: scenePhase,
                weatherPreview: weatherPreview,
                commutePreview: commutePreview,
                selectedArrivalTime: $selectedArrivalTime,
                route: route,
                commuteStartText: commuteStartText,
                commuteEndText: commuteEndText,
                commuteRouteText: commuteRouteText,
                commuteSyncMessage: commuteSyncMessage,
                isWeatherAdjustmentUnlocked: isWeatherAdjustmentUnlocked,
                isCommuteAdjustmentUnlocked: isCommuteAdjustmentUnlocked,
                selectedCommuteMode: selectedCommuteMode,
                onLockedWeatherTap: onLockedWeatherTap,
                onLockedPathTap: onLockedPathTap,
                onTitleChanged: onTitleChanged,
                onAppearanceChanged: onAppearanceChanged,
                onRepeatWeekdayToggle: onRepeatWeekdayToggle,
                onRepeatPresetSelected: onRepeatPresetSelected,
                onSnoozeChanged: onSnoozeChanged,
                onChallengeChanged: onChallengeChanged,
                onSoundChanged: onSoundChanged,
                onLoudVolumeChanged: onLoudVolumeChanged,
                onArrivalTimeChanged: onArrivalTimeChanged,
                onCommuteModeChanged: onCommuteModeChanged,
                onSelectCommuteStart: {
                    dismissEditorThenOpenRoute(onSelectCommuteStart)
                },
                onSelectCommuteEnd: {
                    dismissEditorThenOpenRoute(onSelectCommuteEnd)
                },
                onSchedule: onSchedule,
                onCollapsed: onCollapsed,
                onAutoSave: onAutoSave,
                onRefreshCommutePreview: onRefreshCommutePreview,
                advanceDisplay: advanceDisplay,
                initiallyExpanded: true
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("编辑闹钟")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dismissEditorThenOpenRoute(_ action: @escaping () -> Void) {
        isEditorPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else {
                return
            }
            action()
        }
    }
}

private struct AlarmRepeatEditor: View {
    let selectedWeekdays: Set<Int>
    let summaryText: String
    let onToggleWeekday: (Int) -> Void
    let onPresetSelected: ([Int]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("重复", systemImage: "repeat")
                Spacer()
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            WeekdayChipsView(
                selectedWeekdays: selectedWeekdays,
                onToggle: onToggleWeekday
            )

            HStack(spacing: 8) {
                RepeatPresetButton(title: "工作日") {
                    onPresetSelected([2, 3, 4, 5, 6])
                }

                RepeatPresetButton(title: "每天") {
                    onPresetSelected([1, 2, 3, 4, 5, 6, 7])
                }

                RepeatPresetButton(title: "仅一次") {
                    onPresetSelected([])
                }
            }
        }
    }
}

private struct RepeatPresetButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
    }
}

private struct WeekdayChipsView: View {
    let selectedWeekdays: Set<Int>
    let onToggle: (Int) -> Void

    private let weekdays: [(value: Int, title: String)] = [
        (2, "一"),
        (3, "二"),
        (4, "三"),
        (5, "四"),
        (6, "五"),
        (7, "六"),
        (1, "日")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekdays, id: \.value) { weekday in
                Button {
                    onToggle(weekday.value)
                } label: {
                    Text(weekday.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedWeekdays.contains(weekday.value) ? .white : .primary)
                        .frame(width: 30, height: 30)
                        .background(
                            selectedWeekdays.contains(weekday.value)
                                ? Color.accentColor
                                : Color(uiColor: .tertiarySystemGroupedBackground),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("周\(weekday.title)")
            }
        }
    }
}

private struct AnimatedAlarmBadge: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let scale = 1.0 + phase * 0.34
            let opacity = 0.32 * (1.0 - phase)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(opacity))
                    .scaleEffect(scale)

                Circle()
                    .fill(Color.accentColor)

                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating, value: isActive)
            }
            .frame(width: 48, height: 48)
        }
    }
}

private struct ForecastInsightRow: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct SmartTimingRulesHomeCard: View {
    let rainMinutes: Int
    let heavyRainMinutes: Int

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "slider.horizontal.3")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Color(red: 0.08, green: 0.47, blue: 0.44), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("个性化提前规则")
                    .font(.headline.weight(.bold))

                Text("小雨 \(rainMinutes) 分钟 · 强降水 \(heavyRainMinutes) 分钟")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        }
    }
}

@MainActor
private struct SmartTimingRuleEditor: View {
    @Binding var rainAdvanceMinutes: Int
    @Binding var heavyRainAdvanceMinutes: Int
    let onRuleChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("按你的早晨节奏设置")
                        .font(.title2.weight(.bold))
                    Text("真实降水强度决定是否触发；这里仅设置触发后的个人准备时间。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 6) {
                    ruleRow(
                        title: "普通降水",
                        subtitle: "轻到中等降水时的准备缓冲",
                        value: $rainAdvanceMinutes,
                        range: 0...90
                    )

                    Divider().padding(.leading, 44)

                    ruleRow(
                        title: "强降水",
                        subtitle: "有可靠降水量支持时才会采用",
                        value: $heavyRainAdvanceMinutes,
                        range: rainAdvanceMinutes...120
                    )
                }
                .padding(14)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Label(
                    "仅有较高降水概率、但没有可靠降水量时，不会直接按强降水处理。",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.05, green: 0.39, blue: 0.37))
                .padding(14)
                .background(Color(red: 0.84, green: 0.97, blue: 0.93), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.99, blue: 1.00),
                    Color(red: 0.96, green: 1.00, blue: 0.97)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("提前规则")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: rainAdvanceMinutes) {
            if heavyRainAdvanceMinutes < rainAdvanceMinutes {
                heavyRainAdvanceMinutes = rainAdvanceMinutes
            } else {
                onRuleChanged()
            }
        }
        .onChange(of: heavyRainAdvanceMinutes) {
            onRuleChanged()
        }
    }

    private func ruleRow(
        title: String,
        subtitle: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: title == "强降水" ? "cloud.heavyrain.fill" : "cloud.rain.fill")
                .foregroundStyle(Color(red: 0.09, green: 0.47, blue: 0.56))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Stepper(value: value, in: range, step: 5) {
                Text("\(value.wrappedValue) 分钟")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            .labelsHidden()

            Text("\(value.wrappedValue) 分")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

@available(iOS 26.0, *)
private struct RouteLocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: ActiveRouteSelection
    @ObservedObject var settingsViewModel: WeatherAlarmSettingsViewModel
    let onRouteSaved: (ActiveRouteSelection) -> Void

    var body: some View {
        RouteWebMapPicker(
            startAddress: currentStartAddress,
            endAddress: currentEndAddress,
            activeRole: selection.role,
            onSave: { startAddress, endAddress in
                let shouldPersistDraft: Bool
                if case .wakeUp = selection.target {
                    shouldPersistDraft = true
                } else {
                    shouldPersistDraft = false
                }
                settingsViewModel.saveCommuteAddressDraft(
                    startAddress: startAddress,
                    endAddress: endAddress,
                    persist: shouldPersistDraft
                )

                let didSave: Bool
                switch selection.target {
                case .wakeUp:
                    didSave = await settingsViewModel.syncCommuteRouteWithMapKit()
                case .ordinaryAlarm(let alarmID):
                    didSave = await settingsViewModel.syncCommuteRouteWithMapKit(
                        forOrdinaryAlarmID: alarmID
                    )
                    if didSave {
                        settingsViewModel.prepareCommuteRouteDraft(
                            from: settingsViewModel.ordinaryAlarmRoute(id: alarmID)
                        )
                    }
                }

                guard didSave else {
                    return false
                }

                dismiss()
                onRouteSaved(selection)
                return true
            }
        )
    }

    private var currentStartAddress: String {
        routeAddress(
            currentValue: settingsViewModel.commuteStartAddress,
            fallback: currentRoute?.startName
        )
    }

    private var currentEndAddress: String {
        routeAddress(
            currentValue: settingsViewModel.commuteEndAddress,
            fallback: currentRoute?.endName
        )
    }

    private var currentRoute: CommuteRoute? {
        switch selection.target {
        case .wakeUp:
            return settingsViewModel.settings?.commuteRoute
        case .ordinaryAlarm(let alarmID):
            return settingsViewModel.ordinaryAlarmRoute(id: alarmID)
        }
    }

    private func routeAddress(currentValue: String, fallback: String?) -> String {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct RouteEndpointButton: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(value.contains("点此") ? .secondary : .primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CommuteRouteSettingsPanel: View {
    let route: CommuteRoute?
    let isUnlocked: Bool
    let selectedCommuteMode: CommuteMode
    let startText: String
    let endText: String
    let routeText: String
    let syncMessage: String?
    let onModeChanged: (CommuteMode) -> Void
    let onSelectStart: () -> Void
    let onSelectEnd: () -> Void
    @State private var commuteModeDraft: CommuteMode

    init(
        route: CommuteRoute?,
        isUnlocked: Bool,
        selectedCommuteMode: CommuteMode,
        startText: String,
        endText: String,
        routeText: String,
        syncMessage: String?,
        onModeChanged: @escaping (CommuteMode) -> Void,
        onSelectStart: @escaping () -> Void,
        onSelectEnd: @escaping () -> Void
    ) {
        self.route = route
        self.isUnlocked = isUnlocked
        self.selectedCommuteMode = selectedCommuteMode
        self.startText = startText
        self.endText = endText
        self.routeText = routeText
        self.syncMessage = syncMessage
        self.onModeChanged = onModeChanged
        self.onSelectStart = onSelectStart
        self.onSelectEnd = onSelectEnd
        _commuteModeDraft = State(initialValue: selectedCommuteMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isUnlocked {
                CommuteMapPreview(route: route)

                Picker("通勤方式", selection: $commuteModeDraft) {
                    ForEach(CommuteMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: commuteModeDraft) {
                    onModeChanged(commuteModeDraft)
                }
                .onChange(of: selectedCommuteMode) {
                    if commuteModeDraft != selectedCommuteMode {
                        commuteModeDraft = selectedCommuteMode
                    }
                }

                VStack(spacing: 10) {
                    RouteEndpointButton(
                        title: "出发地",
                        value: startText,
                        systemImage: "location.circle.fill",
                        action: onSelectStart
                    )

                    RouteEndpointButton(
                        title: "目的地",
                        value: endText,
                        systemImage: "mappin.circle.fill",
                        action: onSelectEnd
                    )
                }
            } else {
                Button(action: onSelectStart) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.10, green: 0.42, blue: 0.36))
                            .frame(width: 36, height: 36)
                            .background(Color(red: 0.80, green: 0.98, blue: 0.88), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("解锁路径后设置路线")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)

                            Text("付费前不会发起路线查询，也不会打开地图输入。")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("当前路线")
                    .font(.headline)

                Text(routeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(syncMessage.contains("失败") ? .red : .secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .background(.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
    }
}

private struct WeatherMoodHeaderView: View {
    let baseTimeText: String
    let suggestedTimeText: String
    let advanceText: String?
    let statusText: String
    let weatherText: String
    let hourlyForecast: [HourlyWeatherSummary]
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一次响铃")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.44))

                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(suggestedTimeText)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if let advanceText {
                            Text(advanceBadgeText(for: advanceText))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.05, green: 0.43, blue: 0.40))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.82, green: 0.96, blue: 0.92), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 4)

                WeatherConditionSymbolView(
                    condition: displayCondition,
                    isRefreshing: isRefreshing
                )
                .frame(width: 62, height: 62)
            }

            Text(statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.black.opacity(0.06))

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WeatherDisplayIcon.systemName(for: displayCondition))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.44))

                Text(weatherText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Text("原定 \(baseTimeText)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primary.opacity(0.62))
                    .monospacedDigit()
                    .fixedSize()
            }

            if isRefreshing {
                Label("正在读取真实天气", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.44))
            }
        }
        .padding(15)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.73, green: 0.94, blue: 0.90).opacity(0.42),
                    .clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 12, y: 5)
    }

    private var displayCondition: String {
        hourlyForecast.max { lhs, rhs in
            let lhsAmount = lhs.precipitationAmountMillimeters ?? -1
            let rhsAmount = rhs.precipitationAmountMillimeters ?? -1
            if lhsAmount == rhsAmount {
                return lhs.precipitationChancePercent < rhs.precipitationChancePercent
            }
            return lhsAmount < rhsAmount
        }?.weatherCondition
            ?? weatherText
    }

    private func advanceBadgeText(for text: String) -> String {
        if text == "无需提前" || text == "正在计算" || text.contains("提前") {
            return text
        }
        return "提前 \(text)"
    }
}

private enum WeatherDisplayIcon {
    enum Kind {
        case sunny
        case cloudy
        case rainy
        case foggy
        case snowy
        case stormy
    }

    static func systemName(for condition: String) -> String {
        switch kind(for: condition) {
        case .sunny:
            return "sun.max.fill"
        case .cloudy:
            return "cloud.fill"
        case .rainy:
            return "cloud.rain.fill"
        case .foggy:
            return "cloud.fog.fill"
        case .snowy:
            return "cloud.snow.fill"
        case .stormy:
            return "cloud.bolt.rain.fill"
        }
    }

    static func kind(for condition: String) -> Kind {
        let lowercased = condition.lowercased()
        if condition.contains("雷") || lowercased.contains("thunder") {
            return .stormy
        }

        if condition.contains("雪") || lowercased.contains("snow") {
            return .snowy
        }

        if condition.contains("雨") || lowercased.contains("rain") || lowercased.contains("drizzle") {
            return .rainy
        }

        if condition.contains("雾") || lowercased.contains("fog") || lowercased.contains("haze") {
            return .foggy
        }

        if condition.contains("云") || lowercased.contains("cloud") || lowercased.contains("overcast") {
            return .cloudy
        }

        return .sunny
    }
}

private struct WeatherConditionSymbolView: View {
    let condition: String
    let isRefreshing: Bool

    var body: some View {
        ZStack {
            if isRefreshing {
                Circle()
                    .fill(.white.opacity(0.52))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 5)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.90, blue: 0.62),
                                Color(red: 1.00, green: 0.84, blue: 0.46)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(12)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.44, blue: 0.42))
            } else {
                weatherGlyph
            }
        }
    }

    @ViewBuilder
    private var weatherGlyph: some View {
        let kind = WeatherDisplayIcon.kind(for: condition)

        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.89, blue: 0.48).opacity(0.92),
                            Color(red: 0.62, green: 0.90, blue: 1.00).opacity(0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(2)
                .shadow(color: Color(red: 0.13, green: 0.34, blue: 0.42).opacity(0.16), radius: 8, y: 5)

            switch kind {
            case .sunny:
                Circle()
                    .fill(Color.orange.opacity(0.20))
                    .blur(radius: 3)
                    .padding(1)

                Circle()
                    .fill(Color.yellow)
                    .frame(width: 42, height: 42)
                    .offset(x: -12, y: -12)

                Circle()
                    .fill(Color.orange.opacity(0.88))
                    .frame(width: 22, height: 22)
                    .offset(x: -12, y: -12)

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(0.34))
                    .offset(x: -12, y: -12)

            case .cloudy:
                Circle()
                    .fill(Color.yellow.opacity(0.82))
                    .frame(width: 34, height: 34)
                    .offset(x: -13, y: -10)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.28), radius: 5, y: 3)
                    .offset(x: 5, y: 3)

            case .rainy:
                Circle()
                    .fill(Color.yellow.opacity(0.74))
                    .frame(width: 32, height: 32)
                    .offset(x: -12, y: -13)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.28), radius: 5, y: 3)
                    .offset(x: 4, y: -1)

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue)
                        .frame(width: 4, height: 15)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue.opacity(0.82))
                        .frame(width: 4, height: 19)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.blue.opacity(0.68))
                        .frame(width: 4, height: 14)
                }
                .offset(y: 24)

            case .foggy:
                Image(systemName: "cloud.fog.fill")
                    .font(.system(size: 43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.26), radius: 5, y: 3)

            case .snowy:
                Image(systemName: "cloud.snow.fill")
                    .font(.system(size: 43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.cyan.opacity(0.28), radius: 5, y: 3)

            case .stormy:
                Image(systemName: "cloud.fill")
                    .font(.system(size: 43, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.28), radius: 5, y: 3)
                    .offset(y: -3)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.purple)
                    .offset(x: 5, y: 18)

                HStack(spacing: 7) {
                    Capsule().fill(Color.blue).frame(width: 4, height: 13)
                    Capsule().fill(Color.blue.opacity(0.78)).frame(width: 4, height: 16)
                }
                .offset(x: -16, y: 23)
            }
        }
    }
}

private struct RainMoodGraphic: View {
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Capsule()
                    .fill(.white)
                    .frame(width: 76, height: 34)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                Circle()
                    .fill(.white)
                    .frame(width: 34, height: 34)
                    .offset(x: -18, y: -8)

                Circle()
                    .fill(.white)
                    .frame(width: 42, height: 42)
                    .offset(x: 12, y: -10)
            }

            HStack(spacing: 12) {
                RainDropView(height: 18)
                RainDropView(height: 24)
                RainDropView(height: 16)
            }
            .foregroundStyle(Color(red: 0.18, green: 0.50, blue: 0.92).opacity(0.78))
        }
        .frame(width: 116, height: 118)
    }
}

private struct RainDropView: View {
    let height: CGFloat

    var body: some View {
        Capsule()
            .frame(width: 3, height: height)
    }
}

struct CommuteMapPreview: View {
    let route: CommuteRoute?
    let height: CGFloat
    let showsStatusOverlay: Bool

    init(route: CommuteRoute?, height: CGFloat = 190, showsStatusOverlay: Bool = true) {
        self.route = route
        self.height = height
        self.showsStatusOverlay = showsStatusOverlay
    }

    var body: some View {
        Group {
            if let route {
                RouteMapView(route: route)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if showsStatusOverlay {
                            Text("\(route.effectiveMode.displayName) · 已保存路线")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(12)
                        }
                    }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text("保存路线后显示地图")
                        .font(.headline)

                    Text("输入出发地和目的地后，会为你计算路线耗时和提前量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: max(150, height), alignment: .leading)
                .padding(16)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RouteMapView: UIViewRepresentable {
    let route: CommuteRoute

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isUserInteractionEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
        mapView.pointOfInterestFilter = .excludingAll
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .flat,
                emphasisStyle: .muted
            )
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        guard context.coordinator.lastRoute != route else {
            return
        }
        context.coordinator.lastRoute = route

        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)

        let start = MKPointAnnotation()
        start.title = route.startName ?? "出发地"
        start.subtitle = "起点"
        start.coordinate = route.startCoordinate

        let end = MKPointAnnotation()
        end.title = route.endName ?? "目的地"
        end.subtitle = "终点"
        end.coordinate = route.endCoordinate

        mapView.addAnnotations([start, end])

        let coordinates = [route.startCoordinate, route.endCoordinate]
        let polyline = coordinates.withUnsafeBufferPointer { buffer in
            MKPolyline(coordinates: buffer.baseAddress!, count: buffer.count)
        }
        mapView.addOverlay(polyline)

        var mapRect = polyline.boundingMapRect
        if mapRect.isNull || mapRect.size.width == 0 || mapRect.size.height == 0 {
            let point = MKMapPoint(route.startCoordinate)
            mapRect = MKMapRect(x: point.x, y: point.y, width: 10_000, height: 10_000)
        }

        mapView.setVisibleMapRect(
            mapRect,
            edgePadding: UIEdgeInsets(top: 42, left: 42, bottom: 42, right: 42),
            animated: false
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
        coordinator.lastRoute = nil
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastRoute: CommuteRoute?

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? MKPointAnnotation else {
                return nil
            }

            let identifier = "SmartWakeRouteMarker"
            let marker = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: point, reuseIdentifier: identifier)
            marker.annotation = point
            marker.canShowCallout = true
            marker.markerTintColor = point.subtitle == "起点"
                ? UIColor(red: 0.18, green: 0.74, blue: 0.86, alpha: 1)
                : UIColor(red: 0.98, green: 0.54, blue: 0.20, alpha: 1)
            marker.glyphImage = UIImage(systemName: point.subtitle == "起点" ? "location.fill" : "flag.fill")
            return marker
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.18, green: 0.74, blue: 0.86, alpha: 0.95)
                renderer.lineWidth = 5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

enum SmartWakeManualScreenshotScreen: String, CaseIterable, Identifiable {
    case home
    case permissions
    case weather
    case route
    case alarm
    case freshAlarm = "fresh-alarm"
    case freshSound = "fresh-sound"
    case paywall
    case invite
    case crowdfunding
    case settings
    case troubleshooting

    var id: String { rawValue }
}

@available(iOS 26.0, *)
struct SmartWakeManualScreensRoot: View {
    let screen: SmartWakeManualScreenshotScreen
    @StateObject private var subscriptionStore = StoreKitSubscriptionStore()
    @StateObject private var offerStore = PurchaseOfferStore()
    @State private var selectedWakeUpTime = Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: Date()) ?? Date()
    @State private var selectedCommuteMode: CommuteMode = .driving
    @State private var isSmartAdjustmentEnabled = true
    @State private var isCommuteAdjustmentEnabled = true
    @State private var isManualWakeEnabled = true
    @State private var selectedAlarmArrival = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var manualAlarmTitle = "起床闹钟"
    @State private var manualSoundSelection: AlarmSoundSelection = .builtIn(.radar)
    @State private var manualDismissChallenge: OrdinaryAlarmDismissChallenge = .steps
    @State private var manualLoudVolumeEnabled = true

    var body: some View {
        switch screen {
        case .home:
            manualHome
        case .permissions:
            manualPermissions
        case .weather:
            manualWeather
        case .route:
            manualRoute
        case .alarm:
            manualAlarm
        case .freshAlarm:
            manualFreshAlarm
        case .freshSound:
            manualFreshSound
        case .paywall:
            PaywallView(store: subscriptionStore, offerStore: offerStore, focus: .general)
                .environmentObject(AuthSessionViewModel())
        case .invite:
            InviteView()
        case .crowdfunding:
            CrowdfundingView(store: subscriptionStore)
        case .settings:
            manualSettings
        case .troubleshooting:
            manualTroubleshooting
        }
    }

    private var manualHome: some View {
        NavigationStack {
            SmartWakeFreshAppShell(
                wakeTimeText: "07:04",
                wakeBaseTimeText: "07:10",
                wakeAdvanceMinutes: 6,
                wakeWeatherAdvanceMinutes: 0,
                wakeRouteAdvanceMinutes: 6,
                alarmTitle: "起床闹钟",
                repeatSummary: "工作日",
                countdownText: "闹钟会在 8 小时 44 分钟后响铃",
                weatherHeadline: "明早多云 · 降水概率 7%",
                weatherDetail: "多云 · 7% · 0.0 毫米",
                routeDetail: "驾车约 31 分钟 · 路径自动提前 6 分钟",
                hourlyForecast: sampleForecast,
                wakeRoute: sampleRoute,
                totalAdvanceText: "总共提前 6 分钟",
                ordinaryAlarms: [sampleOrdinaryAlarm],
                ordinaryAdvanceDisplays: [
                    sampleOrdinaryAlarm.id: AlarmAdvanceDisplay(
                        advanceMinutes: 6,
                        weatherAdvanceMinutes: 0,
                        routeAdvanceMinutes: 6,
                        scheduledWakeUpDate: selectedWakeUpTime.addingTimeInterval(-6 * 60)
                    )
                ],
                wakeThemeIndex: 2,
                wakeIconName: "sunrise.fill",
                hasWeatherAccess: true,
                hasRouteAccess: true,
                isWakeWeatherEnabled: true,
                isWakeRouteEnabled: true,
                wakeEnabled: $isManualWakeEnabled,
                onEditWakeAlarm: {},
                onOpenWakeRoute: {},
                onEditOrdinaryAlarm: { _ in },
                onToggleOrdinaryAlarm: { _, _ in },
                onDeleteOrdinaryAlarm: { _ in },
                onAddAlarm: {},
                onOpenPremium: {},
                onInvite: {},
                onCrowdfunding: {}
            )
        }
    }

    private var manualFreshAlarm: some View {
        SmartWakeFreshAlarmEditor(
            screenTitle: "唤醒闹钟",
            selectedTime: $selectedWakeUpTime,
            alarmTitle: $manualAlarmTitle,
            themeIndex: 2,
            iconName: "sunrise.fill",
            snoozeMinutes: 9,
            selectedWeekdays: [2, 3, 4, 5, 6],
            soundSelection: $manualSoundSelection,
            dismissChallenge: $manualDismissChallenge,
            isLoudVolumeEnabled: $manualLoudVolumeEnabled,
            isWeatherEnabled: $isSmartAdjustmentEnabled,
            isRouteEnabled: $isCommuteAdjustmentEnabled,
            isAlarmEnabled: $isManualWakeEnabled,
            selectedArrivalTime: $selectedAlarmArrival,
            weatherUnlocked: true,
            routeUnlocked: true,
            weatherSummary: "多云 · 降水概率 7% · 0.0 毫米",
            routeSummary: "驾车约 31 分钟 · 路径提前 6 分钟",
            advanceDisplay: AlarmAdvanceDisplay(
                advanceMinutes: 6,
                weatherAdvanceMinutes: 0,
                routeAdvanceMinutes: 6,
                scheduledWakeUpDate: selectedWakeUpTime.addingTimeInterval(-6 * 60)
            ),
            route: sampleRoute,
            selectedCommuteMode: selectedCommuteMode,
            commuteStartText: sampleRoute.startName ?? "示例出发地",
            commuteEndText: sampleRoute.endName ?? "示例目的地",
            commuteRouteText: "驾车约 31 分钟，约 5.2 公里",
            commuteSyncMessage: "已同步通勤路线",
            isSchedulingAlarm: false,
            isSchedulingTestAlarm: false,
            onToggleWeekday: { _ in },
            onSelectWeekdays: { _ in },
            onAppearanceChanged: { _, _ in },
            onSnoozeChanged: { _ in },
            onLockedWeather: {},
            onLockedRoute: {},
            onCommuteModeChanged: { selectedCommuteMode = $0 },
            onSelectCommuteStart: {},
            onSelectCommuteEnd: {},
            onScheduleTest: {},
            onDelete: nil,
            onSave: {}
        )
    }

    private var manualFreshSound: some View {
        NavigationStack {
            SmartWakeFreshSoundPicker(
                selection: $manualSoundSelection,
                loudVersion: manualLoudVolumeEnabled
            )
        }
    }

    private var manualHomeLegacy: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WeatherMoodHeaderView(
                    baseTimeText: "07:10",
                    suggestedTimeText: "07:04",
                    advanceText: "6 分钟",
                    statusText: "明早多云，路径拥堵触发提前",
                    weatherText: "多云 · 7% · 0.0 毫米",
                    hourlyForecast: sampleForecast,
                    isRefreshing: false
                )

                SystemAlarmVolumeInfoPanel()

                WakeAlarmControlPanel(
                    title: "起床闹钟",
                    wakeUpTimeText: "07:10",
                    repeatSummaryText: "工作日",
                    selectedRepeatWeekdays: [2, 3, 4, 5, 6],
                    themeIndex: 2,
                    iconName: "sun.max.fill",
                    dismissChallenge: .math,
                    soundChoice: .radar,
                    isLoudVolumeEnabled: true,
                    weatherPreview: sampleForecast.dropFirst(3).first,
                    commutePreview: sampleCommutePreview,
                    arrivalTimeText: "08:30",
                    route: sampleRoute,
                    selectedCommuteMode: selectedCommuteMode,
                    commuteStartText: sampleRoute.startName ?? "示例出发地",
                    commuteEndText: sampleRoute.endName ?? "示例目的地",
                    commuteRouteText: "驾车约 31 分钟，5.2 公里",
                    commuteSyncMessage: "已同步通勤路线",
                    selectedWakeUpTime: $selectedWakeUpTime,
                    selectedArrivalTime: .constant(selectedAlarmArrival),
                    isSmartAdjustmentEnabled: $isSmartAdjustmentEnabled,
                    isCommuteAdjustmentEnabled: $isCommuteAdjustmentEnabled,
                    isSmartAdjustmentUnlocked: true,
                    isCommuteAdjustmentUnlocked: true,
                    isSchedulingWakeAlarm: false,
                    isSchedulingTestAlarm: false,
                    onLockedWeatherTap: {},
                    onLockedPathTap: {},
                    onTimeChanged: {},
                    onArrivalTimeChanged: { _ in },
                    onTitleChanged: { _ in },
                    onRepeatWeekdayToggle: { _ in },
                    onRepeatPresetSelected: { _ in },
                    onAppearanceChanged: { _, _ in },
                    onChallengeChanged: { _ in },
                    onSoundChanged: { _ in },
                    onLoudVolumeChanged: { _ in },
                    onCommuteModeChanged: { _ in },
                    onSelectCommuteStart: {},
                    onSelectCommuteEnd: {},
                    onCollapsed: {},
                    onScheduleWakeAlarm: {},
                    onScheduleTestAlarm: {},
                    advanceDisplay: AlarmAdvanceDisplay(
                        advanceMinutes: 6,
                        weatherAdvanceMinutes: 0,
                        routeAdvanceMinutes: 6,
                        scheduledWakeUpDate: selectedWakeUpTime.addingTimeInterval(-6 * 60)
                    ),
                    initiallyExpanded: false
                )
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualPermissions: some View {
        VStack(spacing: 18) {
            Text("SmartWake 想获取你的位置信息")
                .font(.title3.weight(.bold))
            Text("我们需要基于天气和通勤条件，帮你提前判断是否该更早出门。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
                .frame(height: 180)
                .overlay(alignment: .center) {
                    VStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("建议选择“始终允许”")
                            .font(.headline.weight(.bold))
                        Text("这样 SmartWake 才能在闹钟前帮你刷新天气和路线。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }
                }

            HStack(spacing: 10) {
                Capsule().fill(Color.gray.opacity(0.18)).frame(height: 48).overlay(Text("允许一次").font(.headline))
                Capsule().fill(Color.gray.opacity(0.18)).frame(height: 48).overlay(Text("使用 App 时允许").font(.headline))
                Capsule().fill(Color.gray.opacity(0.18)).frame(height: 48).overlay(Text("不允许").font(.headline))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualWeather: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WeatherMoodHeaderView(
                    baseTimeText: "07:10",
                    suggestedTimeText: "07:10",
                    advanceText: "无需提前",
                    statusText: "明早多云，当前未触发提前",
                    weatherText: "多云，降水概率 7%",
                    hourlyForecast: sampleForecast,
                    isRefreshing: false
                )
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualRoute: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CommuteRouteSettingsPanel(
                    route: sampleRoute,
                    isUnlocked: true,
                    selectedCommuteMode: selectedCommuteMode,
                    startText: "北京市西城区什刹海街道山釜餐厅",
                    endText: "北京市西城区德胜街道德胜门东滨河路中国工程院",
                    routeText: "驾车：北京市西城区什刹海街道山釜餐厅 → 北京市西城区德胜街道德胜门东滨河路中国工程院，预计 31 分钟，约 5.2 公里",
                    syncMessage: "已同步通勤路线",
                    onModeChanged: { _ in },
                    onSelectStart: {},
                    onSelectEnd: {}
                )
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualAlarm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WakeAlarmControlPanel(
                    title: "起床闹钟",
                    wakeUpTimeText: "07:10",
                    repeatSummaryText: "工作日",
                    selectedRepeatWeekdays: [2, 3, 4, 5, 6],
                    themeIndex: 2,
                    iconName: "sun.max.fill",
                    dismissChallenge: .math,
                    soundChoice: .radar,
                    isLoudVolumeEnabled: true,
                    weatherPreview: sampleForecast.dropFirst(3).first,
                    commutePreview: sampleCommutePreview,
                    arrivalTimeText: "08:30",
                    route: sampleRoute,
                    selectedCommuteMode: selectedCommuteMode,
                    commuteStartText: sampleRoute.startName ?? "示例出发地",
                    commuteEndText: sampleRoute.endName ?? "示例目的地",
                    commuteRouteText: "驾车约 31 分钟，5.2 公里",
                    commuteSyncMessage: "已同步通勤路线",
                    selectedWakeUpTime: $selectedWakeUpTime,
                    selectedArrivalTime: .constant(selectedAlarmArrival),
                    isSmartAdjustmentEnabled: $isSmartAdjustmentEnabled,
                    isCommuteAdjustmentEnabled: $isCommuteAdjustmentEnabled,
                    isSmartAdjustmentUnlocked: true,
                    isCommuteAdjustmentUnlocked: true,
                    isSchedulingWakeAlarm: false,
                    isSchedulingTestAlarm: false,
                    onLockedWeatherTap: {},
                    onLockedPathTap: {},
                    onTimeChanged: {},
                    onArrivalTimeChanged: { _ in },
                    onTitleChanged: { _ in },
                    onRepeatWeekdayToggle: { _ in },
                    onRepeatPresetSelected: { _ in },
                    onAppearanceChanged: { _, _ in },
                    onChallengeChanged: { _ in },
                    onSoundChanged: { _ in },
                    onLoudVolumeChanged: { _ in },
                    onCommuteModeChanged: { _ in },
                    onSelectCommuteStart: {},
                    onSelectCommuteEnd: {},
                    onCollapsed: {},
                    onScheduleWakeAlarm: {},
                    onScheduleTestAlarm: {},
                    initiallyExpanded: true
                )

                OrdinaryAlarmRow(
                    alarm: sampleOrdinaryAlarm,
                    selectedTime: .constant(selectedAlarmTime),
                    isEnabled: .constant(true),
                    isWeatherAdjustmentEnabled: .constant(true),
                    isCommuteAdjustmentEnabled: .constant(true),
                    isScheduling: false,
                    scenePhase: .active,
                    weatherPreview: sampleForecast.first,
                    commutePreview: sampleCommutePreview,
                    selectedArrivalTime: $selectedAlarmArrival,
                    route: sampleRoute,
                    commuteStartText: "北京市西城区什刹海街道山釜餐厅",
                    commuteEndText: "北京市西城区德胜街道德胜门东滨河路中国工程院",
                    commuteRouteText: "驾车：北京市西城区什刹海街道山釜餐厅 → 北京市西城区德胜街道德胜门东滨河路中国工程院，预计 31 分钟，约 5.2 公里",
                    commuteSyncMessage: "路径已同步",
                    isWeatherAdjustmentUnlocked: true,
                    isCommuteAdjustmentUnlocked: true,
                    selectedCommuteMode: .driving,
                    onLockedWeatherTap: {},
                    onLockedPathTap: {},
                    onTitleChanged: { _ in },
                    onAppearanceChanged: { _, _ in },
                    onRepeatWeekdayToggle: { _ in },
                    onRepeatPresetSelected: { _ in },
                    onSnoozeChanged: { _ in },
                    onChallengeChanged: { _ in },
                    onSoundChanged: { _ in },
                    onLoudVolumeChanged: { _ in },
                    onArrivalTimeChanged: { _ in },
                    onCommuteModeChanged: { _ in },
                    onSelectCommuteStart: {},
                    onSelectCommuteEnd: {},
                    onSchedule: {},
                    onAutoSave: {},
                    onRefreshCommutePreview: {},
                    initiallyExpanded: true
                )
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AlarmAppearancePicker(
                    selectedThemeIndex: .constant(3),
                    selectedIconName: .constant("cloud.rain.fill")
                )
                AlarmMenuPickerRow(
                    title: "铃声",
                    systemImage: "speaker.wave.2.fill",
                    selection: .constant(AlarmSoundChoice.apex)
                ) {
                    Text(AlarmSoundChoice.apex.displayName).tag(AlarmSoundChoice.apex)
                }
                AlarmLoudVolumeToggleRow(isOn: .constant(true))
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var manualTroubleshooting: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("如果天气或路线暂时刷新失败，SmartWake 会保留基础闹钟。")
                .font(.headline)
            Text("1. 检查通知权限\n2. 检查定位权限\n3. 重新点一下刷新按钮\n4. 保留当前闹钟继续使用")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var sampleForecast: [HourlyWeatherSummary] {
        let base = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
        return [
            (-2, "多云", 5, 0.0),
            (-1, "多云", 7, 0.0),
            (0, "晴", 2, 0.0),
            (1, "晴", 2, 0.0),
            (2, "多云", 5, 0.0),
            (3, "小雨", 42, 0.6),
            (4, "小雨", 55, 1.2)
        ].compactMap { offset, condition, chance, amount in
            Calendar.current.date(byAdding: .hour, value: offset, to: base).map {
                HourlyWeatherSummary(
                    date: $0,
                    weatherCondition: condition,
                    precipitationChancePercent: Double(chance),
                    precipitationAmountMillimeters: amount
                )
            }
        }
    }

    private var sampleRoute: CommuteRoute {
        CommuteRoute(
            startName: "山釜餐厅",
            startLatitude: 39.9376,
            startLongitude: 116.3584,
            endName: "中国工程院",
            endLatitude: 39.9536,
            endLongitude: 116.3755,
            mode: .driving,
            city: "北京市",
            baseDurationSeconds: 1860,
            baseDistanceMeters: 5200,
            baseWalkingDistanceMeters: 1200,
            coordinateSystem: "wgs84"
        )
    }

    private var sampleOrdinaryAlarm: OrdinaryAlarmSettings {
        OrdinaryAlarmSettings(
            hour: 7,
            minute: 10,
            isEnabled: true,
            title: "晨会",
            repeatWeekdays: [2, 3, 4, 5, 6],
            themeIndex: 4,
            iconName: "calendar",
            snoozeMinutes: 10,
            dismissChallenge: .shake,
            soundChoice: .beacon,
            isWeatherAdjustmentEnabled: true,
            isCommuteAdjustmentEnabled: true,
            arrivalHour: 8,
            arrivalMinute: 0,
            commuteModeSuggestion: .driving
        )
    }

    private var selectedAlarmTime: Date {
        Calendar.current.date(bySettingHour: 7, minute: 10, second: 0, of: Date()) ?? Date()
    }

    private var sampleCommutePreview: OrdinaryAlarmCommutePreview {
        OrdinaryAlarmCommutePreview(
            trafficText: "拥堵",
            detailText: "驾车约 31 分钟 · 常规 25 分钟 · 路径自动提前 6 分钟",
            delayMinutes: 6,
            arrivalAdvanceMinutes: 0,
            recommendedDepartureDate: nil,
            recommendedDepartureText: nil,
            isCongested: true
        )
    }
}

@available(iOS 26.0, *)
private struct FastUnlockPaywallView: View {
    @ObservedObject var store: StoreKitSubscriptionStore
    let focus: SubscriptionPaywallFocus
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var didScheduleProductLoad = false
    @State private var isCrowdfundingPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(Color(red: 0.05, green: 0.08, blue: 0.13))

                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.82, green: 0.97, blue: 0.96),
                                Color(red: 0.92, green: 1.00, blue: 0.90),
                                Color(red: 0.93, green: 0.96, blue: 1.00)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                    if focus != .path {
                        unlockRow(
                            title: "天气年订阅",
                            price: "198 元/年",
                            note: "雨雪天气自动提前闹钟，适合长期使用。",
                            productID: WeatherAlarmProductID.weatherYearly,
                            isRecommended: true
                        )

                        unlockRow(
                            title: "天气永久买断",
                            price: "298 元限时",
                            note: "只包含天气功能，不包含路径功能。",
                            productID: WeatherAlarmProductID.foreverCommute,
                            isRecommended: false
                        )
                    }

                    if focus != .weather {
                        unlockRow(
                            title: "路径年订阅",
                            price: "198 元/年",
                            note: "堵车、公交雨天步行、骑行降速一起算。",
                            productID: WeatherAlarmProductID.gaodeEnhanceYearly,
                            isRecommended: true
                        )

                        unlockRow(
                            title: "路径月订阅",
                            price: "19 元/月",
                            note: "先用一个月测试真实通勤调整。",
                            productID: WeatherAlarmProductID.gaodeEnhance,
                            isRecommended: false
                        )
                    }

                    if let message {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }

                    if SmartWakeReleasePolicy.showsExperimentalFeatures {
                        crowdfundingEntry
                    }
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("解锁安心早晨")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(Color(uiColor: .label).opacity(0.78))
                }
            }
            .onAppear {
                scheduleProductLoadIfNeeded(after: 0.45)
            }
            .sheet(isPresented: $isCrowdfundingPresented) {
                NavigationStack {
                    CrowdfundingView(store: store)
                }
            }
        }
    }

    private var title: String {
        switch focus {
        case .weather:
            return "开启天气提前"
        case .path:
            return "开启路径提前"
        case .general:
            return "明早更稳一点"
        }
    }

    private var subtitle: String {
        switch focus {
        case .weather:
            return "下雨、降温、强降水时，提前帮你重新计算响铃时间。"
        case .path:
            return "出发地、目的地、堵车和雨天通勤变慢，都在这里解锁。"
        case .general:
            return "天气和路径分开付费，按你需要的功能开启。"
        }
    }

    private func unlockRow(
        title: String,
        price: String,
        note: String,
        productID: String,
        isRecommended: Bool
    ) -> some View {
        Button {
            purchase(productID: productID)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.black))
                            .foregroundStyle(.primary)

                        if isRecommended {
                            Text("推荐")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.34))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.80, green: 0.98, blue: 0.88), in: Capsule())
                        }
                    }

                    Text(note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.product(for: productID)?.displayPrice ?? price)
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color(red: 0.10, green: 0.38, blue: 0.82))

                    Text(store.product(for: productID) == nil ? "加载中" : "立即开启")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var crowdfundingEntry: some View {
        Button {
            isCrowdfundingPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.72, green: 0.52, blue: 1.00),
                                        Color(red: 1.00, green: 0.30, blue: 0.43)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(red: 0.82, green: 0.30, blue: 0.92).opacity(0.30), radius: 16, y: 8)

                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("新功能众筹抵扣")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("提前支持 AI 催眠、外卖提醒、提前睡觉闹钟，上线后自动抵扣。")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.top, 8)
                }

                Text("支持后不是一次性的鼓励，而是会变成你未来功能的抵扣权益。")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.17, green: 0.10, blue: 0.42),
                        Color(red: 0.08, green: 0.08, blue: 0.12),
                        Color(red: 0.03, green: 0.03, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: Color(red: 0.46, green: 0.24, blue: 1.00).opacity(0.12), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func purchase(productID: String) {
        guard let product = store.product(for: productID) else {
            scheduleProductLoadIfNeeded(after: 0.05)
            message = "正在加载 App Store 商品，请稍等一秒再点。"
            return
        }

        message = "正在打开 Apple 支付..."
        Task {
            let didPurchase = await store.purchase(product)
            if didPurchase {
                dismiss()
            } else if case .failed(let errorMessage) = store.state {
                message = errorMessage
            } else {
                message = "购买未完成，可以稍后再试。"
            }
        }
    }

    private func scheduleProductLoadIfNeeded(after delay: TimeInterval) {
        guard !didScheduleProductLoad else {
            return
        }

        didScheduleProductLoad = true
        Task { @MainActor in
            let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            store.startLoadingProductsAndEntitlements()
        }
    }
}

private extension DateFormatter {
    static let weatherAlarmHour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
