import ARKit
import CoreLocation
import Foundation
import Observation

/// VPS scouting stub, the dual-VPS doctrine hook (docs/05 §2.1 + open Q1).
///
/// The production localization stack is **ARCore Geospatial** (`GARSession`:
/// VPS pose ~1 m / 1–2° + Streetscape Geometry), which is an external SDK and
/// therefore out of this dependency-free P0 scaffold. What we *can* do today
/// with pure Apple frameworks is scout: ARKit's own geo tracking
/// (`ARGeoTrackingConfiguration.checkAvailability(at:)`) answers "does Apple
/// have VPS-class coverage here?", a free, on-device-initiated probe that
/// feeds the degraded-modes ladder (docs/05 §5) and the on-foot coverage
/// survey (docs/05 open Q2) before the ARCore dependency lands.
///
/// TODO(P1): ARCore Geospatial, add `ARCore/Geospatial` (SPM/CocoaPods,
/// pin ≥ 1.45 per docs/05 §2.1), create the `GARSession` alongside ARKit,
/// feed each `ARFrame` via `session.update(_:)`, and gate exact-pin UI on
/// `horizontalAccuracy < 5 m && orientationYawAccuracy < 5°`. This service
/// then becomes the tier selector: Full VPS → coarse → map-only.
@Observable
@MainActor
final class GeoScoutingService {
    enum Availability {
        case unknown
        case checking
        /// Apple geo tracking (and very likely Google VPS) covers this spot.
        case available
        /// No coverage, the scanner stays in coarse mode here.
        case unavailable
        /// Device can't run geo tracking at all (rung 4, docs/05 §5).
        case unsupported
    }

    private(set) var availability: Availability = .unknown

    var statusSuffix: String {
        switch availability {
        case .unknown, .checking: return ""
        case .available: return " · VPS coverage here"
        case .unavailable: return " · no VPS coverage"
        case .unsupported: return ""
        }
    }

    /// Probes geo-tracking availability at a coordinate. Safe to call on
    /// every significant location change; results are per-area, not per-fix.
    func scout(coordinate: CLLocationCoordinate2D) {
        guard ARGeoTrackingConfiguration.isSupported else {
            availability = .unsupported
            return
        }
        availability = .checking
        ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { available, _ in
            Task { @MainActor [weak self] in
                self?.availability = available ? .available : .unavailable
            }
        }
    }
}
