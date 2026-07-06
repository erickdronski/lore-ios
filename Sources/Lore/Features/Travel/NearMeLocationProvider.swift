import CoreLocation
import Foundation
import Observation

/// A lightweight, location-only CoreLocation source for the "Near me" shelf
/// (task requirement 4). Deliberately separate from the scanner's
/// `LocationHeadingProvider` (which also runs the compass): the map shelf only
/// needs position, so this asks for less and can run at a coarser cadence.
///
/// Publishes the latest fix and authorization status. It never blocks the shelf:
/// with no permission or no fix yet, the shelf shows its own empty/placeholder
/// state, location is an enhancement, not a gate (the map works from anywhere,
/// docs/10 §5).
@Observable
final class NearMeLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    /// True once we've been denied/restricted, the shelf uses this to show a
    /// "turn on location" affordance instead of an endless spinner.
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        // Hundred-meter accuracy is plenty to rank a near-you shelf and is
        // far cheaper than the scanner's best-accuracy fix.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Only re-rank when the user has actually moved a block.
        manager.distanceFilter = 25
    }

    /// Request permission (if needed) and begin updates. Safe to call on the
    /// shelf's `.onAppear`; idempotent.
    func start() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Keep the most recent, reasonably-accurate fix.
        if let latest = locations.last, latest.horizontalAccuracy >= 0 {
            location = latest
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last known fix; the shelf degrades to whatever it had.
    }
}
