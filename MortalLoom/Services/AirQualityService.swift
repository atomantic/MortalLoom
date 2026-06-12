import Foundation
import CoreLocation

// Privacy note: AirQualityService makes a single HTTPS request to Open-Meteo's
// public Air Quality API (no account, no API key, no tracking cookies). The
// request includes only a rounded coordinate (0.01° precision ≈ 1 km) and
// returns a US AQI value that is mapped to MortalLoom's AirQualityLevel bucket.
// The rounded coordinate is never persisted locally after the call returns.

enum AirQualityService {

    /// Coordinate precision used when calling the remote API. Rounding to 2
    /// decimal places (~1 km) keeps the request coarse enough that the remote
    /// server cannot triangulate a user's address, while still returning the
    /// correct local AQI reading.
    private static let coordinateRoundingPrecision: Double = 100 // => 1 / 0.01

    struct Reading: Sendable, Equatable {
        let usAQI: Int
        let pm25: Double
        let level: AirQualityLevel
    }

    /// Fetch a single AQI reading for the given coordinate.
    /// Returns nil on any network error, malformed response, or timeout —
    /// callers should gracefully fall back to manual selection.
    static func fetch(coordinate: CLLocationCoordinate2D) async -> Reading? {
        let lat = (coordinate.latitude * coordinateRoundingPrecision).rounded() / coordinateRoundingPrecision
        let lon = (coordinate.longitude * coordinateRoundingPrecision).rounded() / coordinateRoundingPrecision

        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        struct Response: Decodable {
            struct Current: Decodable {
                let us_aqi: Double?
                let pm2_5: Double?
            }
            let current: Current?
        }

        guard let parsed = try? JSONDecoder().decode(Response.self, from: data),
              let current = parsed.current,
              let aqi = current.us_aqi else { return nil }

        return Reading(
            usAQI: Int(aqi),
            pm25: current.pm2_5 ?? 0,
            level: level(forUSAQI: Int(aqi))
        )
    }

    /// Map a US EPA AQI value to MortalLoom's AirQualityLevel bucket.
    /// US AQI bands: 0–50 Good, 51–100 Moderate, 101–150 Unhealthy for
    /// Sensitive Groups, 151–200 Unhealthy, 201–300 Very Unhealthy, 301+
    /// Hazardous. We collapse 101–200 into our single `unhealthy` bucket
    /// and 201+ into `hazardous` to match the app's 4-step scale.
    static func level(forUSAQI aqi: Int) -> AirQualityLevel {
        switch aqi {
        case ..<0:    return .moderate
        case 0...50:  return .good
        case 51...100: return .moderate
        case 101...200: return .unhealthy
        default:       return .hazardous
        }
    }
}
