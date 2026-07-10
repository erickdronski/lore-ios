import CoreLocation
import Foundation

/// Row shape of the `story` table, the "meanwhile-nearby" layer: a moment in
/// history pinned to a real spot that has no building of its own (a fire, a
/// film shoot, a riot, an invention). Surfaced in the scanner when the user's
/// pose is within ~150 m (12-SCANNER-INTELLIGENCE.md §3.1), distance is
/// filtered client-side.
/// `GET /rest/v1/story?city=eq.{city}`
///
/// ```json
/// { "id": "d2d78d25-…", "city": "chicago",
///   "title": "The night the Board of Trade clock stopped",
///   "narrative": "On a still October evening in 1930…", "year": 1930,
///   "year_label": "1930", "lat": 41.8781, "lng": -87.6322, "emoji": "🕰️",
///   "tags": ["ghost","finance","depression"], "links": {},
///   "source": "seed:dev", "license": "cc0", "created_at": "2026-07-02T…" }
/// ```
struct Story: Codable, Identifiable, Hashable {
    let id: String
    let city: String
    let title: String
    /// The short historical vignette (docent voice, one arresting moment).
    let narrative: String?
    /// The event year, when a single year applies.
    let year: Int?
    /// Human display for the year ("1930", "c. 1871", "1920s"), prefer this
    /// over `year` for rendering.
    let yearLabel: String?
    /// Real-world spot the moment happened.
    let lat: Double
    let lng: Double
    let emoji: String?
    /// Free-form tags (`ghost`, `finance`, `film`, …). Drives the haunted /
    /// interest layers.
    let tags: [String]
    /// Read-more links (`{ "wikipedia_title": "…" }`).
    let links: CultureLinks
    let source: String?
    let license: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, city, title, narrative, year, lat, lng, emoji, tags, links
        case source, license
        case yearLabel = "year_label"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        city = try container.decode(String.self, forKey: .city)
        title = try container.decode(String.self, forKey: .title)
        narrative = try container.decodeIfPresent(String.self, forKey: .narrative)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        yearLabel = try container.decodeIfPresent(String.self, forKey: .yearLabel)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        links = try container.decodeIfPresent(CultureLinks.self, forKey: .links) ?? CultureLinks()
        source = try container.decodeIfPresent(String.self, forKey: .source)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return "🕰️"
    }

    /// Prefer the curated `year_label`, then a bare `year`, else empty.
    var displayYear: String {
        if let yearLabel, !yearLabel.isEmpty { return yearLabel }
        if let year { return String(year) }
        return ""
    }

    /// True when this story belongs to the opt-in haunted / spooky layer.
    var isHaunted: Bool {
        tags.contains("ghost") || tags.contains("haunted") || tags.contains("haunted-lore")
    }

    /// True for the easter-egg layer: real, obscure finds most visitors walk
    /// right past (the `hidden-find` tag authored across the atlas). These
    /// earn a distinct ✦ treatment in the scanner and story sheets.
    var isHiddenFind: Bool {
        tags.contains("hidden-find")
    }

    /// Distance in meters from a given location, the client-side proximity
    /// filter the scanner uses to decide whether to float this marker.
    func distance(from location: CLLocation) -> CLLocationDistance {
        self.location.distance(from: location)
    }
}
