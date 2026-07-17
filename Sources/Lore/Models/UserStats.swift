import Foundation

/// The signed-in explorer's world-tracking stats, from the `user_stats(p_user)`
/// RPC (a single jsonb object, RLS-guarded to the caller). Drives the Passport's
/// exploration dashboard. Every number is real, computed server-side from the
/// user's own visits — never estimated.
struct UserStats: Decodable, Hashable {
    let places: Int
    let cities: Int
    let countries: Int
    let continents: Int
    let continentsList: [String]
    let divesRead: Int
    let notes: Int
    let photos: Int
    let publicLores: Int
    let scannerVisits: Int
    let badges: Int
    let badgesTotal: Int
    let insightPoints: Int
    let currentStreak: Int
    let longestStreak: Int
    let topCategories: [CategoryStat]
    let firstVisit: String?

    /// The 7 inhabited-world continents, for the "lit up as you go" globe row.
    /// Antarctica is intentionally excluded (Lore has no places there).
    static let allContinents = [
        "North America", "South America", "Europe", "Africa", "Asia", "Oceania",
    ]

    var hasVisitedContinent: (String) -> Bool {
        { continentsList.contains($0) }
    }

    /// A friendly "exploring since" label from the first visit timestamp.
    var exploringSince: String? {
        guard let firstVisit else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: firstVisit)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.date(from: firstVisit) }()
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: date)
    }

    struct CategoryStat: Decodable, Hashable, Identifiable {
        let kind: String
        let count: Int
        var id: String { kind }
    }

    enum CodingKeys: String, CodingKey {
        case places, cities, countries, continents, notes, photos, badges
        case continentsList = "continents_list"
        case divesRead = "dives_read"
        case publicLores = "public_lores"
        case scannerVisits = "scanner_visits"
        case badgesTotal = "badges_total"
        case insightPoints = "insight_points"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case topCategories = "top_categories"
        case firstVisit = "first_visit"
    }

    /// The empty (signed-out / no-visits) baseline, so the dashboard renders an
    /// honest zero state rather than nothing.
    static let zero = UserStats(
        places: 0, cities: 0, countries: 0, continents: 0, continentsList: [],
        divesRead: 0, notes: 0, photos: 0, publicLores: 0, scannerVisits: 0,
        badges: 0, badgesTotal: 0, insightPoints: 0, currentStreak: 0,
        longestStreak: 0, topCategories: [], firstVisit: nil
    )
}
