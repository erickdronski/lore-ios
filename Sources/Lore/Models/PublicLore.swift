import Foundation

/// One shared traveler note on a place, from the moderated `lore_public` view
/// (opt-in rows only, `visible`/`approved` status, caller's blocks applied
/// server-side). The view projects ONLY safe columns — the author appears as
/// their chosen display name or "A traveler", never an email.
///
/// `authorID` is granted to `authenticated` only: a signed-out reader must not
/// be able to correlate a stable account id across places into a movement
/// history, so `anon` has no column privilege on it and the key is simply
/// absent from their payload. Report/block (which need the id) already require
/// a session, so this is nil exactly when those affordances are unavailable.
struct PublicLore: Decodable, Identifiable {
    let id: String
    let placeID: String
    let authorID: String?
    let displayName: String
    let note: String?
    let visitedAt: String?
    let sharedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case authorID = "author_id"
        case displayName = "display_name"
        case note
        case visitedAt = "visited_at"
        case sharedAt = "shared_at"
    }

    /// A friendly date from the ISO share timestamp.
    var dateLabel: String {
        guard let stamp = sharedAt ?? visitedAt else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: stamp)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.date(from: stamp) }()
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: date)
    }
}
