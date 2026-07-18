import CoreLocation
import Foundation
import UserNotifications

@MainActor
@available(iOS 26.0, *)
final class StartupPermissionRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var didRequestThisLaunch = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestAllNeededPermissions(
        toastCenter: ToastMessageCenter,
        alarmManager: AlarmManager
    ) async {
        guard !didRequestThisLaunch else {
            return
        }

        didRequestThisLaunch = true

        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled else {
            return
        }

        await requestNotificationPermission(toastCenter: toastCenter)
        try? await Task.sleep(for: .milliseconds(600))
        await requestAlarmPermission(alarmManager: alarmManager, toastCenter: toastCenter)
        try? await Task.sleep(for: .milliseconds(600))
        await requestLocationPermissions(toastCenter: toastCenter)
    }

    private func requestNotificationPermission(toastCenter: ToastMessageCenter) async {
        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                return
            case .denied:
                toastCenter.showToast("请在系统设置中打开通知，闹钟提醒才不会错过。")
                return
            case .notDetermined:
                break
            @unknown default:
                break
            }

            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            if !granted {
                toastCenter.showToast("请在系统设置中打开通知，闹钟提醒才不会错过。")
            }
        } catch {
            toastCenter.showToast("通知权限请求失败，请稍后在系统设置里打开。")
        }
    }

    private func requestAlarmPermission(
        alarmManager: AlarmManager,
        toastCenter: ToastMessageCenter
    ) async {
        do {
            try await alarmManager.requestAuthorization()
        } catch {
            toastCenter.showToast("请允许系统闹钟权限，SmartWake 才能准时响铃。")
        }
    }

    private func requestLocationPermissions(toastCenter: ToastMessageCenter) async {
        guard CLLocationManager.locationServicesEnabled() else {
            toastCenter.showToast("定位服务未开启，请在系统设置中打开定位服务。")
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            toastCenter.showToast("接下来的定位弹窗请选择“使用 App 时允许”，之后可在设置里改为“始终允许”。")
            let status = await requestWhenInUseAuthorization()
            if status == .authorizedWhenInUse {
                toastCenter.showToast("建议稍后在系统设置中把定位改为“始终允许”，闹钟前刷新更稳。")
            }
        case .authorizedWhenInUse:
            break
        case .authorizedAlways:
            break
        case .denied, .restricted:
            toastCenter.showToast("请在系统设置中把定位改为“始终允许”，天气提前会更稳定。")
        @unknown default:
            toastCenter.showToast("定位权限状态异常，请在系统设置中确认已选择“始终允许”。")
        }
    }

    private func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self,
                      authorizationContinuation != nil else {
                    return
                }

                authorizationContinuation = nil
                continuation.resume(returning: locationManager.authorizationStatus)
            }
        }
    }

    private func requestAlwaysAuthorizationIfPossible(
        status: CLAuthorizationStatus,
        toastCenter: ToastMessageCenter
    ) async {
        guard status == .authorizedWhenInUse else {
            if status != .authorizedAlways {
                toastCenter.showToast("定位未授权，请在系统设置中改为“始终允许”。")
            }
            return
        }

        toastCenter.showToast("为了闹钟前自动刷新天气，请在定位权限中选择“始终允许”。")
        locationManager.requestAlwaysAuthorization()
        try? await Task.sleep(for: .seconds(1))

        if locationManager.authorizationStatus != .authorizedAlways {
            toastCenter.showToast("建议把定位改为“始终允许”，雨天提前和通勤提醒会更稳。")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let continuation = authorizationContinuation else {
                return
            }

            switch manager.authorizationStatus {
            case .notDetermined:
                break
            default:
                authorizationContinuation = nil
                continuation.resume(returning: manager.authorizationStatus)
            }
        }
    }
}
