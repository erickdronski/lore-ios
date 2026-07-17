import CoreLocation
import Foundation
import Observation

/// The city has two faces, and Lore shows both: by day the map reads bright
/// and architectural; after sundown it turns dark and the night layer wakes —
/// ghost stories surface as markers, nightlife pins hold their glow, museums
/// sleep. Mode follows the real sun by default (civil solar calculation at the
/// user's location) and the user can pin day or night whenever they like — the
/// moon button cycles auto → day → night.
@MainActor
@Observable
final class DayNightStore {
    enum Override: String {
        case auto, day, night
    }

    private static let defaultsKey = "lore.dayNight.override"

    /// The user's pinned choice; `.auto` follows the sun.
    var override: Override {
        didSet {
            UserDefaults.standard.set(override.rawValue, forKey: Self.defaultsKey)
            refresh()
        }
    }

    /// The single truth every surface reads.
    private(set) var isNight: Bool = false

    /// Best-known position for the solar calculation; fed by the map's
    /// location provider when a fix exists. Without one, a clock fallback
    /// (19:00–06:00 local) keeps the feature honest-ish everywhere on earth.
    private var coordinate: CLLocationCoordinate2D?

    private var timer: Timer?

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        override = raw.flatMap(Override.init(rawValue:)) ?? .auto
        #if DEBUG
        // Screenshot/verification hook: force night on launch so the dark map
        // + ghost wisps can be captured deterministically via Simulator
        // (LORE_FORCE_NIGHT=1), no location or UI tap needed. DEBUG-only.
        if ProcessInfo.processInfo.environment["LORE_FORCE_NIGHT"] == "1" {
            override = .night
        }
        #endif
        refresh()
        // Minute-scale drift is plenty: sunset doesn't sneak up in seconds.
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Cycle the map-header control: auto → day → night → auto.
    func cycle() {
        switch override {
        case .auto: override = .day
        case .day: override = .night
        case .night: override = .auto
        }
    }

    /// Feed the latest location fix (map already has one; no extra sensors).
    func updateLocation(_ location: CLLocation?) {
        guard let location else { return }
        coordinate = location.coordinate
        refresh()
    }

    private func refresh() {
        switch override {
        case .day: isNight = false
        case .night: isNight = true
        case .auto: isNight = Self.isSunDown(at: coordinate, on: Date())
        }
    }

    // MARK: - Solar position (NOAA simplified)

    /// True when the sun is below the horizon at `coordinate` (or, with no
    /// fix, when the local clock reads 19:00–06:00 — a stated approximation,
    /// not a fake sunset).
    static func isSunDown(at coordinate: CLLocationCoordinate2D?, on date: Date) -> Bool {
        guard let coordinate else {
            let hour = Calendar.current.component(.hour, from: date)
            return hour >= 19 || hour < 6
        }
        // NOAA solar-elevation approximation, accurate to well under a degree,
        // more than enough to know whether it is night out.
        let cal = Calendar(identifier: .gregorian)
        let year = cal.component(.year, from: date)
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let daysInYear = Double(cal.range(of: .day, in: .year, for: date)?.count ?? 365)
        var utc = cal
        utc.timeZone = TimeZone(identifier: "UTC")!
        let hourUTC = Double(utc.component(.hour, from: date))
            + Double(utc.component(.minute, from: date)) / 60
        _ = year

        // Fractional year (radians).
        let gamma = 2 * Double.pi / daysInYear * (dayOfYear - 1 + (hourUTC - 12) / 24)
        // Solar declination (radians).
        let decl = 0.006918
            - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        // Equation of time (minutes).
        let eqTime = 229.18 * (0.000075
            + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        // True solar time (minutes) → hour angle (radians).
        let timeOffset = eqTime + 4 * coordinate.longitude
        let trueSolarMinutes = hourUTC * 60 + timeOffset
        var hourAngleDeg = trueSolarMinutes / 4 - 180
        if hourAngleDeg < -180 { hourAngleDeg += 360 }
        let hourAngle = hourAngleDeg * .pi / 180
        let lat = coordinate.latitude * .pi / 180
        // Solar zenith cosine → elevation.
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        let elevationDeg = 90 - acos(max(-1, min(1, cosZenith))) * 180 / .pi
        // Civil night begins when the sun drops below -0.833° (standard
        // refraction-adjusted sunset).
        return elevationDeg < -0.833
    }
}
