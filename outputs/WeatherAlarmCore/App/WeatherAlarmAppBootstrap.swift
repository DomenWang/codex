import CoreLocation
import Foundation

/// App 启动时的组装示例。
///
/// 这不是 Mock：`locationProvider` 必须接入你自己的真实定位服务，
/// 例如 CLLocationManager 保存的最近一次授权位置。
@MainActor
@available(iOS 26.0, *)
final class WeatherAlarmAppBootstrap {
    private let backgroundScheduler: WeatherAlarmBackgroundScheduler

    init(locationProvider: @escaping () async throws -> CLLocation) {
        self.backgroundScheduler = WeatherAlarmBackgroundScheduler(locationProvider: locationProvider)
    }

    func start() {
        backgroundScheduler.register()

        do {
            try backgroundScheduler.scheduleNextDaily3AMRefresh()
        } catch {
            // TODO: 将后台任务提交失败写入 App 内诊断日志，方便用户检查 Background Modes 配置。
        }
    }
}

