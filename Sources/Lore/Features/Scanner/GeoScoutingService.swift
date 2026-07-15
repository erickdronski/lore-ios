import ARKit
import CoreLocation
import Foundation
import Observation

/// VPS coverage scouting for Lore's Apple precise-mode release path.
///
/// ARKit's own geo tracking
/// (`ARGeoTrackingConfiguration.checkAvailability(at:)`) answers "does Apple
/// have VPS-class coverage here?", a free, on-device-initiated probe that
/// feeds the degraded-modes ladder before the user starts precise mode.
///
/// A future ARCore Geospatial backend can add Streetscape occlusion and broader
/// coverage behind the existing `VPSProvider` seam. It is not required for the
/// current Apple ARGeoTracking implementation to function or ship. Add
/// `ARCore/Geospatial` (SPM/CocoaPods,
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
    private var activeRequestID = UUID()

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
        let requestID = UUID()
        activeRequestID = requestID
        guard ARGeoTrackingConfiguration.isSupported else {
            availability = .unsupported
            return
        }
        availability = .checking
        ARGeoTrackingConfiguration.checkAvailability(at: coordinate) { available, _ in
            Task { @MainActor [weak self] in
                guard self?.activeRequestID == requestID else { return }
                self?.availability = available ? .available : .unavailable
            }
        }
    }
}
