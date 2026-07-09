import Combine
import CoreLocation
import Foundation

enum WeatherAlarmLocationProviderError: LocalizedError {
    case authorizationDenied
    case locationUnavailable
    case requestAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Location permission was denied."
        case .locationUnavailable:
            return "Current location is unavailable."
        case .requestAlreadyRunning:
            return "A location request is already running."
        }
    }
}

@MainActor
final class WeatherAlarmLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestCurrentLocation() async throws -> CLLocation {
        try await ensureLocationAuthorization()

        return try await withCheckedThrowingContinuation { continuation in
            guard locationContinuation == nil else {
                continuation.resume(throwing: WeatherAlarmLocationProviderError.requestAlreadyRunning)
                return
            }

            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func ensureLocationAuthorization() async throws {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .notDetermined:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            throw WeatherAlarmLocationProviderError.authorizationDenied
        @unknown default:
            throw WeatherAlarmLocationProviderError.authorizationDenied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            guard let continuation = authorizationContinuation else {
                return
            }

            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                authorizationContinuation = nil
                continuation.resume(returning: ())
            case .denied, .restricted:
                authorizationContinuation = nil
                continuation.resume(throwing: WeatherAlarmLocationProviderError.authorizationDenied)
            case .notDetermined:
                break
            @unknown default:
                authorizationContinuation = nil
                continuation.resume(throwing: WeatherAlarmLocationProviderError.authorizationDenied)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation = locationContinuation else {
                return
            }

            locationContinuation = nil

            if let location = locations.last {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: WeatherAlarmLocationProviderError.locationUnavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else {
                return
            }

            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}
