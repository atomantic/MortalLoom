import Foundation
import CoreLocation

// Privacy note: LocationService requests a single coarse location fix (country-level accuracy),
// reverse-geocodes it to an ISO country code on-device via Apple's geocoder,
// and discards the coordinates. No location data ever leaves the device.

@Observable @MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    enum Status: Equatable {
        case idle
        case requesting      // waiting for permission
        case detecting       // got permission, waiting for location fix
        case done
        case denied
        case failed(String)
    }

    var status: Status = .idle
    var detectedCountryCode: String?

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func detect() async {
        let authStatus = manager.authorizationStatus
        switch authStatus {
        case .denied, .restricted:
            status = .denied
            return
        case .notDetermined:
            status = .requesting
            manager.requestWhenInUseAuthorization()
            // delegate will call requestLocationAndGeocode() when authorized
            return
        default:
            break
        }
        // Already authorized
        await requestLocationAndGeocode()
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(iOS)
        return status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        return status == .authorized
        #endif
    }

    private func requestLocationAndGeocode() async {
        status = .detecting
        let loc = await withCheckedContinuation { c in
            self.locationContinuation = c
            self.manager.requestLocation()
        }
        guard let loc else {
            status = .failed("Could not determine location")
            return
        }
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
           let code = placemarks.first?.isoCountryCode {
            detectedCountryCode = code
            status = .done
        } else {
            status = .failed("Could not determine country")
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.first)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            guard status == .requesting else { return }
            if isAuthorized(s) {
                await requestLocationAndGeocode()
            } else if s == .denied || s == .restricted {
                status = .denied
            }
        }
    }
}
