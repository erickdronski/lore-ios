import CoreLocation
import Foundation

/// Row shape of the public read view `place_explore` (live PostgREST surface,
/// mirrored from `lore-web/lib/types.ts` + the deployed view).
///
/// ```json
/// { "id": "215607ca-…", "slug": "willis-tower", "name": "Willis Tower",
///   "kind": "building", "lat": 41.8789, "lng": -87.6359, "height_m": 442,
///   "city": "chicago", "layer1": { "hook": "…", "style": "…",
///   "architect": "…", "year_built": 1973 }, "tags": [], "emoji": null }
/// ```
struct Place: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let name: String
    /// 'building' | 'statue' | 'monument' | …
    let kind: String
    let lat: Double
    let lng: Double
    let heightM: Double?
    let city: String
    let layer1: Layer1?
    let tags: [String]
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, kind, lat, lng, city, layer1, tags, emoji
        case heightM = "height_m"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }

    /// Emoji badge for map pins / scanner chips: explicit `emoji` column wins,
    /// otherwise a per-kind default.
    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        switch kind {
        case "statue", "sculpture": return "🗿"
        case "monument", "memorial": return "🏛️"
        case "bridge": return "🌉"
        case "park": return "🌳"
        case "church", "temple": return "⛪️"
        default: return "🏙️"
        }
    }
}

/// The Layer-1 card projection embedded in `place_explore.layer1` (jsonb).
/// Hooks are authored from CC0/PD/user_cla sources only, never CC-BY-SA
/// (lore/docs/04-DATA-SCHEMA.md §2.2); safe to render without attribution.
struct Layer1: Codable, Hashable {
    let hook: String?
    let yearBuilt: Int?
    let architect: String?
    let style: String?
    /// Where the name comes from ("Named for the boat marina at its base…") —
    /// the live `place_explore.layer1` carries this; safe (CC0/PD) to render.
    let nameMeaning: String?

    enum CodingKeys: String, CodingKey {
        case hook, architect, style
        case yearBuilt = "year_built"
        case nameMeaning = "name_meaning"
    }
}
