import Foundation

/// Row shape of the `visit` table, a logged "I was here" event that feeds the
/// achievement engine. Own rows only, via RLS; clients INSERT, then call
/// `recompute_achievements` to settle newly-unlocked badges.
/// `GET /rest/v1/visit` (with a user bearer token)
///
/// Live columns: `user_id`, `place_id`, `visited_at`, `source`.
struct Visit: Codable, Identifiable, Hashable {
    let userID: String
    let placeID: String
    /// ISO-8601 timestamp; server-defaulted to `now()` when omitted on insert.
    let visitedAt: String?
    /// How the visit was logged (`scanner`, `map`, `tour`, `manual`).
    let source: String?

    /// Composite identity for lists (one place can be visited many times, so
    /// fold in the timestamp).
    var id: String { "\(userID)#\(placeID)#\(visitedAt ?? "")" }

    enum CodingKeys: String, CodingKey {
        case source
        case userID = "user_id"
        case placeID = "place_id"
        case visitedAt = "visited_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        placeID = try container.decode(String.self, forKey: .placeID)
        visitedAt = try container.decodeIfPresent(String.self, forKey: .visitedAt)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    init(userID: String, placeID: String, visitedAt: String? = nil, source: String? = nil) {
        self.userID = userID
        self.placeID = placeID
        self.visitedAt = visitedAt
        self.source = source
    }

    /// How a visit came to be logged, passed to `logVisit(placeID:source:)`.
    enum Source: String {
        /// Locked a Tier-A pin in the camera.
        case scanner
        /// Tapped a pin on the living map.
        case map
        /// Reached a stop on an active tour.
        case tour
        /// Manually marked as visited.
        case manual
    }
}
