import Foundation

/// The whole Passport scrapbook in one payload, the shape the `travel_stats`
/// RPC returns (lore/docs/26-TRAVEL-PASSPORT.md "Backend"): a `SECURITY DEFINER`
/// function that reads the caller's own `visit` rows and returns the tally, the
/// city stamps, and the recent-visit feed already joined to place + city + the
/// photo title. One call feeds the Passport, so the client never fans out N
/// place lookups.
///
/// `POST /rest/v1/rpc/travel_stats { "p_user": userID }` → this object.
///
/// Every field is optional-tolerant on decode: a brand-new user with zero
/// visits gets an all-zero tally and empty arrays, never a decode error, so the
/// composed empty state (docs/26 §3 "A composed empty state") renders instead of
/// a failure.
struct TravelStats: Codable, Hashable {
    /// The Wrapped headline numbers (docs/26 §3 "The tally").
    let totals: Totals
    /// One entry per city the user has collected a place in (docs/26 §3 "The
    /// stamp wall"), earned on the first visit there.
    let cityStamps: [CityStamp]
    /// Reverse-chronological postcards (docs/26 §3 "The feed").
    let recentVisits: [RecentVisit]

    enum CodingKeys: String, CodingKey {
        case totals
        case cityStamps = "city_stamps"
        case recentVisits = "recent_visits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totals = try container.decodeIfPresent(Totals.self, forKey: .totals) ?? .empty
        cityStamps = try container.decodeIfPresent([CityStamp].self, forKey: .cityStamps) ?? []
        recentVisits = try container.decodeIfPresent([RecentVisit].self, forKey: .recentVisits) ?? []
    }

    init(totals: Totals, cityStamps: [CityStamp], recentVisits: [RecentVisit]) {
        self.totals = totals
        self.cityStamps = cityStamps
        self.recentVisits = recentVisits
    }

    /// The zero state, so the Passport can render its empty scrapbook without a
    /// round trip (signed out, or before the first fetch lands).
    static let empty = TravelStats(totals: .empty, cityStamps: [], recentVisits: [])

    /// True when the user hasn't collected anything yet, drives the empty state.
    var isEmpty: Bool { totals.places == 0 && recentVisits.isEmpty }

    // MARK: - Totals

    /// The always-live tally, the big Fraunces numerals at the top of the wall.
    struct Totals: Codable, Hashable {
        /// Distinct places collected.
        let places: Int
        /// Distinct cities collected.
        let cities: Int
        /// Distinct countries collected.
        let countries: Int
        /// Places collected in the current calendar year (the Wrapped year line).
        let thisYear: Int

        enum CodingKeys: String, CodingKey {
            case places, cities, countries
            case thisYear = "this_year"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            places = try container.decodeIfPresent(Int.self, forKey: .places) ?? 0
            cities = try container.decodeIfPresent(Int.self, forKey: .cities) ?? 0
            countries = try container.decodeIfPresent(Int.self, forKey: .countries) ?? 0
            thisYear = try container.decodeIfPresent(Int.self, forKey: .thisYear) ?? 0
        }

        init(places: Int, cities: Int, countries: Int, thisYear: Int) {
            self.places = places
            self.cities = cities
            self.countries = countries
            self.thisYear = thisYear
        }

        static let empty = Totals(places: 0, cities: 0, countries: 0, thisYear: 0)
    }

    // MARK: - City stamp

    /// One passport stamp: a city the user has collected at least one place in,
    /// with the count and the day it was first stamped.
    struct CityStamp: Codable, Hashable, Identifiable {
        /// The `city` slug (the join key everywhere, `Place.city`).
        let slug: String
        /// Display name (`Chicago`), falls back to a titlecased slug if absent.
        let name: String?
        /// ISO country code (`US`), for the stamp's country line.
        let country: String?
        /// City emoji, the stamp's medallion glyph.
        let emoji: String?
        /// Places collected in this city.
        let count: Int
        /// ISO-8601 day the first place here was collected (the stamp date).
        let firstVisitedAt: String?

        var id: String { slug }

        enum CodingKeys: String, CodingKey {
            case slug, name, country, emoji, count
            case firstVisitedAt = "first_visited_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            slug = try container.decode(String.self, forKey: .slug)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            country = try container.decodeIfPresent(String.self, forKey: .country)
            emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
            count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
            firstVisitedAt = try container.decodeIfPresent(String.self, forKey: .firstVisitedAt)
        }

        init(slug: String, name: String?, country: String?, emoji: String?, count: Int, firstVisitedAt: String?) {
            self.slug = slug
            self.name = name
            self.country = country
            self.emoji = emoji
            self.count = count
            self.firstVisitedAt = firstVisitedAt
        }

        /// Display name or a prettified slug (`museum-campus` → `Museum Campus`).
        var displayName: String {
            if let name, !name.isEmpty { return name }
            return slug
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }

        var displayEmoji: String {
            if let emoji, !emoji.isEmpty { return emoji }
            return "🏙️"
        }
    }

    // MARK: - Recent visit (postcard)

    /// One postcard in the feed: a collected place, resolved to its name, city,
    /// date, the user's note, and a `wikipediaTitle` the client feeds to
    /// `WikipediaService.portraitURL` for the lead photo (docs/26 §3 "The feed").
    struct RecentVisit: Codable, Hashable, Identifiable {
        /// The visited `place.id`, so a tapped postcard routes to the dossier.
        let placeID: String
        let placeName: String
        /// Place kind (`building`, `statue`, …), for the emoji fallback.
        let kind: String?
        /// The `city` slug the place belongs to.
        let city: String?
        /// City display name (`Chicago`).
        let cityName: String?
        /// ISO-8601 timestamp the visit was logged.
        let visitedAt: String?
        /// The user's note on this visit, if any.
        let note: String?
        /// How the visit was logged (`gps`, `map`, `tour`, `manual`, `scanner`).
        let source: String?
        /// Wikipedia article title for the lead-photo lookup (nullable, many
        /// places have no article, then the postcard keeps its emoji plate).
        let wikipediaTitle: String?
        /// Explicit place emoji, if the row carried one.
        let emoji: String?

        /// Composite identity, a place can appear once per day in the feed.
        var id: String { "\(placeID)#\(visitedAt ?? "")" }

        enum CodingKeys: String, CodingKey {
            case placeID = "place_id"
            case placeName = "place_name"
            case kind, city, note, source, emoji
            case cityName = "city_name"
            case visitedAt = "visited_at"
            case wikipediaTitle = "wikipedia_title"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            placeID = try container.decode(String.self, forKey: .placeID)
            placeName = try container.decodeIfPresent(String.self, forKey: .placeName) ?? "A place"
            kind = try container.decodeIfPresent(String.self, forKey: .kind)
            city = try container.decodeIfPresent(String.self, forKey: .city)
            cityName = try container.decodeIfPresent(String.self, forKey: .cityName)
            visitedAt = try container.decodeIfPresent(String.self, forKey: .visitedAt)
            note = try container.decodeIfPresent(String.self, forKey: .note)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            wikipediaTitle = try container.decodeIfPresent(String.self, forKey: .wikipediaTitle)
            emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        }

        init(
            placeID: String,
            placeName: String,
            kind: String? = nil,
            city: String? = nil,
            cityName: String? = nil,
            visitedAt: String? = nil,
            note: String? = nil,
            source: String? = nil,
            wikipediaTitle: String? = nil,
            emoji: String? = nil
        ) {
            self.placeID = placeID
            self.placeName = placeName
            self.kind = kind
            self.city = city
            self.cityName = cityName
            self.visitedAt = visitedAt
            self.note = note
            self.source = source
            self.wikipediaTitle = wikipediaTitle
            self.emoji = emoji
        }

        /// Emoji plate for a postcard with no photo: explicit column wins, else a
        /// per-kind default matching `Place.displayEmoji`.
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

        /// City display name or a prettified slug fallback.
        var displayCity: String? {
            if let cityName, !cityName.isEmpty { return cityName }
            guard let city, !city.isEmpty else { return nil }
            return city
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}

// MARK: - Date formatting

extension TravelStats {
    /// Shared parser for the ISO-8601 timestamps the RPC returns (PostgREST
    /// emits fractional seconds), so every postcard and stamp reads a date the
    /// same way.
    static func parseDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: iso) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: iso) { return d }
        // Fall back to a date-only day (`2026-07-06`), used by the stamp date.
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(iso.prefix(10)))
    }

    /// A short "Jul 6, 2026" label for a postcard / stamp date.
    static func dayLabel(_ iso: String?) -> String? {
        guard let date = parseDate(iso) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
