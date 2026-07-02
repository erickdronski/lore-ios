import Foundation

/// Row shape of the `tour` table, optionally with `tour_stop` rows embedded
/// via PostgREST resource embedding (`select=*,tour_stop(*)`).
///
/// Live columns: `id`, `slug`, `title`, `city`, `emoji`, `blurb`,
/// `duration_min`, `distance_km`.
struct Tour: Codable, Identifiable, Hashable {
    let id: String
    let slug: String
    let title: String
    let city: String
    let emoji: String?
    let blurb: String?
    let durationMin: Int?
    let distanceKm: Double?
    /// Embedded stops — present when fetched with `select=*,tour_stop(*)`.
    let stops: [TourStop]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, city, emoji, blurb
        case durationMin = "duration_min"
        case distanceKm = "distance_km"
        case stops = "tour_stop"
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
        let embedded = try container.decodeIfPresent([TourStop].self, forKey: .stops) ?? []
        stops = embedded.sorted { $0.seq < $1.seq }
    }

    var displayEmoji: String { emoji ?? "🚶" }

    /// "45 min · 2.5 km" style summary line.
    var summaryLine: String {
        var parts: [String] = []
        if let durationMin { parts.append("\(durationMin) min") }
        if let distanceKm { parts.append(String(format: "%.1f km", distanceKm)) }
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
