import Foundation
import CoreLocation

// Privacy note: LocationService requests a single coarse location fix (country-level accuracy),
// reverse-geocodes it to an ISO country code + region on-device via Apple's geocoder,
// briefly uses the coordinate for air-quality lookup via AirQualityService (if requested),
// and then discards the coordinates. No location data is persisted or sent anywhere else.

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
    var detectedRegionCode: String?
    /// Coordinate from the most recent successful fix. Cleared by `clearCoordinate()`
    /// once callers have consumed it (e.g., after an air-quality lookup).
    /// We keep it only long enough for the one-shot lookup; it is never persisted.
    var lastCoordinate: CLLocationCoordinate2D?

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
        lastCoordinate = loc.coordinate
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(loc),
           let placemark = placemarks.first,
           let code = placemark.isoCountryCode {
            detectedCountryCode = code
            detectedRegionCode = regionCode(from: placemark, country: code)
            status = .done
        } else {
            status = .failed("Could not determine country")
        }
    }

    /// Discard the transient coordinate. Call this after any one-shot consumer
    /// (e.g., air-quality lookup) finishes so nothing lingers in memory.
    func clearCoordinate() {
        lastCoordinate = nil
    }

    /// Build an ISO 3166-2 region code (e.g. "US-CA") from a geocoded placemark.
    /// Apple returns `administrativeArea` as a state/province abbreviation in the
    /// US and a full name in some other locales (e.g. "England" for GB), so we
    /// try direct code-match first and fall back to reverse name lookup.
    private func regionCode(from placemark: CLPlacemark, country: String) -> String? {
        guard let area = placemark.administrativeArea else { return nil }
        let candidate = "\(country.uppercased())-\(area.uppercased())"
        if LocationEngine.regionDisplayName(candidate) != candidate { return candidate }
        return LocationEngine.regionCode(countryCode: country, administrativeAreaName: area)
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
