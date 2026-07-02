import Foundation

/// Row shape of the `dive` table — the cached deep-dive dossier for one place
/// (synthesized once, read many; lore/docs/03-ARCHITECTURE.md §7).
///
/// Live PostgREST columns: `place_id`, `narrative`, `timeline`, `links`,
/// `media`, `source`. The jsonb columns can be null — decoding defaults them
/// to empty arrays so views never branch on optionality.
struct Dive: Codable, Hashable {
    let placeID: String
    /// Long-form docent narrative (the DiveSheet reader body).
    let narrative: String?
    /// Horizontal timeline events, oldest first.
    let timeline: [TimelineEvent]
    /// Source / read-more links (attribution surface for CC-BY-SA prose).
    let links: [DiveLink]
    /// Photos / audio attached to the dossier.
    let media: [DiveMedia]
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
        timeline = try container.decodeIfPresent([TimelineEvent].self, forKey: .timeline) ?? []
        links = try container.decodeIfPresent([DiveLink].self, forKey: .links) ?? []
        media = try container.decodeIfPresent([DiveMedia].self, forKey: .media) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    init(
        placeID: String,
        narrative: String?,
        timeline: [TimelineEvent] = [],
        links: [DiveLink] = [],
        media: [DiveMedia] = [],
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

/// A link row in `dive.links`.
struct DiveLink: Codable, Hashable, Identifiable {
    let title: String?
    let url: String

    var id: String { url }
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return URL(string: url)?.host() ?? url
    }
}

/// A media row in `dive.media`.
struct DiveMedia: Codable, Hashable, Identifiable {
    let url: String
    let kind: String?
    let caption: String?

    var id: String { url }
}
