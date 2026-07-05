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
    let transits: [AMapTransitPath]?
}

struct AMapPath: Codable {
    /// 持续时间，单位：秒。
    let duration: String

    /// 距离，单位：米。
    let distance: String
}

struct AMapTransitPath: Codable {
    let duration: String
    let walkingDistance: String?
    let distance: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case walkingDistance = "walking_distance"
        case distance
    }
}

struct AMapBicyclingResponse: Codable {
    let errcode: Int?
    let errmsg: String?
    let data: AMapBicyclingData?
}

struct AMapBicyclingData: Codable {
    let paths: [AMapPath]?
}

struct AMapGeocodeResponse: Codable {
    let status: String
    let info: String
    let geocodes: [AMapGeocode]?
}

struct AMapGeocode: Codable {
    /// 高德返回格式为 "longitude,latitude"，坐标系为 GCJ-02。
    let location: String
    let formattedAddress: String?

    enum CodingKeys: String, CodingKey {
        case location
        case formattedAddress = "formatted_address"
    }
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

    /// 高德返回路线距离，单位：米。
    let distanceMeters: Double?

    let trafficLevel: TrafficLevel
}

enum TransitServiceError: LocalizedError {
    case missingAPIKey
    case missingBaseDuration
    case missingRoute
    case missingGeocodeResult
    case missingTransitCity
    case invalidAPIResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AMap API Key is missing."
        case .missingBaseDuration:
            return "Base commute duration is missing."
        case .missingRoute:
            return "AMap did not return a usable route."
        case .missingGeocodeResult:
            return "AMap did not return a usable geocode result."
        case .missingTransitCity:
            return "Transit mode requires a city for AMap transit API."
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

        let metrics = try await fetchRouteMetrics(
            mode: .driving,
            amapStart: amapStart,
            amapEnd: amapEnd,
            city: nil
        )

        let baseDuration = try baseDurationProvider()

        let trafficLevel = Self.trafficLevel(
            realDuration: metrics.duration,
            baseDuration: baseDuration
        )

        return CommuteResult(
            baseDuration: baseDuration,
            realDuration: metrics.duration,
            distanceMeters: metrics.distance,
            trafficLevel: trafficLevel
        )
    }

    /// 根据已保存的通勤路线计算实时通勤。
    ///
    /// 如果路线来自高德地理编码，坐标已经是 GCJ-02，不会再次偏移。
    func calculateCommute(route: CommuteRoute) async throws -> CommuteResult {
        guard !apiKey.contains("YOUR_") else {
            throw TransitServiceError.missingAPIKey
        }

        let start = route.startCoordinate
        let end = route.endCoordinate
        let amapStart: CLLocationCoordinate2D
        let amapEnd: CLLocationCoordinate2D

        if route.coordinateSystem == "gcj02" {
            amapStart = start
            amapEnd = end
        } else {
            amapStart = CoordinateTransformer.transformToGCJ(from: start)
            amapEnd = CoordinateTransformer.transformToGCJ(from: end)
        }

        let metrics = try await fetchRouteMetrics(
            mode: route.effectiveMode,
            amapStart: amapStart,
            amapEnd: amapEnd,
            city: route.city
        )

        let trafficLevel = Self.trafficLevel(
            realDuration: metrics.duration,
            baseDuration: route.baseDurationSeconds
        )

        return CommuteResult(
            baseDuration: route.baseDurationSeconds,
            realDuration: metrics.duration,
            distanceMeters: metrics.distance ?? route.baseDistanceMeters,
            trafficLevel: trafficLevel
        )
    }

    /// 将用户输入的出发地/目的地同步到高德地图 API。
    ///
    /// 成功后返回可保存的通勤路线，包含：
    /// - 高德解析出的真实坐标。
    /// - 首次路线规划得到的基础通勤时长。
    ///
    /// 不使用默认地址，不伪造路线。
    func syncCommuteRoute(
        startAddress: String,
        endAddress: String,
        mode: CommuteMode,
        city: String?
    ) async throws -> CommuteRoute {
        guard !apiKey.contains("YOUR_") else {
            throw TransitServiceError.missingAPIKey
        }

        let start = try await geocode(address: startAddress)
        let end = try await geocode(address: endAddress)
        let metrics = try await fetchRouteMetrics(
            mode: mode,
            amapStart: start.coordinate,
            amapEnd: end.coordinate,
            city: city
        )

        return CommuteRoute(
            startName: start.name,
            startLatitude: start.coordinate.latitude,
            startLongitude: start.coordinate.longitude,
            endName: end.name,
            endLatitude: end.coordinate.latitude,
            endLongitude: end.coordinate.longitude,
            mode: mode,
            city: city,
            baseDurationSeconds: metrics.duration,
            baseDistanceMeters: metrics.distance,
            coordinateSystem: "gcj02"
        )
    }

    private func geocode(address: String) async throws -> (name: String, coordinate: CLLocationCoordinate2D) {
        var components = URLComponents(string: "https://restapi.amap.com/v3/geocode/geo")
        components?.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(AMapGeocodeResponse.self, from: data)
        guard result.status == "1" else {
            throw TransitServiceError.invalidAPIResponse(result.info)
        }

        guard let geocode = result.geocodes?.first,
              let coordinate = Self.parseAMapCoordinate(geocode.location) else {
            throw TransitServiceError.missingGeocodeResult
        }

        return (geocode.formattedAddress ?? address, coordinate)
    }

    private struct RouteMetrics {
        let duration: TimeInterval
        let distance: Double?
    }

    private func fetchRouteMetrics(
        mode: CommuteMode,
        amapStart: CLLocationCoordinate2D,
        amapEnd: CLLocationCoordinate2D,
        city: String?
    ) async throws -> RouteMetrics {
        switch mode {
        case .driving:
            return try await fetchV3PathMetrics(
                endpoint: "https://restapi.amap.com/v3/direction/driving",
                amapStart: amapStart,
                amapEnd: amapEnd,
                extraQueryItems: [
                    URLQueryItem(name: "extensions", value: "base"),
                    URLQueryItem(name: "strategy", value: "0")
                ]
            )
        case .walking:
            return try await fetchV3PathMetrics(
                endpoint: "https://restapi.amap.com/v3/direction/walking",
                amapStart: amapStart,
                amapEnd: amapEnd,
                extraQueryItems: []
            )
        case .bicycling:
            return try await fetchBicyclingMetrics(
                amapStart: amapStart,
                amapEnd: amapEnd
            )
        case .transit:
            guard let city,
                  !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TransitServiceError.missingTransitCity
            }

            return try await fetchTransitMetrics(
                amapStart: amapStart,
                amapEnd: amapEnd,
                city: city
            )
        }
    }

    private func fetchV3PathMetrics(
        endpoint: String,
        amapStart: CLLocationCoordinate2D,
        amapEnd: CLLocationCoordinate2D,
        extraQueryItems: [URLQueryItem]
    ) async throws -> RouteMetrics {
        let origin = "\(amapStart.longitude),\(amapStart.latitude)"
        let destination = "\(amapEnd.longitude),\(amapEnd.latitude)"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "key", value: apiKey)
        ] + extraQueryItems

        guard let url = components?.url else {
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
              let duration = Double(path.duration) else {
            throw TransitServiceError.missingRoute
        }

        return RouteMetrics(duration: duration, distance: Double(path.distance))
    }

    private func fetchTransitMetrics(
        amapStart: CLLocationCoordinate2D,
        amapEnd: CLLocationCoordinate2D,
        city: String
    ) async throws -> RouteMetrics {
        let origin = "\(amapStart.longitude),\(amapStart.latitude)"
        let destination = "\(amapEnd.longitude),\(amapEnd.latitude)"
        var components = URLComponents(string: "https://restapi.amap.com/v3/direction/transit/integrated")
        components?.queryItems = [
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
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

        guard let transit = result.route?.transits?.first,
              let duration = Double(transit.duration) else {
            throw TransitServiceError.missingRoute
        }

        let distance = Double(transit.distance ?? "") ?? Double(transit.walkingDistance ?? "")
        return RouteMetrics(duration: duration, distance: distance)
    }

    private func fetchBicyclingMetrics(
        amapStart: CLLocationCoordinate2D,
        amapEnd: CLLocationCoordinate2D
    ) async throws -> RouteMetrics {
        let origin = "\(amapStart.longitude),\(amapStart.latitude)"
        let destination = "\(amapEnd.longitude),\(amapEnd.latitude)"
        var components = URLComponents(string: "https://restapi.amap.com/v4/direction/bicycling")
        components?.queryItems = [
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(AMapBicyclingResponse.self, from: data)
        guard result.errcode == nil || result.errcode == 0 else {
            throw TransitServiceError.invalidAPIResponse(result.errmsg ?? "AMap bicycling API failed.")
        }

        guard let path = result.data?.paths?.first,
              let duration = Double(path.duration) else {
            throw TransitServiceError.missingRoute
        }

        return RouteMetrics(duration: duration, distance: Double(path.distance))
    }

    private static func parseAMapCoordinate(_ location: String) -> CLLocationCoordinate2D? {
        let parts = location.split(separator: ",").compactMap { Double(String($0)) }
        guard parts.count == 2 else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: parts[1], longitude: parts[0])
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
