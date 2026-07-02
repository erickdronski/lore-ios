import Foundation

/// One row returned by the `search_lore` RPC — a unified hit across places,
/// stories, tours, culture, and cities.
/// `POST /rest/v1/rpc/search_lore { "q": "...", "max_results": N }`
///
/// ```json
/// { "kind": "place", "ref": "d0843219-…", "slug": "cayan-tower",
///   "label": "Cayan Tower", "sublabel": "Dubai", "city": "dubai",
///   "emoji": "🌀", "score": 0.68 }
/// ```
struct SearchResult: Codable, Identifiable, Hashable {
    /// What kind of thing this hit is — drives which screen a tap routes to.
    let kind: Kind
    /// The row's primary key / reference within its table (place id, story id,
    /// tour slug, …). Use with `kind` to open the right detail.
    let ref: String
    /// URL-safe slug where the entity has one.
    let slug: String?
    /// Primary result line (place name, story title, …).
    let label: String
    /// Secondary line (city name, "Tour", year, …).
    let sublabel: String?
    /// The city slug this hit belongs to (for scoping / fly-to).
    let city: String?
    let emoji: String?
    /// Relevance score from the RPC — results arrive ranked, highest first.
    let score: Double?

    /// Stable identity: `kind` + `ref` uniquely locate a hit.
    var id: String { "\(kind.rawValue):\(ref)" }

    enum CodingKeys: String, CodingKey {
        case kind, ref, slug, label, sublabel, city, emoji, score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .place
        ref = try container.decode(String.self, forKey: .ref)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        label = try container.decode(String.self, forKey: .label)
        sublabel = try container.decodeIfPresent(String.self, forKey: .sublabel)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        score = try container.decodeIfPresent(Double.self, forKey: .score)
    }

    /// The entity types `search_lore` can return.
    enum Kind: String, Codable, Hashable, CaseIterable {
        case place
        case story
        case tour
        case culture
        case city

        /// Forward-compatible: unknown kinds fall back to `.place`.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .place
        }

        /// SF Symbol hint for the result row's leading glyph.
        var symbolName: String {
            switch self {
            case .place: return "mappin.and.ellipse"
            case .story: return "text.book.closed"
            case .tour: return "figure.walk"
            case .culture: return "quote.bubble"
            case .city: return "building.2"
            }
        }
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return ""
    }
}
