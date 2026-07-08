import SwiftUI

@main
@available(iOS 26.0, *)
struct WeatherAlarmApp: App {
    @StateObject private var dependencies = WeatherAlarmDependencies()
    @StateObject private var authSession = AuthSessionViewModel()
    @StateObject private var referralStateStore = ReferralStateStore()
    @StateObject private var subscriptionStore = StoreKitSubscriptionStore()
    private let restoreWarningNotifier = PurchaseRestoreWarningNotifier()

    var body: some Scene {
        WindowGroup {
            Group {
                if authSession.isSignedIn {
                    ContentView(subscriptionStore: subscriptionStore)
                        .environmentObject(dependencies.toastCenter)
                        .environmentObject(authSession)
                } else {
                    LoginView(viewModel: authSession)
                }
            }
            .task {
                await authSession.restoreSession()
                await subscriptionStore.loadProductsAndEntitlements()
                await restoreWarningNotifier.scheduleIfNeeded()
            }
            .onOpenURL { url in
                referralStateStore.handleInviteURL(url)
            }
        }
    }
}
