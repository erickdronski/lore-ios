import Foundation

/// Row shape of the user's own `saved_place` rows. This is future-tense travel
/// intent: places the traveler wants to remember before they have been there.
/// Reads and writes are owner-scoped by Supabase RLS.
struct SavedPlace: Codable, Identifiable, Hashable {
    let userID: String?
    let placeID: String
    let savedAt: String?
    let note: String?
    let rating: Int?
    let place: PlaceSummary?

    var id: String { placeID }

    enum CodingKeys: String, CodingKey {
        case note, rating, place
        case userID = "user_id"
        case placeID = "place_id"
        case savedAt = "saved_at"
    }

    init(
        userID: String? = nil,
        placeID: String,
        savedAt: String? = nil,
        note: String? = nil,
        rating: Int? = nil,
        place: PlaceSummary? = nil
    ) {
        self.userID = userID
        self.placeID = placeID
        self.savedAt = savedAt
        self.note = note
        self.rating = rating
        self.place = place
    }

    var displayName: String { place?.name ?? "Saved place" }
    var displayKind: String? { place?.kind.capitalized }
    var displayCity: String? { place?.cityTitle }
    var displayEmoji: String { place?.emoji ?? "📍" }

    var savedDate: Date? {
        guard let savedAt else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: savedAt) ?? ISO8601DateFormatter().date(from: savedAt)
    }

    struct PlaceSummary: Codable, Hashable {
        let id: String
        let slug: String?
        let name: String
        let kind: String
        let city: String
        let emoji: String?

        var cityTitle: String {
            city.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
