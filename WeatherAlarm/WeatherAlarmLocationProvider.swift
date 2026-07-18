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
    private var authorizationTimeoutTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?

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
            locationTimeoutTask?.cancel()
            locationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled,
                      let self,
                      let continuation = self.locationContinuation else {
                    return
                }

                self.locationContinuation = nil
                self.locationTimeoutTask = nil
                continuation.resume(throwing: WeatherAlarmLocationProviderError.locationUnavailable)
            }
        }
    }

    private func ensureLocationAuthorization() async throws {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .notDetermined:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard authorizationContinuation == nil else {
                    continuation.resume(throwing: WeatherAlarmLocationProviderError.requestAlreadyRunning)
                    return
                }

                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
                authorizationTimeoutTask?.cancel()
                authorizationTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled,
                          let self,
                          let continuation = self.authorizationContinuation else {
                        return
                    }

                    self.authorizationContinuation = nil
                    self.authorizationTimeoutTask = nil
                    continuation.resume(throwing: WeatherAlarmLocationProviderError.locationUnavailable)
                }
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
                authorizationTimeoutTask?.cancel()
                authorizationTimeoutTask = nil
                continuation.resume(returning: ())
            case .denied, .restricted:
                authorizationContinuation = nil
                authorizationTimeoutTask?.cancel()
                authorizationTimeoutTask = nil
                continuation.resume(throwing: WeatherAlarmLocationProviderError.authorizationDenied)
            case .notDetermined:
                break
            @unknown default:
                authorizationContinuation = nil
                authorizationTimeoutTask?.cancel()
                authorizationTimeoutTask = nil
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
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil

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
            locationTimeoutTask?.cancel()
            locationTimeoutTask = nil
            continuation.resume(throwing: error)
        }
    }
}
