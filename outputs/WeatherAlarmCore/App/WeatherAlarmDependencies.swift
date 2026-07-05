import Foundation
import Combine

/// App 级依赖容器。
///
/// View 层只拿 `alarmManager` 和 `toastCenter`，不会直接创建或调用 TransitService。
@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmDependencies: ObservableObject {
    let toastCenter = ToastMessageCenter()
    let alarmManager: AlarmManager

    init(settingsStore: AlarmSettingsStore = AlarmSettingsStore()) {
        self.alarmManager = AlarmManager(
            settingsStore: settingsStore,
            toastPresenter: toastCenter
        )
    }
}
