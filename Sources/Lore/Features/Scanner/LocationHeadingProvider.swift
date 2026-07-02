import CoreLocation
import Foundation
import Observation

/// GPS + compass source for the coarse scanner (docs/05 §5, rung 2).
///
/// Publishes location, true heading, and their accuracy figures every update.
/// The accuracy numbers aren't decoration — they drive the honesty contract:
/// ±10–30 m position and ±10–25° heading in an urban canyon is exactly why
/// this mode renders *directional labels*, never on-building claims
/// (docs/05 §4.2 refuse-to-guess threshold).
@Observable
final class LocationHeadingProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    /// Degrees clockwise from true north; -1 while unknown.
    private(set) var headingDegrees: Double = -1
    /// Compass accuracy in degrees; negative = invalid.
    private(set) var headingAccuracy: Double = -1
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    var hasFix: Bool { location != nil && headingDegrees >= 0 }

    /// Human-readable status for the StatusChip.
    var statusLine: String {
        if !isAuthorized { return "Location permission needed" }
        guard let location else { return "Finding your block…" }
        let radius = max(1, Int(location.horizontalAccuracy.rounded()))
        if headingDegrees < 0 { return "±\(radius) m · finding north…" }
        return "Coarse mode · ±\(radius) m"
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 2 // degrees between callbacks — cheap smoothing
    }

    func start() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        location = locations.last
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        // Prefer true heading (declination-corrected); fall back to magnetic.
        let value = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        headingDegrees = value
        headingAccuracy = newHeading.headingAccuracy
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last known fix; the scanner degrades honestly on staleness.
    }
}
