import Foundation

/// Row shape of the `city_culture` table, the "how a city talks and thinks"
/// layer: slang, sayings, quotes, and notable people, shown on the city intro
/// / culture shelf.
/// `GET /rest/v1/city_culture?city=eq.{city}&order=sort`
///
/// ```json
/// { "id": "10535853-…", "city": "chicago", "kind": "slang", "headline": "pop",
///   "body": "Not soda, not coke…", "attribution": null, "emoji": "🥤",
///   "year": null, "place_id": null, "links": {}, "source": "seed:dev",
///   "license": "cc0", "sort": 10 }
/// ```
struct CityCulture: Codable, Identifiable, Hashable {
    let id: String
    let city: String
    let kind: Kind
    /// The word, phrase, quote title, or person's name (the card title).
    let headline: String
    /// The explanation / definition / quote body.
    let body: String?
    /// Who said it (quotes) or the source of a saying; nil for slang.
    let attribution: String?
    let emoji: String?
    /// Relevant year for a quote or a person, when known.
    let year: Int?
    /// Optional place this culture note is anchored to.
    let placeID: String?
    /// Read-more links, e.g. `{ "wikipedia_title": "…" }`.
    let links: CultureLinks
    let source: String?
    let license: String?
    /// Curated display order within the city.
    let sort: Int?

    enum CodingKeys: String, CodingKey {
        case id, city, kind, headline, body, attribution, emoji, year, links
        case source, license, sort
        case placeID = "place_id"
    }

    /// The four culture registers the DB enum allows.
    enum Kind: String, Codable, Hashable, CaseIterable {
        /// A local word ("pop", "the Loop").
        case slang
        /// A local saying / turn of phrase.
        case saying
        /// A memorable quote about the city.
        case quote
        /// A notable person from / tied to the city.
        case person

        /// Forward-compatible decode: unknown DB values fall back to `.saying`
        /// so a new enum member on the server never crashes an old build.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .saying
        }

        /// Section header for grouping culture cards.
        var sectionTitle: String {
            switch self {
            case .slang: return "Slang"
            case .saying: return "Sayings"
            case .quote: return "Quotes"
            case .person: return "People"
            }
        }

        /// Fallback emoji when a row has none.
        var defaultEmoji: String {
            switch self {
            case .slang: return "💬"
            case .saying: return "🗯️"
            case .quote: return "❝"
            case .person: return "👤"
            }
        }
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return kind.defaultEmoji
    }

    /// The Wikipedia article title for a person / quote read-more, if present.
    var wikipediaTitle: String? { links.wikipediaTitle }
}

/// The `links` jsonb on a `city_culture` row. An empty object `{}` decodes to
/// all-nil.
struct CultureLinks: Codable, Hashable {
    let website: String?
    let wikipediaTitle: String?

    enum CodingKeys: String, CodingKey {
        case website
        case wikipediaTitle = "wikipedia_title"
    }

    init(website: String? = nil, wikipediaTitle: String? = nil) {
        self.website = website
        self.wikipediaTitle = wikipediaTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        website = try container.decodeIfPresent(String.self, forKey: .website)
        wikipediaTitle = try container.decodeIfPresent(String.self, forKey: .wikipediaTitle)
    }
}
