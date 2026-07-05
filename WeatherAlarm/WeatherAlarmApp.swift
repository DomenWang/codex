import SwiftUI

@main
@available(iOS 26.0, *)
struct WeatherAlarmApp: App {
    @StateObject private var dependencies = WeatherAlarmDependencies()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dependencies.toastCenter)
        }
    }
}

