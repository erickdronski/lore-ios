import CoreLocation
import CoreMotion
import Foundation
import Observation

/// GPS + compass + gravity source for the coarse scanner (docs/05 §5, rung 2).
///
/// Publishes location, true heading, their accuracy figures, and the camera's
/// pitch every update. The accuracy numbers aren't decoration, they drive the
/// honesty contract: ±10–30 m position and ±10–25° heading in an urban canyon
/// is exactly why this mode renders *directional labels*, never on-building
/// claims (docs/05 §4.2 refuse-to-guess threshold). Pitch (from CoreMotion's
/// gravity vector) feeds the ground/sky gates ported from the scanner lab
/// (lore-expo docs/SCANNER-FUSION.md): a camera aimed at the ground must not
/// claim a skyline lock.
@Observable
final class LocationHeadingProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let motion = CMMotionManager()

    private(set) var location: CLLocation?
    /// Degrees clockwise from true north; -1 while unknown.
    private(set) var headingDegrees: Double = -1
    /// Compass accuracy in degrees; negative = invalid.
    private(set) var headingAccuracy: Double = -1
    /// Elevation of the back camera's optical axis above the horizon, degrees:
    /// 0 = level, +90 = straight up, -90 = at the ground. `nil` until motion
    /// data arrives (or on devices without motion sensors).
    private(set) var cameraPitchDeg: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Called when location permission is denied/restricted, so the scanner can
    /// show a Settings path instead of silently never finding a fix.
    var onPermissionDenied: (() -> Void)?

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    var hasFix: Bool { location != nil && headingDegrees >= 0 }

    /// Human-readable status for the StatusChip (localized chrome).
    var statusLine: String {
        if !isAuthorized { return L10n.t("scan.permissionNeeded") }
        guard let location else { return L10n.t("scan.findingBlock") }
        let radius = max(1, Int(location.horizontalAccuracy.rounded()))
        if headingDegrees < 0 { return "±\(radius) m · \(L10n.t("scan.findingNorth"))" }
        return "\(L10n.t("scan.coarseMode")) · ±\(radius) m"
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 2 // degrees between callbacks, cheap smoothing
    }

    func start() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            onPermissionDenied?()
        default:
            break
        }
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        startMotion()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        cameraPitchDeg = nil
    }

    /// Gravity → camera pitch, low-passed. CMDeviceMotion.gravity is in G
    /// units, iOS convention: flat screen-up reads z ≈ -1 (camera straight
    /// down), upright portrait reads y ≈ -1 (camera at the horizon).
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            let horizontal = (gravity.x * gravity.x + gravity.y * gravity.y).squareRoot()
            let raw = atan2(gravity.z, horizontal) * 180 / .pi
            if let previous = self.cameraPitchDeg {
                self.cameraPitchDeg = previous + 0.25 * (raw - previous)
            } else {
                self.cameraPitchDeg = raw
            }
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        case .denied, .restricted:
            onPermissionDenied?()
        default:
            break
        }
    }

    /// Let iOS present the figure-8 calibration when the compass is unreliable.
    /// The whole coarse scanner depends on a trustworthy heading, so without
    /// this an uncalibrated magnetometer can never be recovered in-app.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Reject stale or low-quality fixes: a cached last-known location
        // delivered on start would otherwise drive confident bearing chips as if
        // it were the user's current position.
        guard let fix = locations.last else { return }
        let age = -fix.timestamp.timeIntervalSinceNow
        guard age < 12, fix.horizontalAccuracy > 0, fix.horizontalAccuracy < 100 else { return }
        location = fix
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
