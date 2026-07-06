import Foundation

/// Row shape of the `dive` table, the cached deep-dive dossier for one place
/// (synthesized once, read many; lore/docs/03-ARCHITECTURE.md §7).
///
/// Live PostgREST columns: `place_id`, `narrative`, `timeline`, `links`,
/// `media`, `source`. `links` and `media` are jsonb OBJECTS (not arrays) and
/// every jsonb column can be null, so each is decoded leniently: a null,
/// absent, or unexpectedly-shaped value defaults to empty and NEVER throws, so
/// one odd row can never fail the whole dossier (the bug that broke the
/// paywalled deep dive on device).
struct Dive: Codable, Hashable {
    let placeID: String
    /// Long-form docent narrative (the DiveSheet reader body).
    let narrative: String?
    /// Horizontal timeline events, oldest first.
    let timeline: [TimelineEvent]
    /// Source / read-more links, a jsonb OBJECT
    /// ({"website": "...", "wikipedia_title": "..."}).
    let links: DiveLinks
    /// The dossier's lead image reference, resolved from
    /// `media.wikipedia_title` via the Wikipedia summary API (the same source
    /// the culture portraits use). Also a jsonb OBJECT.
    let media: DiveMediaRef
    /// Synthesis provenance tag.
    let source: String?

    enum CodingKeys: String, CodingKey {
        case narrative, timeline, links, media, source
        case placeID = "place_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeID = try container.decode(String.self, forKey: .placeID)
        narrative = try container.decodeIfPresent(String.self, forKey: .narrative)
        timeline = (try? container.decodeIfPresent([TimelineEvent].self, forKey: .timeline)) ?? []
        links = (try? container.decodeIfPresent(DiveLinks.self, forKey: .links)) ?? DiveLinks()
        media = (try? container.decodeIfPresent(DiveMediaRef.self, forKey: .media)) ?? DiveMediaRef()
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    init(
        placeID: String,
        narrative: String?,
        timeline: [TimelineEvent] = [],
        links: DiveLinks = DiveLinks(),
        media: DiveMediaRef = DiveMediaRef(),
        source: String? = nil
    ) {
        self.placeID = placeID
        self.narrative = narrative
        self.timeline = timeline
        self.links = links
        self.media = media
        self.source = source
    }
}

/// One node on the dive timeline: `{ "year": 1973, "title": "…",
/// "detail": "…", "emoji": "🏗️" }`.
struct TimelineEvent: Codable, Hashable, Identifiable {
    let year: Int
    let title: String
    let detail: String?
    let emoji: String?

    var id: String { "\(year)-\(title)" }
}

/// `dive.links`, a jsonb object. Both fields optional; a link row only renders
/// when its value is present.
struct DiveLinks: Codable, Hashable {
    let website: String?
    let wikipediaTitle: String?

    enum CodingKeys: String, CodingKey {
        case website
        case wikipediaTitle = "wikipedia_title"
    }

    init(website: String? = nil, wikipediaTitle: String? = nil) {
        self.website = website
        self.wikipediaTitle = wikipediaTitle
    }

    /// The read-more Wikipedia article URL for this dive, if it names one.
    var wikipediaURL: URL? {
        guard let title = wikipediaTitle,
              let encoded = title.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }
}

/// `dive.media`, a jsonb object naming the Wikipedia article whose lead image
/// is the dossier's gallery photo. Resolved to a URL at render via
/// `WikipediaService`.
struct DiveMediaRef: Codable, Hashable {
    let wikipediaTitle: String?

    enum CodingKeys: String, CodingKey {
        case wikipediaTitle = "wikipedia_title"
    }

    init(wikipediaTitle: String? = nil) {
        self.wikipediaTitle = wikipediaTitle
    }
}
