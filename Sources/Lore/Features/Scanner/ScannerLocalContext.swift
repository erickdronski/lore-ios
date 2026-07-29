import CoreLocation
import Foundation

/// The scanner describes the world around the device, not the city the map is
/// browsing. This value type keeps that contract testable without starting the
/// camera, Core Location delegates, or network work.
enum ScannerLocalContext: Equatable {
    case waitingForLocation
    case loadingCities
    case unavailable
    case outsideCoverage(nearest: City?, distanceM: CLLocationDistance?)
    case locked(City)

    var lockedCity: City? {
        if case .locked(let city) = self { return city }
        return nil
    }

    var isBlockingScanner: Bool {
        switch self {
        case .waitingForLocation, .loadingCities, .unavailable, .outsideCoverage:
            return true
        case .locked:
            return false
        }
    }
}

enum ScannerLocalContextResolver {
    /// Preflight radius for choosing the local city catalog. Projection still
    /// uses the tighter place-level bearing radius, so this never turns distant
    /// places into scanner claims.
    static let defaultCoverageRadiusM: CLLocationDistance = 75_000

    static func resolve(
        location: CLLocation?,
        cities: [City]?,
        maxCoverageDistanceM: CLLocationDistance = defaultCoverageRadiusM
    ) -> ScannerLocalContext {
        guard let location else { return .waitingForLocation }
        guard let cities else { return .loadingCities }
        guard let nearest = nearestCity(to: location, among: cities) else {
            return .unavailable
        }
        if nearest.distanceM <= maxCoverageDistanceM {
            return .locked(nearest.city)
        }
        return .outsideCoverage(nearest: nearest.city, distanceM: nearest.distanceM)
    }

    static func nearestCity(to location: CLLocation, among cities: [City]) -> ScannerResolvedCity? {
        cities
            .filter(\.isLive)
            .map { city in
                ScannerResolvedCity(
                    city: city,
                    distanceM: location.distance(from: city.location)
                )
            }
            .min { $0.distanceM < $1.distanceM }
    }
}

struct ScannerResolvedCity: Equatable {
    let city: City
    let distanceM: CLLocationDistance
}
