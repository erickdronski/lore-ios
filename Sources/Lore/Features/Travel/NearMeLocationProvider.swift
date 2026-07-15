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
        authorizationStatus = manager.authorizationStatus
        // The shelf shows literal distance labels ("60 m away"), which users
        // read as a promise, so this asks for a genuinely accurate fix
        // (ten-meter class). The old hundred-meter fix could put a place 100 m
        // off its label, the exact "that's not 60 m away" complaint.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Update the labels live as the user walks (every ~10 m), not per block.
        manager.distanceFilter = 10
    }

    /// Request permission (if needed) and begin updates. Safe to call on the
    /// shelf's `.onAppear`; idempotent.
    func start(requestPermission: Bool = true) {
        authorizationStatus = manager.authorizationStatus
        if requestPermission && authorizationStatus == .notDetermined {
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
        guard let latest = locations.last else { return }
        // Reject any fix that would make the distance labels lie:
        //  - invalid or coarse accuracy (a fix worse than 65 m can't honestly
        //    back a "60 m away" label), and
        //  - a stale cached fix delivered on start (older than 30 s), which no
        //    longer reflects where the user is standing.
        // Better to keep showing "finding your block" than a wrong distance.
        guard latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= 65,
              abs(latest.timestamp.timeIntervalSinceNow) <= 30
        else { return }
        location = latest
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last known fix; the shelf degrades to whatever it had.
    }
}
