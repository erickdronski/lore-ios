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

        enum CodingKeys: String, CodingKey {
            case website
            case sourceURL = "source_url"
            case videoURL = "video_url"
            case youtubeURL = "youtube_url"
            case tiktokURL = "tiktok_url"
            case instagramURL = "instagram_url"
            case hashtagURL = "hashtag_url"
        }

        init(
            website: String? = nil,
            sourceURL: String? = nil,
            videoURL: String? = nil,
            youtubeURL: String? = nil,
            tiktokURL: String? = nil,
            instagramURL: String? = nil,
            hashtagURL: String? = nil
        ) {
            self.website = website
            self.sourceURL = sourceURL
            self.videoURL = videoURL
            self.youtubeURL = youtubeURL
            self.tiktokURL = tiktokURL
            self.instagramURL = instagramURL
            self.hashtagURL = hashtagURL
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
                ?? sourceURL
        }
    }

    var primaryExternalAction: (label: String, systemImage: String)? {
        switch kind {
        case "watch":
            let platform = meta?.platform?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = platform?.isEmpty == false ? platform! : "video"
            return ("Watch \(name)", "play.rectangle.fill")
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
        case "phrase": return 1
        case "watch": return 2
        case "hashtag": return 3
        case "dish": return 4
        case "drink": return 5
        case "ritual": return 6
        case "local_legend": return 7
        case "first_timer_mistake": return 8
        case "neighborhood_decode": return 9
        case "photo_prompt": return 10
        case "seasonal": return 11
        case "soundmark": return 12
        case "material": return 13
        case "sound": return 14
        case "screen": return 15
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
