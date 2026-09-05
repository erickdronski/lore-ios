import Foundation

/// Row shape of the `tour` table, optionally with `tour_stop` rows embedded
/// via PostgREST resource embedding (`select=*,tour_stop(*)`).
///
/// Live columns: `id`, `slug`, `title`, `city`, `emoji`, `blurb`,
/// `duration_min`, `distance_km`, `is_premium`.
struct Tour: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let city: String
    let emoji: String?
    let blurb: String?
    let durationMin: Int?
    let distanceKm: Double?
    let travelMode: TravelMode
    let distanceKind: DistanceKind
    let routeNote: String?
    let routeSource: String?
    let routeCheckedAt: String?

    enum TravelMode: String, Codable, Hashable {
        case walking, mixed
        init(from decoder: Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .mixed
        }
    }

    enum DistanceKind: String, Codable, Hashable {
        case estimated, walkingRoute = "walking_route", minimum
        init(from decoder: Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .minimum
        }
    }
    /// Whether this is a Lore+ curated walk (gated for free users). The
    /// generated "1 Hour In" walk is always free.
    let isPremium: Bool
    /// Embedded stops, present when fetched with `select=*,tour_stop(*)`.
    let stops: [TourStop]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, city, emoji, blurb
        case durationMin = "duration_min"
        case distanceKm = "distance_km"
        case travelMode = "travel_mode"
        case distanceKind = "distance_kind"
        case routeNote = "route_note"
        case routeSource = "route_source"
        case routeCheckedAt = "route_checked_at"
        case isPremium = "is_premium"
        case stops = "tour_stop"
    }

    /// Memberwise init for tours built in code (the generated "1 Hour In" walk),
    /// since the custom decoder below suppresses the synthesized one.
    init(
        id: String, slug: String, title: String, city: String,
        emoji: String?, blurb: String?, durationMin: Int?, distanceKm: Double?,
        isPremium: Bool = false, stops: [TourStop],
        travelMode: TravelMode = .walking, distanceKind: DistanceKind = .estimated,
        routeNote: String? = nil, routeSource: String? = nil, routeCheckedAt: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.city = city
        self.emoji = emoji
        self.blurb = blurb
        self.durationMin = durationMin
        self.distanceKm = distanceKm
        self.travelMode = travelMode
        self.distanceKind = distanceKind
        self.routeNote = routeNote
        self.routeSource = routeSource
        self.routeCheckedAt = routeCheckedAt
        self.isPremium = isPremium
        self.stops = stops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        city = try container.decode(String.self, forKey: .city)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        blurb = try container.decodeIfPresent(String.self, forKey: .blurb)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        distanceKm = try container.decodeIfPresent(Double.self, forKey: .distanceKm)
        travelMode = try container.decodeIfPresent(TravelMode.self, forKey: .travelMode) ?? .walking
        distanceKind = try container.decodeIfPresent(DistanceKind.self, forKey: .distanceKind) ?? .estimated
        routeNote = try container.decodeIfPresent(String.self, forKey: .routeNote)
        routeSource = try container.decodeIfPresent(String.self, forKey: .routeSource)
        routeCheckedAt = try container.decodeIfPresent(String.self, forKey: .routeCheckedAt)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        let embedded = try container.decodeIfPresent([TourStop].self, forKey: .stops) ?? []
        stops = embedded.sorted { $0.seq < $1.seq }
    }

    var requiresTransport: Bool { travelMode == .mixed }
    var displayEmoji: String { emoji ?? (requiresTransport ? "🗺️" : "🚶") }
    var transportLabel: String? { requiresTransport ? "Transport needed" : nil }
    var distanceSystemImage: String { requiresTransport ? "point.topleft.down.to.point.bottomright.curvepath" : "figure.walk" }
    var routeTypeLabel: String {
        requiresTransport ? "CITY EXCURSION" : (isPremium ? "LORE+ FIELD WALK" : "CITY FIELD WALK")
    }

    var distanceLabel: String? {
        guard let distanceKm, distanceKm.isFinite, distanceKm > 0 else { return nil }
        return String(format: distanceKind == .minimum ? "At least %.1f km" : "About %.1f km", distanceKm)
    }

    /// A minimum straight-line distance cannot justify a walking time. Mixed
    /// excursions also need an actual transport itinerary before quoting one.
    var durationLabel: String? {
        guard !requiresTransport, distanceKind != .minimum,
              let durationMin, durationMin > 0 else { return nil }
        return "About \(durationMin) min"
    }

    var routeSourceURL: URL? {
        guard let routeSource, let url = URL(string: routeSource),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    var summaryLine: String {
        var parts = [transportLabel, durationLabel, distanceLabel].compactMap { $0 }
        if !stops.isEmpty { parts.append("\(stops.count) stops") }
        return parts.joined(separator: " · ")
    }
}

/// Row shape of the `tour_stop` table. Composite identity `(tour_id, seq)` —
/// the table has no `id` column.
struct TourStop: Codable, Hashable, Identifiable {
    let tourID: String
    let placeID: String
    /// 1-based order along the walk.
    let seq: Int
    /// Curator note shown on the stop stepper ("look up at the cornice…").
    let note: String?

    enum CodingKeys: String, CodingKey {
        case seq, note
        case tourID = "tour_id"
        case placeID = "place_id"
    }

    var id: String { "\(tourID)#\(seq)" }
}
