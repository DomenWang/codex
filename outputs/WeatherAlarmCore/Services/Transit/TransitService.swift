import CoreLocation
import Foundation

// MARK: - 高德地图 API 响应模型

struct AMapRouteResponse: Codable {
    let status: String
    let info: String
    let route: AMapRoute?
}

struct AMapRoute: Codable {
    let paths: [AMapPath]?
}

struct AMapPath: Codable {
    /// 持续时间，单位：秒。
    let duration: String

    /// 距离，单位：米。
    let distance: String
}

// MARK: - 路况领域模型

enum TrafficLevel {
    case smooth
    case slow
    case congested
    case unknown
}

struct CommuteResult {
    /// 基础通勤时长，单位：秒。
    let baseDuration: TimeInterval

    /// 实时通勤时长，单位：秒。
    let realDuration: TimeInterval

    let trafficLevel: TrafficLevel
}

enum TransitServiceError: LocalizedError {
    case missingAPIKey
    case missingBaseDuration
    case missingRoute
    case invalidAPIResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AMap API Key is missing."
        case .missingBaseDuration:
            return "Base commute duration is missing."
        case .missingRoute:
            return "AMap did not return a usable route."
        case .invalidAPIResponse(let info):
            return info
        }
    }
}

/// 高德地图通勤服务。
///
/// 这里是真实网络请求，不提供 Mock 结果。API Key 缺失、网络超时、服务端失败都会 throw。
final class TransitService {
    // TODO: [重要] 请在此处填入你在高德开放平台申请的 Web 服务 Key。
    // 申请地址: https://console.amap.com/dev/key/app
    private let apiKey = "YOUR_AMAP_WEB_API_KEY_HERE"

    private let session: URLSession
    private let baseDurationProvider: () throws -> TimeInterval

    init(
        session: URLSession = .shared,
        baseDurationProvider: @escaping () throws -> TimeInterval = {
            throw TransitServiceError.missingBaseDuration
        }
    ) {
        self.session = session
        self.baseDurationProvider = baseDurationProvider
    }

    /// 计算两点之间的实时通勤时间。
    ///
    /// - Parameters:
    ///   - start: 起点坐标，WGS84。
    ///   - end: 终点坐标，WGS84。
    /// - Returns: 基础时长、实时路况时长、路况等级。
    func calculateCommute(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) async throws -> CommuteResult {
        guard !apiKey.contains("YOUR_") else {
            throw TransitServiceError.missingAPIKey
        }

        let amapStart = CoordinateTransformer.transformToGCJ(from: start)
        let amapEnd = CoordinateTransformer.transformToGCJ(from: end)

        let origin = "\(amapStart.longitude),\(amapStart.latitude)"
        let destination = "\(amapEnd.longitude),\(amapEnd.latitude)"
        let urlString = "https://restapi.amap.com/v3/direction/driving?origin=\(origin)&destination=\(destination)&extensions=base&strategy=0&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(AMapRouteResponse.self, from: data)

        guard result.status == "1" else {
            throw TransitServiceError.invalidAPIResponse(result.info)
        }

        guard let path = result.route?.paths?.first,
              let realDuration = Double(path.duration) else {
            throw TransitServiceError.missingRoute
        }

        let baseDuration = try baseDurationProvider()

        let trafficLevel = Self.trafficLevel(
            realDuration: realDuration,
            baseDuration: baseDuration
        )

        return CommuteResult(
            baseDuration: baseDuration,
            realDuration: realDuration,
            trafficLevel: trafficLevel
        )
    }

    private static func trafficLevel(
        realDuration: TimeInterval,
        baseDuration: TimeInterval
    ) -> TrafficLevel {
        guard baseDuration > 0 else {
            return .unknown
        }

        let ratio = realDuration / baseDuration
        if ratio < 1.1 {
            return .smooth
        } else if ratio < 1.5 {
            return .slow
        } else {
            return .congested
        }
    }
}

// MARK: - 坐标转换工具

private struct CoordinateTransformer {
    private static let a: Double = 6378245.0
    private static let ee: Double = 0.00669342162296594323

    static func transformToGCJ(from coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else {
            return coordinate
        }

        let lat = coordinate.latitude - 35.0
        let lon = coordinate.longitude - 105.0

        var dLat = transformLat(lat - 35.0, lon - 105.0)
        var dLon = transformLon(lat - 35.0, lon - 105.0)

        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }

    private static func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.longitude > 72.004 &&
            coordinate.longitude < 135.05 &&
            coordinate.latitude > 3.86 &&
            coordinate.latitude < 53.55
    }

    private static func transformLat(_ lat: Double, _ lon: Double) -> Double {
        var ret = -100.0 + 2.0 * lat + 3.0 * lon + 0.2 * lon * lon + 0.1 * lat * lon + 0.2 * sqrt(abs(lat))
        ret += (20.0 * sin(6.0 * .pi * lat) + 20.0 * sin(2.0 * .pi * lat)) * 2.0 / 3.0
        ret += (20.0 * sin(.pi * lon) + 40.0 * sin(.pi * lon / 3.0)) * 2.0 / 3.0
        ret += (160.0 * sin(.pi * lon / 12.0) + 320.0 * sin(.pi * lon / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ lat: Double, _ lon: Double) -> Double {
        var ret = 300.0 + lat + 2.0 * lon + 0.1 * lat * lat + 0.1 * lat * lon + 0.1 * sqrt(abs(lat))
        ret += (20.0 * sin(6.0 * .pi * lat) + 20.0 * sin(2.0 * .pi * lat)) * 2.0 / 3.0
        ret += (20.0 * sin(.pi * lat) + 40.0 * sin(.pi * lat / 3.0)) * 2.0 / 3.0
        ret += (150.0 * sin(.pi * lat / 12.0) + 300.0 * sin(.pi * lat / 30.0)) * 2.0 / 3.0
        return ret
    }
}
