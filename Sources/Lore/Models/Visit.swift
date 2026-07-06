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
        /// Auto-captured by dwell / geofence (the `VisitTracker`, docs/26 §1).
        /// The `visit.source` column already defaults to `'tap'` and accepts
        /// arbitrary sources, so `'gps'` needs no migration.
        case gps
    }
}

/// A device pose stamped into `visit.device_pose` on an auto-captured visit
/// (docs/26 §1, docs/04 §2.3). Same field shape as `contribution.device_pose`
/// so exports and audits read one schema: `{lat, lng, alt_m, h_accuracy_m,
/// v_accuracy_m, heading_deg, captured_at}`. This is the fix that *triggered*
/// the capture, not continuous tracking, one row per collected place.
struct VisitPose: Hashable {
    let lat: Double
    let lng: Double
    /// Altitude in meters, if the fix carried one.
    let altitudeM: Double?
    /// Horizontal accuracy in meters (negative ⇒ invalid, omitted).
    let horizontalAccuracyM: Double?
    /// Vertical accuracy in meters (negative ⇒ invalid, omitted).
    let verticalAccuracyM: Double?
    /// Course/heading in degrees, if known.
    let headingDeg: Double?
    /// ISO-8601 timestamp of the fix.
    let capturedAt: String

    /// The jsonb object POSTed as `device_pose`. Only present, valid fields are
    /// included, so a coarse fix never writes bogus `-1` accuracies.
    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "lat": lat,
            "lng": lng,
            "captured_at": capturedAt,
        ]
        if let altitudeM { object["alt_m"] = altitudeM }
        if let horizontalAccuracyM, horizontalAccuracyM >= 0 {
            object["h_accuracy_m"] = horizontalAccuracyM
        }
        if let verticalAccuracyM, verticalAccuracyM >= 0 {
            object["v_accuracy_m"] = verticalAccuracyM
        }
        if let headingDeg, headingDeg >= 0 { object["heading_deg"] = headingDeg }
        return object
    }
}
