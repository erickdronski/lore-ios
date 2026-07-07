import CoreLocation
import Foundation

/// The "1 Hour In ___" generator (strategy synth, Phase 2 "the revenue no-brainer"):
/// an auto-routed, time-boxed walk stitched from the places we already have, so
/// it works in every city on day one. Greedy nearest-neighbour from the start
/// point, budgeted by walking time + a dwell per stop, capped for a clean walk.
enum OneHourTour {
    /// Strolling pace, meters per minute (~4.5 km/h, an unhurried tourist).
    private static let metersPerMinute = 75.0
    /// Minutes spent standing at each stop reading + looking up.
    private static let dwellMinutes = 6.0
    /// Never route more than this many stops into one walk.
    private static let maxStops = 8

    /// Build a `Tour` for `city` from `places`, starting at `origin` (the user's
    /// location when known, else the densest centre of the set). Returns nil if
    /// there aren't at least two reachable stops within the budget.
    static func generate(
        city: String,
        places: [Place],
        from origin: CLLocationCoordinate2D?,
        durationMin: Int = 60
    ) -> Tour? {
        guard places.count >= 2 else { return nil }

        var pool = places
        var start = origin ?? centroid(of: places)
        // Anchor the walk on a real place near the start so the first leg is short.
        if origin == nil, let anchor = pool.min(by: { distance(start, $0.coordinate) < distance(start, $1.coordinate) }) {
            start = anchor.coordinate
        }

        var ordered: [Place] = []
        var remaining = Double(durationMin)
        var current = start

        while !pool.isEmpty && ordered.count < maxStops {
            guard let next = pool.min(by: {
                distance(current, $0.coordinate) < distance(current, $1.coordinate)
            }) else { break }
            let legMeters = distance(current, next.coordinate)
            let cost = legMeters / metersPerMinute + dwellMinutes
            // Always take the first stop; after that, respect the time budget.
            if !ordered.isEmpty && cost > remaining { break }
            ordered.append(next)
            remaining -= cost
            current = next.coordinate
            pool.removeAll { $0.id == next.id }
        }

        guard ordered.count >= 2 else { return nil }

        let tourID = "one-hour-\(city)"
        let stops = ordered.enumerated().map { index, place in
            TourStop(tourID: tourID, placeID: place.id, seq: index + 1, note: place.layer1?.hook)
        }
        let totalMeters = zip(ordered, ordered.dropFirst())
            .reduce(0.0) { $0 + distance($1.0.coordinate, $1.1.coordinate) }

        return Tour(
            id: tourID,
            slug: tourID,
            title: "1 Hour In \(cityLabel(city))",
            city: city,
            emoji: "⏱️",
            blurb: "A perfect hour on foot: \(ordered.count) storied stops, routed for you.",
            durationMin: durationMin,
            distanceKm: totalMeters / 1000,
            stops: stops
        )
    }

    // MARK: Geometry

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func centroid(of places: [Place]) -> CLLocationCoordinate2D {
        let count = Double(places.count)
        return CLLocationCoordinate2D(
            latitude: places.map(\.lat).reduce(0, +) / count,
            longitude: places.map(\.lng).reduce(0, +) / count
        )
    }

    private static func cityLabel(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
