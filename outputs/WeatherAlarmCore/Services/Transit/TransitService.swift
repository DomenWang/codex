import CoreLocation
import Foundation
import MapKit

struct MapResolvedLocation {
    let name: String
    let coordinate: CLLocationCoordinate2D
}

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

    /// 当前 ETA 与同一时段历史 P80 中更保守的值，单位：秒。
    let plannedDuration: TimeInterval

    /// 路线距离，单位：米。
    let distanceMeters: Double?

    /// 公共交通方案中需要实际步行的距离，单位：米。
    let walkingDistanceMeters: Double?

    let trafficLevel: TrafficLevel
    let hasTrafficAwareETA: Bool
}

enum TransitServiceError: LocalizedError {
    case missingBaseDuration
    case missingRoute
    case missingGeocodeResult
    case invalidAPIResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseDuration:
            return "请先保存一次路线，再开启自动提前。"
        case .missingRoute:
            return "暂时没有找到可用路线，请换个地址试试。"
        case .missingGeocodeResult:
            return "没有找到这个地点，请输入更完整的地址。"
        case .invalidAPIResponse(let info):
            return info
        }
    }
}

/// Apple MapKit 通勤服务。
///
/// 地点解析使用 `MKLocalSearch`，路线预估使用 `MKDirections`，不再依赖第三方地图 Web API。
final class TransitService {
    private let baseDurationProvider: () throws -> TimeInterval
    private let historyStore: CommuteETAHistoryStore

    init(
        baseDurationProvider: @escaping () throws -> TimeInterval = {
            throw TransitServiceError.missingBaseDuration
        },
        historyStore: CommuteETAHistoryStore = CommuteETAHistoryStore()
    ) {
        self.baseDurationProvider = baseDurationProvider
        self.historyStore = historyStore
    }

    /// 计算两点之间的当前通勤时间。
    func calculateCommute(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) async throws -> CommuteResult {
        let metrics = try await routeMetrics(
            start: start,
            end: end,
            mode: .driving,
            departureDate: Date(),
            arrivalDate: nil
        )
        let baseDuration = try baseDurationProvider()

        return CommuteResult(
            baseDuration: baseDuration,
            realDuration: metrics.duration,
            plannedDuration: metrics.duration,
            distanceMeters: metrics.distance,
            walkingDistanceMeters: metrics.walkingDistance,
            trafficLevel: Self.trafficLevel(
                realDuration: metrics.duration,
                baseDuration: baseDuration
            ),
            hasTrafficAwareETA: metrics.hasTrafficAwareETA
        )
    }

    /// 根据已保存的通勤路线计算当前通勤。
    func calculateCommute(
        route: CommuteRoute,
        departureDate: Date = Date(),
        arrivalDate: Date? = nil
    ) async throws -> CommuteResult {
        let startCoordinate = Self.normalizedCoordinate(
            route.startCoordinate,
            coordinateSystem: route.coordinateSystem
        )
        let endCoordinate = Self.normalizedCoordinate(
            route.endCoordinate,
            coordinateSystem: route.coordinateSystem
        )
        let metrics = try await routeMetrics(
            start: startCoordinate,
            end: endCoordinate,
            mode: route.effectiveMode,
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
        let history = historyStore.statistics(for: route, departureDate: departureDate)
        let referenceDuration = history?.p50 ?? max(0, route.baseDurationSeconds)
        let effectiveReference = referenceDuration > 0 ? referenceDuration : metrics.duration
        let plannedDuration = max(metrics.duration, history?.p80 ?? metrics.duration)
        historyStore.record(metrics.duration, for: route, departureDate: departureDate)

        return CommuteResult(
            baseDuration: effectiveReference,
            realDuration: metrics.duration,
            plannedDuration: plannedDuration,
            distanceMeters: metrics.distance ?? route.baseDistanceMeters,
            walkingDistanceMeters: metrics.walkingDistance ?? route.baseWalkingDistanceMeters,
            trafficLevel: Self.trafficLevel(
                realDuration: metrics.duration,
                baseDuration: effectiveReference
            ),
            hasTrafficAwareETA: metrics.hasTrafficAwareETA
        )
    }

    /// 将用户输入的出发地/目的地同步为可保存的通勤路线。
    func syncCommuteRoute(
        startAddress: String,
        endAddress: String,
        mode: CommuteMode,
        city: String?
    ) async throws -> CommuteRoute {
        let start = try await resolveAddress(startAddress)
        let end = try await resolveAddress(endAddress)
        let metrics = try await routeMetrics(
            start: start.coordinate,
            end: end.coordinate,
            mode: mode,
            departureDate: Date(),
            arrivalDate: nil
        )

        return CommuteRoute(
            startName: startAddress,
            startLatitude: start.coordinate.latitude,
            startLongitude: start.coordinate.longitude,
            endName: endAddress,
            endLatitude: end.coordinate.latitude,
            endLongitude: end.coordinate.longitude,
            mode: mode,
            city: city,
            baseDurationSeconds: metrics.duration,
            baseDistanceMeters: metrics.distance,
            baseWalkingDistanceMeters: metrics.walkingDistance,
            coordinateSystem: "wgs84"
        )
    }

    func resolveAddress(_ address: String) async throws -> MapResolvedLocation {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TransitServiceError.missingGeocodeResult
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw TransitServiceError.missingGeocodeResult
        }

        return MapResolvedLocation(
            name: Self.displayName(for: item, fallback: trimmed),
            coordinate: item.location.coordinate
        )
    }

    private struct RouteMetrics {
        let duration: TimeInterval
        let distance: Double?
        let walkingDistance: Double?
        let hasTrafficAwareETA: Bool
    }

    private func routeMetrics(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        mode: CommuteMode,
        departureDate: Date?,
        arrivalDate: Date?
    ) async throws -> RouteMetrics {
        switch mode {
        case .driving:
            return try await mapKitRouteMetrics(
                start: start,
                end: end,
                transportType: .automobile,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
        case .walking:
            return try await mapKitRouteMetrics(
                start: start,
                end: end,
                transportType: .walking,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
        case .transit:
            return try await transitRouteMetrics(
                start: start,
                end: end,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
        case .bicycling:
            if let metrics = try? await mapKitRouteMetrics(
                start: start,
                end: end,
                transportType: .cycling,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            ) {
                return metrics
            }
            return try await bicyclingEstimate(
                start: start,
                end: end,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
        }
    }

    private func transitRouteMetrics(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        departureDate: Date?,
        arrivalDate: Date?
    ) async throws -> RouteMetrics {
        do {
            let metrics = try await mapKitRouteMetrics(
                start: start,
                end: end,
                transportType: .transit,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )

            return RouteMetrics(
                duration: metrics.duration,
                distance: metrics.distance,
                walkingDistance: metrics.walkingDistance ?? estimatedWalkingDistance(forTotalDistance: metrics.distance),
                hasTrafficAwareETA: metrics.hasTrafficAwareETA
            )
        } catch {
            return try await transitFallbackRouteMetrics(
                start: start,
                end: end,
                departureDate: departureDate,
                arrivalDate: arrivalDate
            )
        }
    }

    private func transitFallbackRouteMetrics(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        departureDate: Date?,
        arrivalDate: Date?
    ) async throws -> RouteMetrics {
        if let walkingMetrics = try? await mapKitRouteMetrics(
            start: start,
            end: end,
            transportType: .walking,
            departureDate: departureDate,
            arrivalDate: arrivalDate
        ) {
            let distance = walkingMetrics.distance
            let transitLikeDuration = estimatedTransitDuration(
                distanceMeters: distance,
                walkingDuration: walkingMetrics.duration
            )
            return RouteMetrics(
                duration: transitLikeDuration,
                distance: distance,
                walkingDistance: estimatedWalkingDistance(forTotalDistance: distance) ?? distance,
                hasTrafficAwareETA: false
            )
        }

        let straightLineDistance = CLLocation(
            latitude: start.latitude,
            longitude: start.longitude
        ).distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        guard straightLineDistance > 0 else {
            throw TransitServiceError.missingRoute
        }

        let estimatedDistance = straightLineDistance * 1.28
        return RouteMetrics(
            duration: estimatedTransitDuration(distanceMeters: estimatedDistance, walkingDuration: nil),
            distance: estimatedDistance,
            walkingDistance: estimatedWalkingDistance(forTotalDistance: estimatedDistance),
            hasTrafficAwareETA: false
        )
    }

    private func estimatedTransitDuration(
        distanceMeters: Double?,
        walkingDuration: TimeInterval?
    ) -> TimeInterval {
        guard let distanceMeters, distanceMeters > 0 else {
            return max(15 * 60, walkingDuration ?? 0)
        }

        let vehicleSeconds = distanceMeters / (18_000.0 / 3_600.0)
        let transferBufferSeconds = distanceMeters < 2_000 ? 8.0 * 60.0 : 14.0 * 60.0
        let estimatedSeconds = vehicleSeconds + transferBufferSeconds
        if let walkingDuration, walkingDuration > 0 {
            return max(10 * 60, min(walkingDuration, estimatedSeconds))
        }

        return max(10 * 60, estimatedSeconds)
    }

    private func bicyclingEstimate(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        departureDate: Date?,
        arrivalDate: Date?
    ) async throws -> RouteMetrics {
        async let walkingMetricsRequest = try? mapKitRouteMetrics(
            start: start,
            end: end,
            transportType: .walking,
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
        async let drivingMetricsRequest = try? mapKitRouteMetrics(
            start: start,
            end: end,
            transportType: .automobile,
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
        let (walkingMetrics, drivingMetrics) = await (walkingMetricsRequest, drivingMetricsRequest)
        let straightLineDistance = CLLocation(
            latitude: start.latitude,
            longitude: start.longitude
        ).distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))

        let estimatedDistance = max(walkingMetrics?.distance ?? 0, straightLineDistance * 1.18)
        let duration: TimeInterval
        if estimatedDistance <= 10_000,
           let drivingDuration = drivingMetrics?.duration {
            // 城区短途里，骑行可绕开堵点但仍受路口影响。以当前驾车 ETA 为锚点，
            // 同时用约 20km/h 的合理速度下限防止估时过于激进。
            let physicalLowerBound = estimatedDistance / (20_000.0 / 3_600.0)
            duration = max(60, max(physicalLowerBound, drivingDuration * 0.90) + 90)
        } else {
            duration = max(60, estimatedDistance / (15_000.0 / 3_600.0))
        }
        return RouteMetrics(
            duration: duration,
            distance: estimatedDistance,
            walkingDistance: nil,
            hasTrafficAwareETA: false
        )
    }

    private func mapKitRouteMetrics(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        transportType: MKDirectionsTransportType,
        departureDate: Date?,
        arrivalDate: Date?
    ) async throws -> RouteMetrics {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: start.latitude, longitude: start.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: end.latitude, longitude: end.longitude),
            address: nil
        )
        request.transportType = transportType
        request.requestsAlternateRoutes = false
        if let arrivalDate {
            request.arrivalDate = arrivalDate
        } else {
            request.departureDate = departureDate
        }

        do {
            let eta = try await MKDirections(request: request).calculateETA()
            let walkingDistance: Double?
            if transportType == .transit,
               let route = try? await MKDirections(request: request).calculate().routes.first {
                let stepDistance = route.steps
                    .filter { $0.transportType == .walking }
                    .reduce(0) { $0 + $1.distance }
                walkingDistance = stepDistance > 0 ? stepDistance : nil
            } else {
                walkingDistance = transportType == .walking ? eta.distance : nil
            }

            return RouteMetrics(
                duration: eta.expectedTravelTime,
                distance: eta.distance,
                walkingDistance: walkingDistance,
                hasTrafficAwareETA: true
            )
        } catch {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw TransitServiceError.missingRoute
            }
            let walkingDistance: Double?
            if transportType == .transit {
                let stepDistance = route.steps
                    .filter { $0.transportType == .walking }
                    .reduce(0) { $0 + $1.distance }
                walkingDistance = stepDistance > 0 ? stepDistance : nil
            } else {
                walkingDistance = transportType == .walking ? route.distance : nil
            }

            return RouteMetrics(
                duration: route.expectedTravelTime,
                distance: route.distance,
                walkingDistance: walkingDistance,
                hasTrafficAwareETA: false
            )
        }
    }

    private func estimatedWalkingDistance(forTotalDistance distance: Double?) -> Double? {
        guard let distance, distance > 0 else {
            return nil
        }

        return min(max(distance * 0.12, 120), 1_800)
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

    private static func displayName(for item: MKMapItem, fallback: String) -> String {
        let detail = item.addressRepresentations?.fullAddress(
            includingRegion: false,
            singleLine: true
        ) ?? item.address?.fullAddress ?? ""

        if let name = item.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return detail.isEmpty ? name : "\(name) \(detail)"
        }

        if !detail.isEmpty {
            return detail
        }

        return fallback
    }

    private static func normalizedCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        coordinateSystem: String?
    ) -> CLLocationCoordinate2D {
        guard coordinateSystem == "gcj02" else {
            return coordinate
        }

        return CoordinateNormalizer.approximateWGS84(fromGCJ02: coordinate)
    }
}

/// 每条路线、同类日期、30 分钟时段最多保存 16 个 ETA；不保存道路图，也不运行本地寻路。
final class CommuteETAHistoryStore {
    struct Statistics {
        let p50: TimeInterval
        let p80: TimeInterval
    }

    private struct Bucket: Codable {
        var minuteSamples: [UInt16]
        var updatedAt: Date
    }

    private enum Keys {
        static let buckets = "smartwake.commute_eta_history.v1"
    }

    private let userDefaults: UserDefaults
    private let calendar: Calendar

    init(userDefaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.userDefaults = userDefaults
        self.calendar = calendar
    }

    func statistics(for route: CommuteRoute, departureDate: Date) -> Statistics? {
        let samples = loadBuckets()[bucketKey(for: route, departureDate: departureDate)]?.minuteSamples ?? []
        guard samples.count >= 5 else {
            return nil
        }

        let sorted = samples.sorted()
        return Statistics(
            p50: percentile(0.50, in: sorted),
            p80: percentile(0.80, in: sorted)
        )
    }

    func record(_ duration: TimeInterval, for route: CommuteRoute, departureDate: Date) {
        guard duration.isFinite, duration > 0 else {
            return
        }

        let minutes = UInt16(clamping: Int(ceil(duration / 60)))
        var buckets = loadBuckets()
        let key = bucketKey(for: route, departureDate: departureDate)
        var bucket = buckets[key] ?? Bucket(minuteSamples: [], updatedAt: departureDate)
        bucket.minuteSamples.append(minutes)
        bucket.minuteSamples = Array(bucket.minuteSamples.suffix(16))
        bucket.updatedAt = Date()
        buckets[key] = bucket

        if buckets.count > 64 {
            for oldKey in buckets.sorted(by: { $0.value.updatedAt < $1.value.updatedAt })
                .prefix(buckets.count - 64)
                .map(\.key) {
                buckets.removeValue(forKey: oldKey)
            }
        }

        guard let data = try? JSONEncoder().encode(buckets) else {
            return
        }
        userDefaults.set(data, forKey: Keys.buckets)
    }

    private func loadBuckets() -> [String: Bucket] {
        guard let data = userDefaults.data(forKey: Keys.buckets),
              let buckets = try? JSONDecoder().decode([String: Bucket].self, from: data) else {
            return [:]
        }
        return buckets
    }

    private func percentile(_ value: Double, in sorted: [UInt16]) -> TimeInterval {
        let index = min(sorted.count - 1, max(0, Int(ceil(value * Double(sorted.count))) - 1))
        return TimeInterval(sorted[index]) * 60
    }

    private func bucketKey(for route: CommuteRoute, departureDate: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: departureDate)
        let halfHour = (components.hour ?? 0) * 2 + (components.minute ?? 0) / 30
        let dayType = calendar.isDateInWeekend(departureDate) ? "weekend" : "weekday"
        return String(
            format: "%.4f,%.4f>%.4f,%.4f|%@|%@|%d",
            route.startLatitude,
            route.startLongitude,
            route.endLatitude,
            route.endLongitude,
            route.effectiveMode.rawValue,
            dayType,
            halfHour
        )
    }
}

private struct CoordinateNormalizer {
    private static let a: Double = 6378245.0
    private static let ee: Double = 0.00669342162296594323

    static func approximateWGS84(fromGCJ02 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else {
            return coordinate
        }

        let transformed = transformToGCJ(from: coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude * 2 - transformed.latitude,
            longitude: coordinate.longitude * 2 - transformed.longitude
        )
    }

    private static func transformToGCJ(from coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let dLatInput = coordinate.longitude - 105.0
        let dLonInput = coordinate.latitude - 35.0
        var dLat = transformLat(dLatInput, dLonInput)
        var dLon = transformLon(dLatInput, dLonInput)
        let radLat = coordinate.latitude / 180.0 * .pi
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

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
