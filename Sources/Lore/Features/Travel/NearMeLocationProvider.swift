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
    private static let maximumFixAge: TimeInterval = 30
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 65

    private(set) var location: CLLocation?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    #if DEBUG
    private static var screenshotLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.8889, longitude: -87.6359),
            altitude: 180,
            horizontalAccuracy: 8,
            verticalAccuracy: 12,
            timestamp: Date()
        )
    }
    #endif

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
        #if DEBUG
        if ScreenshotSupport.isActive {
            authorizationStatus = .authorizedWhenInUse
            location = Self.screenshotLocation
            return
        }
        #endif
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
        lastError = nil
        #if DEBUG
        if ScreenshotSupport.isActive {
            authorizationStatus = .authorizedWhenInUse
            location = Self.screenshotLocation
            return
        }
        #endif
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

    /// A recent, accurate-enough location for action routing. A fix that was
    /// fresh when Core Location delivered it can age out while another tab is
    /// open, so consumers should prefer this over reading `location` directly.
    func freshLocation(now: Date = Date()) -> CLLocation? {
        guard let location, Self.isActionable(location, now: now) else { return nil }
        return location
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            lastError = nil
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
        guard Self.isActionable(latest) else { return }
        lastError = nil
        location = latest
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last known fix; the shelf degrades to whatever it had.
        guard location == nil else { return }
        if let locationError = error as? CLError, locationError.code == .denied {
            authorizationStatus = manager.authorizationStatus
        } else {
            lastError = "We couldn’t get a reliable location fix. You can retry or keep exploring the city map."
        }
    }

    private static func isActionable(_ location: CLLocation, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && age >= -1
            && age <= maximumFixAge
    }
}
