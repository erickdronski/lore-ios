import Foundation

/// Row shape of the `city_section` table — the "flavor" layer beyond culture:
/// the dish the city is known for, its sound, its manners, its numbers.
/// `GET /rest/v1/city_section?city=eq.{city}&order=sort`
///
/// `kind` is an open string (not an enum) so new section kinds ship as pure
/// data: the client renders any kind it receives, using `SectionKindMeta` for
/// nicer headers on the kinds it knows and a dignified title-cased fallback
/// for ones it doesn't. Old builds never query this table at all.
struct CitySection: Decodable, Identifiable, Hashable {
    let id: String
    let city: String
    let kind: String
    let title: String
    let body: String
    let attribution: String?
    let emoji: String?
    let placeID: String?
    let sort: Int?

    enum CodingKeys: String, CodingKey {
        case id, city, kind, title, body, attribution, emoji, sort
        case placeID = "place_id"
    }
}

/// Display metadata per known section kind; unknown kinds fall back to a
/// title-cased header so future ingestion waves need no client update.
enum SectionKindMeta {
    /// (eyebrow, title) for the section header, mirroring the Culture page's
    /// eyebrow/title voice.
    static func header(for kind: String) -> (eyebrow: String, title: String) {
        switch kind {
        case "name_origin": return ("First, the Name", "Why It's Called That")
        case "dish": return ("Eat Like a Local", "Taste of the City")
        case "ritual": return ("Live Like a Local", "Rituals")
        case "soundmark": return ("Eyes Closed", "The City's Sound")
        case "material": return ("Look Closer", "What It's Made Of")
        case "sound": return ("Turn It Up", "The City's Sound")
        case "screen": return ("As Seen On", "Screen & Page")
        case "etiquette": return ("Blend In", "Local Code")
        case "number": return ("The Big Figures", "City in Numbers")
        case "market": return ("Go Where They Go", "Markets & Streets")
        case "experience": return ("Start Here", "A Route Through the City")
        case "listen": return ("Phone Down", "Listen to the City")
        case "field_note": return ("Your Turn", "Explorer Prompt")
        default:
            let pretty = kind.replacingOccurrences(of: "_", with: " ").capitalized
            return ("The City's Own", pretty)
        }
    }

    /// Stable ordering for known kinds; unknown kinds sort after, alphabetically.
    static func order(for kind: String) -> Int {
        switch kind {
        case "name_origin": return 0   // identity first
        case "dish": return 1
        case "ritual": return 2
        case "soundmark": return 3
        case "material": return 4
        case "sound": return 5
        case "screen": return 6
        case "etiquette": return 7
        case "market": return 8
        case "number": return 9
        case "experience": return 10
        case "listen": return 11
        case "field_note": return 12
        default: return 50
        }
    }
}
