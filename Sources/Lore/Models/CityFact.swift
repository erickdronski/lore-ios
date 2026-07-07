import Foundation

/// Row shape of the `city_fact` table, the "Did You Know" pillar: the surprising,
/// shareable superlatives, firsts, records, quirks, etymology, and killer stats a
/// local brags about. Surfaces on "Meet {City}" as a swipeable fact deck plus a
/// "By the Numbers" stat strip.
/// `GET /rest/v1/city_fact?city=eq.{city}&order=sort`
///
/// ```json
/// { "id": "…", "city": "chicago", "category": "quirk",
///   "fact": "Chicago reversed its river's flow in 1900…", "detail": null,
///   "stat_value": "1900", "stat_label": "Year of reversal", "emoji": "🚢",
///   "source": "https://…", "sort": 10 }
/// ```
struct CityFact: Codable, Identifiable, Hashable {
    let id: String
    let city: String
    let category: Category
    /// The punchy one-liner (the card headline).
    let fact: String
    /// Optional one-sentence expansion under the fact.
    let detail: String?
    /// Optional headline number/date, e.g. "1,900 miles" or "1718".
    let statValue: String?
    /// Optional label for the stat, e.g. "Total alley length".
    let statLabel: String?
    let emoji: String?
    /// A URL confirming the fact (opened from the card's source affordance).
    let source: String?
    /// Curated display order within the city.
    let sort: Int?

    enum CodingKeys: String, CodingKey {
        case id, city, category, fact, detail, emoji, source, sort
        case statValue = "stat_value"
        case statLabel = "stat_label"
    }

    /// The fact registers the DB enum allows. Drives the eyebrow chip label.
    enum Category: String, Codable, Hashable, CaseIterable {
        case superlative, first, record, quirk, etymology, stat
        case claimToFame = "claim-to-fame"
        case funFact = "fun-fact"

        /// Forward-compatible decode: an unknown DB value falls back to `.funFact`
        /// so a new enum member on the server never crashes an old build.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Category(rawValue: raw) ?? .funFact
        }

        /// The chip label shown as the card eyebrow.
        var label: String {
            switch self {
            case .superlative: return "Superlative"
            case .first: return "A First"
            case .record: return "Record"
            case .quirk: return "Quirk"
            case .etymology: return "Origin"
            case .stat: return "By the Numbers"
            case .claimToFame: return "Claim to Fame"
            case .funFact: return "Did You Know"
            }
        }

        var fallbackEmoji: String {
            switch self {
            case .superlative: return "🏆"
            case .first: return "🥇"
            case .record: return "📈"
            case .quirk: return "🤯"
            case .etymology: return "📜"
            case .stat: return "🔢"
            case .claimToFame: return "⭐️"
            case .funFact: return "💡"
            }
        }
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return category.fallbackEmoji
    }

    /// True when this fact carries a headline number worth featuring in the
    /// "By the Numbers" strip.
    var hasStat: Bool {
        guard let statValue else { return false }
        return !statValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var sourceURL: URL? {
        guard let source, !source.isEmpty else { return nil }
        return URL(string: source)
    }
}
