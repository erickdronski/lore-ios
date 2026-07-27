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
    /// Server-derived teaser: the curated `layer1.hook` when present, else the
    /// first sentence of the place's dive narrative. 49% of places have no
    /// curated hook, and reading the fallback here means a shelf card gets real
    /// text without fetching a dive per card. Prefer `teaser` over
    /// `layer1?.hook` on any list surface.
    let hookText: String?
    /// Photo reference from the place's dive (`dive.media.wikipedia_title`),
    /// surfaced on the read view so list cards can resolve imagery without an
    /// extra round-trip each.
    let wikipediaTitle: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, kind, lat, lng, city, layer1, tags, emoji
        case heightM = "height_m"
        case hookText = "hook_text"
        case wikipediaTitle = "wikipedia_title"
    }

    /// Explicit memberwise init — restored because adding a custom `init(from:)`
    /// below suppresses the compiler-synthesized one (used by tests / any direct
    /// construction). Declaration order, with the optionals defaulted.
    init(id: String, slug: String, name: String, kind: String, lat: Double, lng: Double,
         heightM: Double? = nil, city: String, layer1: Layer1? = nil,
         tags: [String] = [], emoji: String? = nil,
         hookText: String? = nil, wikipediaTitle: String? = nil) {
        self.id = id; self.slug = slug; self.name = name; self.kind = kind
        self.lat = lat; self.lng = lng; self.heightM = heightM; self.city = city
        self.layer1 = layer1; self.tags = tags; self.emoji = emoji
        self.hookText = hookText; self.wikipediaTitle = wikipediaTitle
    }

    /// Resilient decode: a single row with a null `slug` (or null `tags`) must
    /// never throw and empty the whole `[Place]` — that once wiped the scanner in
    /// four live cities. `slug` falls back to a name-derived slug, then the id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        if let s = try c.decodeIfPresent(String.self, forKey: .slug), !s.isEmpty {
            slug = s
        } else {
            let derived = name.lowercased().replacingOccurrences(of: " ", with: "-")
            slug = derived.isEmpty ? id : derived
        }
        kind = try c.decode(String.self, forKey: .kind)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        heightM = try c.decodeIfPresent(Double.self, forKey: .heightM)
        city = try c.decode(String.self, forKey: .city)
        layer1 = try c.decodeIfPresent(Layer1.self, forKey: .layer1)
        tags = (try c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji)
        // Absent on older cached payloads and on any surface still selecting the
        // pre-derived column set, so decode leniently rather than throwing and
        // emptying the whole list.
        hookText = try c.decodeIfPresent(String.self, forKey: .hookText)
        wikipediaTitle = try c.decodeIfPresent(String.self, forKey: .wikipediaTitle)
    }

    /// The teaser a list card should show: the server-derived hook (curated, or
    /// the narrative's first sentence) falling back to the raw curated hook for
    /// any payload predating the derived column.
    var teaser: String? {
        if let hookText, !hookText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return hookText
        }
        if let hook = layer1?.hook, !hook.isEmpty { return hook }
        return nil
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
