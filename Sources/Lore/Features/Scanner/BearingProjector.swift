import CoreLocation
import Foundation

/// Pure bearing math for the coarse scanner, no I/O, no frameworks beyond
/// CoreLocation value types, fully unit-testable (the same doctrine as the
/// P1 `Resolver`: docs/03 §2).
enum BearingProjector {
    /// Forward azimuth from `origin` to `target`, degrees clockwise from
    /// true north in `[0, 360)`. Great-circle initial bearing.
    static func bearing(
        from origin: CLLocationCoordinate2D,
        to target: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let deltaLon = (target.longitude - origin.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed smallest angular difference `a - b`, normalized to (-180, 180].
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }

    /// Maps a bearing delta (place bearing − device heading) to a horizontal
    /// screen fraction: 0 = left edge, 0.5 = center, 1 = right edge, for a
    /// camera with `fovDegrees` horizontal field of view. Values outside
    /// [0, 1] mean the target is off-screen in that direction.
    static func screenFraction(delta: Double, fovDegrees: Double) -> Double {
        0.5 + delta / fovDegrees
    }

    /// "600 m" / "1.2 km" formatting for chip distance captions.
    static func distanceLabel(meters: Double) -> String {
        if meters < 950 {
            return "\(Int((meters / 10).rounded() * 10)) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }

    /// Compass arrow glyph for a bearing delta, used on the off-screen edge
    /// chips ("Willis Tower ↖ 600 m" style, docs/05 §5 rung 2).
    static func arrowGlyph(delta: Double) -> String {
        switch delta {
        case -22.5..<22.5: return "↑"
        case 22.5..<67.5: return "↗"
        case 67.5..<112.5: return "→"
        case 112.5..<157.5: return "↘"
        case -67.5..<(-22.5): return "↖"
        case -112.5..<(-67.5): return "←"
        case -157.5..<(-112.5): return "↙"
        default: return "↓"
        }
    }
}

/// One place projected against the current pose.
struct ProjectedPlace: Identifiable {
    let place: Place
    /// Bearing from the user to the place, degrees from true north.
    let bearing: Double
    /// Signed delta vs. device heading, (-180, 180].
    let delta: Double
    /// Ground distance, meters.
    let distance: Double
    /// Horizontal screen fraction (see `BearingProjector.screenFraction`).
    let screenFraction: Double
    /// Whether the place is inside the camera's horizontal FOV.
    let isInView: Bool

    var id: String { place.id }
    var distanceLabel: String { BearingProjector.distanceLabel(meters: distance) }
    var arrow: String { BearingProjector.arrowGlyph(delta: delta) }
}

extension BearingProjector {
    /// Projects `places` against the current fix + heading: filters to
    /// `maxDistance`, computes bearings/deltas, sorts nearest-first.
    static func project(
        places: [Place],
        from location: CLLocation,
        heading: Double,
        fovDegrees: Double,
        maxDistance: Double = 2_500
    ) -> [ProjectedPlace] {
        places.compactMap { place -> ProjectedPlace? in
            let distance = location.distance(from: place.location)
            guard distance <= maxDistance, distance > 5 else { return nil }
            let bearing = bearing(
                from: location.coordinate,
                to: place.coordinate
            )
            let delta = angleDelta(bearing, heading)
            let fraction = screenFraction(delta: delta, fovDegrees: fovDegrees)
            return ProjectedPlace(
                place: place,
                bearing: bearing,
                delta: delta,
                distance: distance,
                screenFraction: fraction,
                isInView: abs(delta) <= fovDegrees / 2
            )
        }
        .sorted { $0.distance < $1.distance }
    }
}
