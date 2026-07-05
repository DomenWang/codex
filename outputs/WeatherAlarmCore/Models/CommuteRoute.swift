import CoreLocation
import Foundation

/// 用户设置的真实通勤路线。
///
/// 这里不提供默认坐标，避免用固定地点假装路况查询成功。
/// 设置页应让用户选择“出发地”和“目的地”后保存。
struct CommuteRoute: Codable, Equatable {
    let startLatitude: Double
    let startLongitude: Double
    let endLatitude: Double
    let endLongitude: Double

    /// 用户配置或历史统计得到的基础通勤时长，单位：秒。
    ///
    /// 不能在 TransitService 里写死 1800 秒；否则不同用户的通勤路线会被错误计算。
    let baseDurationSeconds: TimeInterval

    var startCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var endCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }
}
