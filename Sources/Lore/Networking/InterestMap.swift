import Foundation

/// The interest → data mapping and persona relevance weighting from
/// `lore/docs/13-CURATION-PERSONAS.md` §2–4. **App config, not DB** (the doc's
/// §2 note): the interest→match table is tuned here without a migration.
///
/// Curation is weighting, never a wall (§3): matched pins render prominent,
/// unmatched ones dim and cluster first, but everything can still appear, and
/// "show everything" is always one tap. `hidden_kinds` is the one hard filter.
enum InterestMap {

    /// The canonical interest slugs shown as onboarding chips (13 §1/§2), in
    /// display order.
    static let allInterests: [String] = [
        "architecture",
        "history",
        "parks_nature",
        "nightlife",
        "film_music",
        "family",
        "sports",
        "haunted",
        "public_art",
        "hidden_gems",
        "trending",
    ]

    /// How each interest maps onto the tags a place already carries (13 §2).
    /// `hidden_gems` and `trending` are computed (density / flag), so they hold
    /// no tag list here, see `matches(place:interest:)`.
    static let interestTags: [String: [String]] = [
        "architecture": [
            "art-deco", "beaux-arts", "brutalist", "neo-gothic", "modernist",
            "gothic-revival", "skyline-icon", "engineering-feat",
        ],
        "history": [
            "founding-era", "gilded-age", "survivor", "monument",
        ],
        "parks_nature": [
            "green-space", "forest", "waterfront", "riverfront",
        ],
        "nightlife": [
            "nightlife", "dive-bar", "jazz", "speakeasy", "comedy",
        ],
        "film_music": [
            "film-famous", "music-history", "music-venue", "movie-palace",
        ],
        "family": [
            "family-friendly", "public-art", "observation-deck",
        ],
        "sports": [
            "stadium", "ballpark", "arena", "sports",
        ],
        "haunted": [
            "haunted-lore", "ghost",
        ],
        "public_art": [
            "public-art",
        ],
    ]

    /// How each interest maps onto `place.kind` values (13 §2).
    static let interestKinds: [String: [String]] = [
        "parks_nature": ["park", "nature"],
        "nightlife": ["venue"],
        "family": ["park"],
        "sports": ["stadium"],
        "public_art": ["statue", "mural"],
    ]

    /// Display metadata for the map filter chips (13 §3) and onboarding.
    struct InterestMeta {
        let slug: String
        let label: String
        let emoji: String
    }

    static let interestMeta: [String: InterestMeta] = [
        "architecture": .init(slug: "architecture", label: "Architecture", emoji: "🏛️"),
        "history": .init(slug: "history", label: "History", emoji: "📜"),
        "parks_nature": .init(slug: "parks_nature", label: "Parks & Nature", emoji: "🌳"),
        "nightlife": .init(slug: "nightlife", label: "Nightlife", emoji: "🍸"),
        "film_music": .init(slug: "film_music", label: "Film & Music", emoji: "🎬"),
        "family": .init(slug: "family", label: "Family", emoji: "👨‍👩‍👧"),
        "sports": .init(slug: "sports", label: "Sports", emoji: "🏟️"),
        "haunted": .init(slug: "haunted", label: "Haunted", emoji: "👻"),
        "public_art": .init(slug: "public_art", label: "Public Art", emoji: "🎨"),
        "hidden_gems": .init(slug: "hidden_gems", label: "Hidden Gems", emoji: "💎"),
        "trending": .init(slug: "trending", label: "Trending", emoji: "🔥"),
    ]

    static func meta(for interest: String) -> InterestMeta {
        interestMeta[interest]
            ?? InterestMeta(slug: interest, label: interest.capitalized, emoji: "📍")
    }

    // MARK: - Matching

    /// Whether a place satisfies a single interest. Tag/kind interests check
    /// the mapping tables; the two computed interests use place signals:
    /// - `trending` → the `trending` tag (the view's flag surfaces as a tag),
    /// - `hidden_gems` → non-obvious places (not `skyline-icon`) with a rich
    ///   `story`/tag footprint (13 §2: "low-trending + high-story-density").
    static func matches(place: Place, interest: String) -> Bool {
        switch interest {
        case "trending":
            return place.tags.contains("trending")
        case "hidden_gems":
            let obvious = place.tags.contains("skyline-icon") || place.tags.contains("trending")
            return !obvious && place.tags.count >= 2
        default:
            if let tags = interestTags[interest], !Set(tags).isDisjoint(with: place.tags) {
                return true
            }
            if let kinds = interestKinds[interest], kinds.contains(place.kind) {
                return true
            }
            return false
        }
    }

    /// The set of a user's interests this place matches, drives whether a pin
    /// renders prominent vs. dimmed.
    static func matchedInterests(place: Place, prefs: UserPrefs) -> Set<String> {
        var hits: Set<String> = []
        for interest in prefs.interests where matches(place: place, interest: interest) {
            hits.insert(interest)
        }
        return hits
    }

    // MARK: - Persona weighting

    /// Per-persona tag boosts (13 §4: each mode biases the ranking). A tag in
    /// this map adds to a place's relevance for that persona even when the user
    /// didn't explicitly pick the matching interest, the lens itself leans.
    static let personaTagBoost: [UserPrefs.Persona: [String]] = [
        .traveler: ["skyline-icon", "monument", "observation-deck"],
        .local: ["hidden", "survivor", "dive-bar"],
        .architect: ["engineering-feat", "art-deco", "beaux-arts", "brutalist", "modernist"],
        .historian: ["founding-era", "gilded-age", "monument", "survivor"],
        .family: ["family-friendly", "public-art", "observation-deck"],
        .explorer: ["waterfront", "riverfront", "hidden"],
        .nightlife: ["nightlife", "jazz", "speakeasy", "dive-bar", "comedy"],
        .curator: [],
    ]

    // Relevance-score weights (13 §3 `w_persona` term; kept modest so curation
    // *nudges* rather than dominates proximity/prominence in the full formula).

    /// Weight per explicitly-matched interest.
    static let interestWeight: Double = 1.0
    /// Weight for a persona-lens tag boost.
    static let personaWeight: Double = 0.5
    /// Weight applied to a tag's learned affinity (0…1) from `user_prefs.affinity`.
    static let affinityWeight: Double = 0.75

    /// The persona/interest relevance contribution for a place (the `w_persona`
    /// term in the scanner's ranking formula, 12 §3 / 13 §3). Higher = more
    /// "for you"; unmatched places score 0 here (they still render, just quiet).
    ///
    /// This is *only* the personalization term, callers combine it with
    /// proximity, prominence, gaze, and novelty for the final rank.
    static func relevanceScore(place: Place, prefs: UserPrefs) -> Double {
        var score = 0.0

        // Explicit interests (the real signal, §2).
        score += Double(matchedInterests(place: place, prefs: prefs).count) * interestWeight

        // Persona lens boost (§4): does this place carry a tag the lens leans on?
        if let boostTags = personaTagBoost[prefs.persona] {
            let overlap = Set(boostTags).intersection(place.tags)
            if !overlap.isEmpty {
                score += personaWeight
            }
        }

        // Learned affinity (§1, silent learning): sum weighted tag affinities.
        for tag in place.tags {
            let w = prefs.affinityWeight(for: tag)
            if w > 0 { score += w * affinityWeight }
        }

        return score
    }

    /// Whether a place should be hard-hidden for this user (§3: `hidden_kinds`
    /// is the one wall). Everything else is weighting, never removal.
    static func isHidden(place: Place, prefs: UserPrefs) -> Bool {
        prefs.hiddenKindSet.contains(place.kind)
    }
}
