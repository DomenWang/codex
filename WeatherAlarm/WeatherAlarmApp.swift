import SwiftUI
import UserNotifications
import WidgetKit

@main
@available(iOS 26.0, *)
@MainActor
struct WeatherAlarmApp: App {
    private static let widgetRenderVersion = 2
    private static let widgetRenderVersionKey = "smartwake.widget_render_version"

    @StateObject private var dependencies = WeatherAlarmDependencies()
    @StateObject private var authSession = AuthSessionViewModel()
    @StateObject private var referralStateStore = ReferralStateStore()
    @StateObject private var subscriptionStore = StoreKitSubscriptionStore()
    @StateObject private var wakeNotificationDelegate = WakeNotificationDelegate()
    private let restoreWarningNotifier = PurchaseRestoreWarningNotifier()
    private let backgroundLocationProvider: WeatherAlarmLocationProvider
    private let backgroundBootstrap: WeatherAlarmAppBootstrap
    private let manualScreenshotScreen: SmartWakeManualScreenshotScreen?

    init() {
        self.manualScreenshotScreen = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--smartwake-manual-screen=") })
            .flatMap { argument in
                SmartWakeManualScreenshotScreen(
                    rawValue: String(argument.dropFirst("--smartwake-manual-screen=".count))
                )
            }
        let locationProvider = WeatherAlarmLocationProvider()
        self.backgroundLocationProvider = locationProvider
        let bootstrap = WeatherAlarmAppBootstrap {
            try await locationProvider.requestCurrentLocation()
        }
        self.backgroundBootstrap = bootstrap
        bootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            if let manualScreenshotScreen {
                SmartWakeManualScreensRoot(screen: manualScreenshotScreen)
            } else {
                ContentView(subscriptionStore: subscriptionStore)
                    .environmentObject(dependencies.toastCenter)
                    .environmentObject(authSession)
                    .task {
                        let statusStore = WeatherAlarmStatusStore()
                        let didMigrateStatus = statusStore.migrateLegacyStatusIfNeeded()
                        let sharedDefaults = AppGroupUserDefaults.shared
                        if sharedDefaults.integer(forKey: Self.widgetRenderVersionKey)
                            < Self.widgetRenderVersion {
                            sharedDefaults.set(
                                Self.widgetRenderVersion,
                                forKey: Self.widgetRenderVersionKey
                            )
                            if !didMigrateStatus {
                                WidgetCenter.shared.reloadTimelines(ofKind: "WeatherAlarmWidget")
                            }
                        }
                        WakeNotificationDelegate.registerCategories()
                        UNUserNotificationCenter.current().delegate = wakeNotificationDelegate
                        LocalWakeNotificationScheduler().removeWeatherUpgradeReminder()
                        dependencies.alarmManager.reconcileScheduledAlarmsWithCurrentSettings()
                        await subscriptionStore.loadProductsAndEntitlements()
                        await authSession.restoreSession()
                        await authSession.syncLocalEntitlementsIfPossible()
                        await restoreWarningNotifier.scheduleIfNeeded()
                    }
                    .onOpenURL { url in
                        if url.scheme == "weatherwake",
                           (url.host == "dismiss-challenge" || url.path == "/dismiss-challenge") {
                            NotificationCenter.default.post(name: .weatherAlarmDismissChallengeURLReceived, object: nil)
                        }
                        referralStateStore.handleInviteURL(url)
                    }
            }
        }
    }
}
