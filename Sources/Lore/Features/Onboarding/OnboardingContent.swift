import SwiftUI

/// Static content for the first-run flow, the persona presets, their default
/// interest sets, and the copy register, kept out of the views so the words
/// and the weighting live in one auditable place.
///
/// Source doctrine: `lore/docs/13-CURATION-PERSONAS.md` §1/§4 (lens + interests,
/// the preset row pre-checks a sensible interest set) and `brand/ELEVATION.md`
/// §5 (the "first night" arrival tone). Interest slugs and their data mapping
/// are owned by `InterestMap`; this file only chooses *which* interests each
/// preset seeds and how the flow reads.
enum OnboardingContent {

    // MARK: - Arrival copy (ELEVATION §5.1)

    /// The huge Fraunces headline on the arrival screen. The full stop is set in
    /// Amber (the "Chicago.", Amber full stop treatment, applied in the view).
    static let arrivalHeadline = "Every place has a story."
    /// The single supporting line under the headline.
    static let arrivalSubhead = "You're standing in 200 years of it. Point your phone at a building and Lore tells you what happened here, who built it, what burned, who walked past."

    // MARK: - Interest step copy (13 §4.1)

    static let interestsTitle = "What are you into?"
    static let interestsSubtitle = "Pick a few. We'll make the map lean toward what you love, but everything's always one tap away."
    static let personaRowTitle = "…or I'm here as a"
    /// Minimum interests before the interest step lets you continue (13 §4.1:
    /// "multi-select, 2+ to continue"). Skipping bypasses this entirely.
    static let minInterests = 2

    // MARK: - Location step copy (13 §4.2, plain-English why)

    static let locationTitle = "Find your block"
    static let locationBody = "Lore is about the ground under your feet. With your location we can show what's around you right now and point the scanner at the right buildings. We never track you in the background, only while the app is open and pointed at the world."
    static let locationAllow = "Use my location"
    static let locationSkip = "Not now"

    // MARK: - Notifications step copy (13 §4.3, optional)

    static let notificationsTitle = "A tap on the shoulder"
    static let notificationsBody = "When you wander near a place with a great story, a hidden gem, a spot that matches what you're into, we can nudge you. Rare, and only for the good stuff. Off by default; you're in control."
    static let notificationsAllow = "Turn on nudges"
    static let notificationsSkip = "Maybe later"

    // MARK: - Finish copy

    static let finishTitle = "You're set."
    static let finishBody = "The city's waiting. Point, wander, listen."
    static let finishCTA = "Start exploring"

    // MARK: - Persona presets (13 §1, six presets shown in onboarding)

    /// The onboarding preset row. Each preset picks a `UserPrefs.Persona` (the
    /// stored lens) and pre-checks a sensible interest set (13 §4.1). The six
    /// here are the ones surfaced at first run; `local` and `curator` (also in
    /// `UserPrefs.Persona`) are reachable later from Profile.
    struct Preset: Identifiable, Hashable {
        let persona: UserPrefs.Persona
        /// SF Symbol shown on the preset chip.
        let symbol: String
        /// Interest slugs (from `InterestMap.allInterests`) this preset seeds.
        let interests: [String]

        var id: UserPrefs.Persona { persona }
        /// Reuse the model's own label/tagline so copy stays in one place.
        var label: String { persona.label }
        var tagline: String { persona.tagline }
    }

    /// The six presets, in display order. Interest sets mirror the persona-lens
    /// leanings in `InterestMap.personaTagBoost` so the preset and the ranking
    /// weight agree.
    static let presets: [Preset] = [
        .init(
            persona: .traveler,
            symbol: "figure.walk.motion",
            interests: ["history", "architecture", "public_art"]
        ),
        .init(
            persona: .architect,
            symbol: "building.columns",
            interests: ["architecture", "history", "hidden_gems"]
        ),
        .init(
            persona: .family,
            symbol: "figure.2.and.child.holdinghands",
            interests: ["family", "parks_nature", "public_art"]
        ),
        .init(
            persona: .explorer,
            symbol: "map",
            interests: ["hidden_gems", "parks_nature", "history"]
        ),
        .init(
            persona: .historian,
            symbol: "book.closed",
            interests: ["history", "architecture", "haunted"]
        ),
        .init(
            persona: .nightlife,
            symbol: "moon.stars",
            interests: ["nightlife", "film_music", "trending"]
        ),
    ]

    /// The skip / "just show me the city" default (13 §4.4): the traveler lens
    /// with a broad, never-blank interest set so the map is populated but not
    /// overwhelming.
    static let skipPersona: UserPrefs.Persona = .traveler
    static let skipInterests: [String] = ["history", "architecture", "public_art", "hidden_gems"]

    /// The preset for a persona, if one is shown in onboarding.
    static func preset(for persona: UserPrefs.Persona) -> Preset? {
        presets.first { $0.persona == persona }
    }
}
