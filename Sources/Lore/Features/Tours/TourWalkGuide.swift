import CoreLocation
import Foundation
import Observation

/// The hands-free walking-tour guide: watches the walker's live position and
/// fires an arrival when they reach the current target stop, so the tour can
/// auto-advance and speak the stop's story without touching the phone.
///
/// Honesty contract (same doctrine as `NearMeLocationProvider`): a fix only
/// counts when it is fresh and ten-meter class; `distanceToTarget` is nil until
/// a trustworthy fix exists, so the UI never shows a distance it can't back.
/// Arrivals fire once per target (re-armed only when the target changes), so a
/// GPS wobble at the threshold can't re-trigger the same stop.
///
/// Deliberately foreground-only for v1: the walker has the tour open while
/// walking (like following a map). No background-location entitlement, no
/// Always permission — When-In-Use, which onboarding already requests.
@MainActor
@Observable
final class TourWalkGuide: NSObject, CLLocationManagerDelegate {
    /// Arrival radius in meters. Urban GPS is honestly ±10–30 m; 35 m means
    /// "standing in front of it" without demanding a perfect fix.
    static let arrivalRadius: CLLocationDistance = 35

    private let manager = CLLocationManager()

    /// True while the guide is running (user toggled auto-play on).
    private(set) var isGuiding = false
    /// Live distance to the current target stop, nil until a trustworthy fix.
    private(set) var distanceToTarget: CLLocationDistance?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Fired once when the walker reaches the current target (main actor).
    var onArrive: ((Int) -> Void)?

    private var targetIndex: Int?
    private var targetCoordinate: CLLocationCoordinate2D?
    /// Re-armed when the target changes; blocks duplicate arrivals per target.
    private var hasArrivedAtTarget = false
    private var lastGoodFix: CLLocation?

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override init() {
        super.init()
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
        // Ten-meter class, updating every ~5 m: tight enough to catch a 35 m
        // arrival ring reliably at walking speed.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
        manager.activityType = .fitness
    }

    /// Begin guiding. Safe to call repeatedly; requests When-In-Use on first use.
    func start() {
        authorizationStatus = manager.authorizationStatus
        guard !isDenied else {
            isGuiding = false
            return
        }
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        isGuiding = true
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    /// Stop guiding and clear state so a re-open starts clean.
    func stop() {
        isGuiding = false
        manager.stopUpdatingLocation()
        distanceToTarget = nil
        targetIndex = nil
        targetCoordinate = nil
        hasArrivedAtTarget = false
        lastGoodFix = nil
    }

    /// Aim the guide at a stop. Passing a new index re-arms arrival; passing
    /// the same index keeps the armed/fired state (so a narration replay or a
    /// view refresh can't re-fire the stop the walker is standing at).
    func setTarget(index: Int, coordinate: CLLocationCoordinate2D?) {
        if targetIndex != index {
            hasArrivedAtTarget = false
        }
        targetIndex = index
        targetCoordinate = coordinate
        recomputeDistance()
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isGuiding && self.isAuthorized {
                self.manager.startUpdatingLocation()
            } else if self.isDenied {
                self.isGuiding = false
                self.manager.stopUpdatingLocation()
                self.distanceToTarget = nil
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.ingest(latest)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Keep the last good fix; the distance label degrades to stale-then-nil
        // rather than inventing movement.
    }

    // MARK: Fix handling

    private func ingest(_ fix: CLLocation) {
        // Same honesty gate as the near-me shelf: no coarse or stale fixes.
        guard fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 65,
              abs(fix.timestamp.timeIntervalSinceNow) <= 30
        else { return }
        lastGoodFix = fix
        recomputeDistance()

        guard isGuiding,
              !hasArrivedAtTarget,
              let targetIndex,
              let distance = distanceToTarget,
              distance <= Self.arrivalRadius
        else { return }
        hasArrivedAtTarget = true
        onArrive?(targetIndex)
    }

    private func recomputeDistance() {
        guard let fix = lastGoodFix, let coordinate = targetCoordinate else {
            distanceToTarget = nil
            return
        }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        distanceToTarget = fix.distance(from: target)
    }
}
