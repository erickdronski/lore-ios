import CoreLocation
import Foundation

/// Row shape of the `city` table, the roster of chronicled cities.
/// `GET /rest/v1/city?status=eq.live&order=sort`
///
/// ```json
/// { "slug": "chicago", "name": "Chicago", "country": "US", "emoji": "🫘",
///   "lat": 41.8827, "lng": -87.6233, "zoom": 14.2, "status": "live", "sort": 1 }
/// ```
///
/// The table has no separate `id` column; `slug` is the stable identity every
/// other read surface filters by (`city=eq.{slug}`).
struct City: Codable, Identifiable, Hashable {
    /// URL-safe city key (`chicago`, `nyc`, …). The join key everywhere.
    let slug: String
    let name: String
    /// ISO country code (`US`, …).
    let country: String?
    let emoji: String?
    /// Default map camera center.
    let lat: Double
    let lng: Double
    /// Default MapKit / MapLibre zoom for the arrival fly-to.
    let zoom: Double?
    /// `live` | `coming_soon` | …, only `live` cities are fetched for pins.
    let status: String
    /// Curated display order in the city switcher.
    let sort: Int?

    /// `slug` is the identity, the table has no `id` column.
    var id: String { slug }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return "🏙️"
    }

    /// True when this city has published data and should render pins.
    var isLive: Bool { status == "live" }
}
