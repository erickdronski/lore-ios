import Foundation

/// Row shape of the `user_prefs` table, the onboarding-set curation profile
/// (13-CURATION-PERSONAS.md): a primary lens plus multi-select interests that
/// weight (never wall) the map, near-you shelf, scanner, and dossiers. Own row
/// only, via RLS.
/// `GET /rest/v1/user_prefs` (with a user bearer token)
///
/// Live columns: `user_id`, `persona`, `interests[]`, `hidden_kinds[]`,
/// `affinity` (jsonb tag→weight map the app learns), `onboarded`.
struct UserPrefs: Codable, Identifiable, Hashable {
    let userID: String
    /// The primary lens chosen at onboarding, sets interest defaults and the
    /// docent copy register. `traveler` when skipped.
    let persona: Persona
    /// The real curation signal (`architecture`, `history`, `nightlife`, …).
    /// Raw tag-interest slugs; map to data via `InterestMap`.
    let interests: [String]
    /// Hard "not interested" `place.kind`s the user toggled off, a wall, not
    /// a weight (the only hard filter in the persona system).
    let hiddenKinds: [String]
    /// Learned tag→tap affinity (`{ "art-deco": 0.7, … }`) that silently nudges
    /// relevance. A flexible bag so the shape can evolve server-side.
    let affinity: JSONValue?
    /// True once onboarding wrote prefs; gates the first-night arrival flow.
    let onboarded: Bool

    /// One row per user.
    var id: String { userID }

    enum CodingKeys: String, CodingKey {
        case persona, interests, affinity, onboarded
        case userID = "user_id"
        case hiddenKinds = "hidden_kinds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        persona = try container.decodeIfPresent(Persona.self, forKey: .persona) ?? .traveler
        interests = Self.unique(try container.decodeIfPresent([String].self, forKey: .interests) ?? [])
        hiddenKinds = Self.unique(try container.decodeIfPresent([String].self, forKey: .hiddenKinds) ?? [])
        affinity = try container.decodeIfPresent(JSONValue.self, forKey: .affinity)
        onboarded = try container.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
    }

    init(
        userID: String,
        persona: Persona = .traveler,
        interests: [String] = [],
        hiddenKinds: [String] = [],
        affinity: JSONValue? = nil,
        onboarded: Bool = false
    ) {
        self.userID = userID
        self.persona = persona
        self.interests = Self.unique(interests)
        self.hiddenKinds = Self.unique(hiddenKinds)
        self.affinity = affinity
        self.onboarded = onboarded
    }

    /// The eight onboarding lenses (13 §1). Each biases the scanner's ranking
    /// weights and the copy register (12 §4).
    enum Persona: String, Codable, Hashable, CaseIterable {
        case traveler
        case local
        case architect
        case historian
        case family
        case explorer
        case nightlife
        case curator

        /// Forward-compatible: unknown personas fall back to `.traveler`
        /// (the documented skip default).
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Persona(rawValue: raw) ?? .traveler
        }

        var label: String {
            switch self {
            case .traveler: return "Traveler"
            case .local: return "Local"
            case .architect: return "Architect"
            case .historian: return "Historian"
            case .family: return "Family"
            case .explorer: return "Explorer"
            case .nightlife: return "Night Owl"
            case .curator: return "Curator"
            }
        }

        /// One-line "I'm here as a…" onboarding subtitle.
        var tagline: String {
            switch self {
            case .traveler: return "Show me the icons and the one great fact."
            case .local: return "Surprise me with what I walk past every day."
            case .architect: return "Style, structure, and who built it."
            case .historian: return "The deep timeline and what happened here."
            case .family: return "Kid-friendly wonder and things to point at."
            case .explorer: return "Hidden gems and the roads less walked."
            case .nightlife: return "Where the city comes alive after dark."
            case .curator: return "Everything, unfiltered. I'll decide."
            }
        }

        var symbolName: String {
            switch self {
            case .traveler: return "suitcase.fill"
            case .local: return "building.2.fill"
            case .architect: return "ruler.fill"
            case .historian: return "clock.fill"
            case .family: return "figure.2.and.child.holdinghands"
            case .explorer: return "safari.fill"
            case .nightlife: return "moon.stars.fill"
            case .curator: return "sparkles.rectangle.stack.fill"
            }
        }

        var defaultInterestIDs: [String] {
            switch self {
            case .traveler: return ["architecture", "history", "hidden_gems", "parks_nature", "public_art"]
            case .local: return ["hidden_gems", "nightlife", "film_music", "public_art"]
            case .architect: return ["architecture", "history", "public_art"]
            case .historian: return ["history", "architecture", "haunted"]
            case .family: return ["family", "parks_nature", "public_art", "sports"]
            case .explorer: return ["hidden_gems", "parks_nature", "history", "public_art"]
            case .nightlife: return ["nightlife", "film_music", "haunted", "hidden_gems"]
            case .curator: return UserPrefs.interestCatalog.map(\.id)
            }
        }
    }

    struct InterestOption: Identifiable, Hashable {
        let id: String
        let label: String
        let symbolName: String
        let detail: String
    }

    static let interestCatalog: [InterestOption] = [
        .init(id: "architecture", label: "Architecture", symbolName: "building.columns.fill", detail: "Facades, structures, and skyline icons"),
        .init(id: "history", label: "History", symbolName: "scroll.fill", detail: "Founding eras and turning points"),
        .init(id: "parks_nature", label: "Parks & nature", symbolName: "leaf.fill", detail: "Green spaces, trails, and waterfronts"),
        .init(id: "hidden_gems", label: "Hidden gems", symbolName: "diamond.fill", detail: "The non-obvious, beyond the tourist line"),
        .init(id: "film_music", label: "Film & music", symbolName: "music.note.list", detail: "Where scenes and songs were made"),
        .init(id: "public_art", label: "Public art", symbolName: "paintpalette.fill", detail: "Murals, monuments, and street sculpture"),
        .init(id: "nightlife", label: "Nightlife", symbolName: "wineglass.fill", detail: "Bars, jazz, and after-dark stories"),
        .init(id: "family", label: "Family", symbolName: "figure.2.and.child.holdinghands", detail: "Kid-friendly wonder and open spaces"),
        .init(id: "sports", label: "Sports", symbolName: "sportscourt.fill", detail: "Ballparks, arenas, and local legends"),
        .init(id: "haunted", label: "Haunted", symbolName: "moon.haze.fill", detail: "Ghost stories and hushed folklore"),
    ]

    static var knownInterestIDs: Set<String> {
        Set(interestCatalog.map(\.id))
    }

    /// Interests as a `Set` for fast membership checks in relevance scoring.
    var interestSet: Set<String> { Set(interests) }

    /// Hidden kinds as a `Set`.
    var hiddenKindSet: Set<String> { Set(hiddenKinds) }

    /// The learned affinity weight for a tag, if the app has recorded one.
    func affinityWeight(for tag: String) -> Double {
        if case .object(let dict)? = affinity, case .number(let w)? = dict[tag] {
            return w
        }
        return 0
    }

    func updating(persona: Persona, interests: [String]) -> UserPrefs {
        UserPrefs(
            userID: userID,
            persona: persona,
            interests: interests,
            hiddenKinds: hiddenKinds,
            affinity: affinity,
            onboarded: true
        )
    }

    /// Body for `upsertPrefs`, the mutable subset the client writes back.
    ///
    /// `user_id` MUST be sent: the column is `uuid NOT NULL` with no default,
    /// so RLS does *not* derive it (the policy only checks `user_id =
    /// auth.uid()` — a check cannot populate a value). Omitting it fails the
    /// INSERT with 23502 before `ON CONFLICT` is ever reached. `affinity` is
    /// server-learned and omitted here.
    ///
    /// `includingHiddenKinds` exists because PostgREST's merge-duplicates only
    /// merges columns present in the payload. Onboarding does not own the
    /// category filters, so it must omit them — otherwise finishing first-run
    /// on iOS would blank whatever the traveler configured on web.
    func upsertPayload(includingHiddenKinds: Bool = true) -> [String: Any] {
        var body: [String: Any] = [
            "user_id": userID,
            "persona": persona.rawValue,
            "interests": interests,
            "onboarded": onboarded,
        ]
        if includingHiddenKinds { body["hidden_kinds"] = hiddenKinds }
        return body
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }
}
