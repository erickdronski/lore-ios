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
    /// Editorial provenance. HTTPS values become a source affordance in the
    /// flavor card; internal `editorial:` markers remain intentionally hidden.
    let source: String?
    let provenanceState: String?
    let sort: Int?
    let links: Links
    let meta: Meta?

    struct Links: Decodable, Hashable {
        let website: String?
        let sourceURL: String?
        let videoURL: String?
        let youtubeURL: String?
        let tiktokURL: String?
        let instagramURL: String?
        let hashtagURL: String?
        let wikipediaURL: String?

        enum CodingKeys: String, CodingKey {
            case website
            case sourceURL = "source_url"
            case videoURL = "video_url"
            case youtubeURL = "youtube_url"
            case tiktokURL = "tiktok_url"
            case instagramURL = "instagram_url"
            case hashtagURL = "hashtag_url"
            case wikipediaURL = "wikipedia_url"
        }

        init(
            website: String? = nil,
            sourceURL: String? = nil,
            videoURL: String? = nil,
            youtubeURL: String? = nil,
            tiktokURL: String? = nil,
            instagramURL: String? = nil,
            hashtagURL: String? = nil,
            wikipediaURL: String? = nil
        ) {
            self.website = website
            self.sourceURL = sourceURL
            self.videoURL = videoURL
            self.youtubeURL = youtubeURL
            self.tiktokURL = tiktokURL
            self.instagramURL = instagramURL
            self.hashtagURL = hashtagURL
            self.wikipediaURL = wikipediaURL
        }
    }

    struct Meta: Decodable, Hashable {
        let language: String?
        let originalScript: String?
        let original: String?
        let platform: String?
        let creator: String?
        let duration: String?
        let hashtag: String?
        let neighborhood: String?
        let bestSeason: String?
        let confidence: String?
        let rights: String?
        let promptType: String?

        enum CodingKeys: String, CodingKey {
            case language
            case originalScript = "original_script"
            case original
            case platform
            case creator
            case duration
            case hashtag
            case neighborhood
            case bestSeason = "best_season"
            case confidence
            case rights
            case promptType = "prompt_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, city, kind, title, body, attribution, emoji, source, sort, links, meta
        case placeID = "place_id"
        case provenanceState = "provenance_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        city = try container.decode(String.self, forKey: .city)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        placeID = try container.decodeIfPresent(String.self, forKey: .placeID)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        provenanceState = try container.decodeIfPresent(String.self, forKey: .provenanceState)
        sort = try container.decodeIfPresent(Int.self, forKey: .sort)
        links = try container.decodeIfPresent(Links.self, forKey: .links) ?? Links()
        meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
    }

    var sourceURL: URL? {
        Self.validHTTPSURL(source)
    }

    var primaryExternalURL: URL? {
        switch kind {
        case "watch":
            return Self.validHTTPSURL(links.videoURL)
                ?? Self.validHTTPSURL(links.youtubeURL)
                ?? Self.validHTTPSURL(links.tiktokURL)
                ?? Self.validHTTPSURL(links.website)
                ?? sourceURL
        case "hashtag":
            return Self.validHTTPSURL(links.hashtagURL)
                ?? Self.validHTTPSURL(links.tiktokURL)
                ?? Self.validHTTPSURL(links.instagramURL)
                ?? Self.validHTTPSURL(links.website)
                ?? sourceURL
        default:
            return Self.validHTTPSURL(links.website)
                ?? Self.validHTTPSURL(links.sourceURL)
                ?? Self.validHTTPSURL(links.wikipediaURL)
                ?? sourceURL
        }
    }

    var primaryExternalAction: (label: String, systemImage: String)? {
        switch kind {
        case "watch":
            let platform = meta?.platform?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = platform?.isEmpty == false ? platform! : "video"
            return ("Watch \(name)", "play.rectangle.fill")
        case "screen":
            return primaryExternalURL == nil ? nil : ("Open screen note", "film.fill")
        case "hashtag":
            return ("Open hashtag", "number")
        default:
            guard primaryExternalURL != nil else { return nil }
            return ("Open link", "safari.fill")
        }
    }

    var contextChips: [String] {
        var chips: [String] = []
        for value in [
            meta?.platform,
            meta?.duration,
            meta?.creator,
            meta?.neighborhood,
            meta?.bestSeason,
            meta?.confidence,
            meta?.promptType,
        ] {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            chips.append(value)
        }
        return Array(chips.prefix(3))
    }

    var sourceDisclosureURL: URL? {
        guard let sourceURL else { return nil }
        if let primaryExternalURL,
           primaryExternalURL.absoluteString == sourceURL.absoluteString {
            return nil
        }
        return sourceURL
    }

    private static func validHTTPSURL(_ raw: String?) -> URL? {
        guard
            let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(),
            scheme == "https",
            url.host != nil
        else { return nil }

        return url
    }

    var spokenPhrase: String {
        if let originalScript = (meta?.originalScript ?? meta?.original)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !originalScript.isEmpty {
            return originalScript
        }

        return title.components(separatedBy: "·").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? title
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
        case "phrase": return ("Carry These Words", "Traveler Phrases")
        case "screen": return ("Seen Before", "Movies & Shows")
        case "watch": return ("Watch Before You Go", "City Video Trail")
        case "hashtag": return ("Follow the Locals", "Hashtags & Searches")
        case "dish": return ("Eat Like a Local", "Taste of the City")
        case "drink": return ("Order Like a Local", "What to Drink")
        case "ritual": return ("Live Like a Local", "Rituals")
        case "local_legend": return ("Local Legend", "Stories Locals Tell")
        case "first_timer_mistake": return ("Avoid This", "First-Timer Mistakes")
        case "neighborhood_decode": return ("Read the Map", "Neighborhood Decoder")
        case "photo_prompt": return ("Look Again", "Photo Field Prompts")
        case "seasonal": return ("When to Go", "Seasonal Lore")
        case "soundmark": return ("Eyes Closed", "The City's Sound")
        case "material": return ("Look Closer", "What It's Made Of")
        case "sound": return ("Turn It Up", "The City's Sound")
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
        case "screen": return 1
        case "phrase": return 2
        case "watch": return 3
        case "hashtag": return 4
        case "local_legend": return 5
        case "first_timer_mistake": return 6
        case "neighborhood_decode": return 7
        case "photo_prompt": return 8
        case "seasonal": return 9
        case "dish": return 10
        case "drink": return 11
        case "ritual": return 12
        case "soundmark": return 13
        case "material": return 14
        case "sound": return 15
        case "etiquette": return 16
        case "market": return 17
        case "number": return 18
        case "experience": return 19
        case "listen": return 20
        case "field_note": return 21
        default: return 50
        }
    }
}

/// A compact action plan synthesized from the richer city-section rows. It does
/// not invent new facts; it only elevates already-loaded Lore notes into a
/// traveler brief so "Meet City" feels guided instead of just full.
struct CityFieldBrief: Equatable {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let title: String
        let detail: String
        let systemImage: String
    }

    struct ExternalAction: Equatable {
        let label: String
        let systemImage: String
        let url: URL
    }

    let items: [Item]
    let action: ExternalAction?

    init?(sections: [CitySection]) {
        let orderedSections = sections.sorted {
            let leftSort = $0.sort ?? 100
            let rightSort = $1.sort ?? 100
            return leftSort == rightSort
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : leftSort < rightSort
        }

        func first(_ kind: String) -> CitySection? {
            orderedSections.first { $0.kind == kind }
        }

        var nextItems: [Item] = []
        if let section = first("name_origin") {
            nextItems.append(Self.item(from: section, label: "Name decoded", systemImage: "textformat.abc"))
        }
        if let section = first("phrase") {
            nextItems.append(Self.item(from: section, label: "Say first", systemImage: "quote.bubble.fill"))
        }
        if let section = first("screen") {
            nextItems.append(Self.item(from: section, label: "On screen", systemImage: "film.fill"))
        }
        if let section = first("watch") {
            nextItems.append(Self.item(from: section, label: "Prime lens", systemImage: "play.rectangle.fill"))
        }
        if let section = first("hashtag") {
            nextItems.append(Self.item(from: section, label: "Search", systemImage: "number"))
        }
        if let section = first("local_legend") {
            nextItems.append(Self.item(from: section, label: "Ask about", systemImage: "book.closed.fill"))
        }
        if let section = first("first_timer_mistake") {
            nextItems.append(Self.item(from: section, label: "Avoid", systemImage: "exclamationmark.triangle.fill"))
        }
        if let section = first("neighborhood_decode") {
            nextItems.append(Self.item(from: section, label: "Decode", systemImage: "map.fill"))
        }
        if let section = first("photo_prompt") {
            nextItems.append(Self.item(from: section, label: "Frame", systemImage: "camera.viewfinder"))
        }
        if let section = first("seasonal") {
            nextItems.append(Self.item(from: section, label: "Time it", systemImage: "calendar.badge.clock"))
        }

        guard nextItems.count >= 3 else { return nil }
        items = Array(nextItems.prefix(8))

        if let actionable = orderedSections.first(where: {
            ($0.kind == "watch" || $0.kind == "screen" || $0.kind == "hashtag") && $0.primaryExternalURL != nil
        }),
           let url = actionable.primaryExternalURL,
           let action = actionable.primaryExternalAction {
            self.action = ExternalAction(
                label: action.label,
                systemImage: action.systemImage,
                url: url
            )
        } else {
            action = nil
        }
    }

    private static func item(from section: CitySection, label: String, systemImage: String) -> Item {
        Item(
            id: section.id,
            label: label,
            title: section.title,
            detail: section.body,
            systemImage: systemImage
        )
    }
}
