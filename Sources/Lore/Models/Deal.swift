import Foundation

/// One live offer tied to a place (or city-wide), from the `place_deal_feed`
/// view / `deal` table. Every row is a REAL deal a curator checked on the
/// source marketplace — `fetchedAt` is when, and the UI says so. `matchKind`
/// carries the honesty of the link: `included` (admission to this place is
/// part of the offer), `nearby` (steps away), `city` (city-wide experience).
struct Deal: Decodable, Identifiable {
    let id: String
    let source: String
    let city: String
    let title: String
    let merchant: String
    let url: String
    let priceOriginal: String?
    let priceDeal: String?
    let discountLabel: String?
    let rating: Double?
    let ratingCount: Int?
    let matchKind: String
    let matchNote: String?
    let fetchedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source, city, title, merchant, url, rating
        case priceOriginal = "price_original"
        case priceDeal = "price_deal"
        case discountLabel = "discount_label"
        case ratingCount = "rating_count"
        case matchKind = "match_kind"
        case matchNote = "match_note"
        case fetchedAt = "fetched_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        city = try c.decode(String.self, forKey: .city)
        title = try c.decode(String.self, forKey: .title)
        merchant = try c.decode(String.self, forKey: .merchant)
        url = try c.decode(String.self, forKey: .url)
        priceOriginal = try c.decodeIfPresent(String.self, forKey: .priceOriginal)
        priceDeal = try c.decodeIfPresent(String.self, forKey: .priceDeal)
        discountLabel = try c.decodeIfPresent(String.self, forKey: .discountLabel)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        ratingCount = try c.decodeIfPresent(Int.self, forKey: .ratingCount)
        // `city_deal_feed` rows carry no match_kind (they are all city-wide);
        // default accordingly so one Deal type serves both feeds.
        matchKind = (try c.decodeIfPresent(String.self, forKey: .matchKind)) ?? "city"
        matchNote = try c.decodeIfPresent(String.self, forKey: .matchNote)
        fetchedAt = try c.decodeIfPresent(String.self, forKey: .fetchedAt)
    }

    var dealURL: URL? { URL(string: url) }

    /// "via Groupon" etc. — the marketplace always gets named.
    var sourceLabel: String { "via \(source.capitalized)" }

    /// A friendly "checked" date from the fetch timestamp, so the price
    /// snapshot is honest about its age.
    var checkedLabel: String? {
        guard let fetchedAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: fetchedAt)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.date(from: fetchedAt) }()
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return "checked \(out.string(from: date))"
    }
}
