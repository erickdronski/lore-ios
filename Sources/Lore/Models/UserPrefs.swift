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
        interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        hiddenKinds = try container.decodeIfPresent([String].self, forKey: .hiddenKinds) ?? []
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
        self.interests = interests
        self.hiddenKinds = hiddenKinds
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

    /// Body for `upsertPrefs`, the mutable subset the client writes back
    /// (never `user_id`; RLS derives it from the JWT). `affinity` is
    /// server-learned and omitted here.
    var upsertPayload: [String: Any] {
        [
            "persona": persona.rawValue,
            "interests": interests,
            "hidden_kinds": hiddenKinds,
            "onboarded": onboarded,
        ]
    }
}
