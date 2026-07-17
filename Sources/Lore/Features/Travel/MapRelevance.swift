import SwiftUI

/// The persona-weighted map overlay's brain (task requirement 3): turns
/// `InterestMap.relevanceScore` into concrete per-pin visual weighting the map
/// integrator applies to each annotation, **dimming** non-matching pins rather
/// than removing them.
///
/// Doctrine (13-CURATION-PERSONAS.md §3): *curation is weighting, never a wall.*
/// Matched pins render full-strength; unmatched pins fade toward a floor but
/// never vanish, and "show everything" is always one tap (clear the chips).
/// `hidden_kinds` is the single hard filter, honored by `isHidden`.
///
/// This is a pure value type (no view, no I/O) so it parse/compiles standalone
/// and is trivially testable: feed it a place + prefs, get back an opacity, a
/// scale, and a z-priority. The map composes these onto `PlacePinBadge` without
/// `MapScreen` needing to change shape.
struct MapRelevance {
    /// The user's curation profile. `nil` ⇒ no personalization (everything is
    /// full-strength, the pre-onboarding / signed-out map).
    let prefs: UserPrefs?

    /// Whether any category filter chips are actively narrowing the map. When
    /// nothing is selected the whole map is "on" and no dimming applies, so a
    /// fresh user never sees a half-faded map they didn't ask for.
    let hasActiveFilter: Bool

    /// After sundown (DayNightStore) the night layer re-weights the map:
    /// nightlife/haunted pins hold full glow, daytime institutions rest.
    /// Same doctrine as personas — weighting, never a wall.
    let night: Bool

    init(prefs: UserPrefs?, hasActiveFilter: Bool, night: Bool = false) {
        self.prefs = prefs
        self.hasActiveFilter = hasActiveFilter
        self.night = night
    }

    // MARK: - Night layer

    /// Tags that mark a place as part of the city's night face.
    static let nightTags: Set<String> = [
        "nightlife", "dive-bar", "jazz", "speakeasy", "comedy", "live-music",
        "bar", "night-market", "haunted", "ghost", "theater", "music-venue",
    ]

    /// Place kinds that are asleep after dark (visual rest only, still there).
    static let daytimeKinds: Set<String> = ["museum", "gallery", "library"]

    /// Whether a place belongs to the night layer.
    func isNightPlace(_ place: Place) -> Bool {
        place.tags.contains(where: Self.nightTags.contains)
    }

    // MARK: - Tunables

    /// Opacity a fully-unmatched pin fades to (never 0, it must stay tappable
    /// and legible; §3 "everything can still appear").
    static let dimmedOpacity: Double = 0.32
    /// Opacity a matched / relevant pin holds.
    static let brightOpacity: Double = 1.0
    /// A matched pin gets a subtle size bump so relevance reads at a glance.
    static let matchedScale: CGFloat = 1.0
    static let dimmedScale: CGFloat = 0.86

    /// Relevance at/above this counts as "matched" for the bright/dim split.
    /// Kept low so a single interest hit or persona-lens boost is enough to
    /// stay bright, the lens *nudges*, it doesn't gatekeep.
    static let matchThreshold: Double = 0.5

    // MARK: - Per-pin weighting

    /// The personalization score for a place (0 = not for you, higher = more).
    /// Thin pass-through to `InterestMap` so callers have one entry point.
    func score(for place: Place) -> Double {
        guard let prefs else { return 0 }
        return InterestMap.relevanceScore(place: place, prefs: prefs)
    }

    /// Whether a place clears the "matched / relevant" bar for this user.
    func isRelevant(_ place: Place) -> Bool {
        guard prefs != nil else { return true } // no lens ⇒ everything matches
        return score(for: place) >= Self.matchThreshold
    }

    /// The one hard filter: a `place.kind` the user toggled off in the chips /
    /// hid in prefs. Hidden pins should be dropped from the map entirely.
    func isHidden(_ place: Place) -> Bool {
        guard let prefs else { return false }
        return InterestMap.isHidden(place: place, prefs: prefs)
    }

    /// Opacity to render a pin at. No prefs or no active filtering ⇒ full
    /// strength; otherwise matched pins stay bright and the rest dim to a
    /// floor. At night, the night layer applies on top: night pins never dim,
    /// and daytime institutions rest at a gentle fade even with no filter.
    func opacity(for place: Place) -> Double {
        if night {
            if isNightPlace(place) { return Self.brightOpacity }
            if Self.daytimeKinds.contains(place.kind) { return 0.55 }
        }
        guard prefs != nil, hasActiveFilter else { return Self.brightOpacity }
        return isRelevant(place) ? Self.brightOpacity : Self.dimmedOpacity
    }

    /// Scale factor for a pin, a gentle emphasis for matched pins under an
    /// active filter (and for night-layer pins after dark), identity otherwise.
    func scale(for place: Place) -> CGFloat {
        if night && isNightPlace(place) { return 1.08 }
        guard prefs != nil, hasActiveFilter else { return Self.matchedScale }
        return isRelevant(place) ? Self.matchedScale : Self.dimmedScale
    }

    /// Draw priority: matched pins sit above dimmed ones so they win overlaps
    /// and cluster last (§3 "unmatched ones dim and cluster first"). Night
    /// pins take the top band after dark. Feed into `.zIndex` / ordering.
    func zPriority(for place: Place) -> Double {
        if night && isNightPlace(place) { return 2 }
        return isRelevant(place) ? 1 : 0
    }

    /// A ready-made bundle for a pin, so a map cell can read one value.
    func weighting(for place: Place) -> PinWeighting {
        PinWeighting(
            opacity: opacity(for: place),
            scale: scale(for: place),
            zPriority: zPriority(for: place),
            isRelevant: isRelevant(place)
        )
    }

    /// Order + hide places the way the map should render them: hidden kinds
    /// dropped, then relevant pins first (so staggered blooms cascade for-you
    /// → everything, and clustering drops the quiet ones first).
    func arrange(_ places: [Place]) -> [Place] {
        places
            .filter { !isHidden($0) }
            .sorted { score(for: $0) > score(for: $1) }
    }
}

/// The per-pin visual weighting a map annotation applies. Pure data, the map
/// reads it and modulates its existing `PlacePinBadge` (no `MapScreen` edit).
struct PinWeighting: Equatable {
    let opacity: Double
    let scale: CGFloat
    let zPriority: Double
    let isRelevant: Bool
}

/// A drop-in modifier the integrator can apply to any pin view to realize a
/// `PinWeighting` with the brand's motion (dim/emphasis settles, honoring
/// Reduce Motion via `LoreMotion`). Additive: `MapScreen` stays untouched; the
/// integrator wraps `PlacePinBadge` with `.relevanceWeighted(_:)`.
struct RelevanceWeightModifier: ViewModifier {
    let weighting: PinWeighting

    func body(content: Content) -> some View {
        content
            .opacity(weighting.opacity)
            .scaleEffect(weighting.scale)
            .zIndex(weighting.zPriority)
            .animation(LoreMotion.drift, value: weighting.opacity)
            .animation(LoreMotion.drift, value: weighting.scale)
    }
}

extension View {
    /// Dim / emphasize a pin per its persona-relevance weighting.
    func relevanceWeighted(_ weighting: PinWeighting) -> some View {
        modifier(RelevanceWeightModifier(weighting: weighting))
    }
}

/// A small overlay glyph an integrator can badge onto a visited pin so the
/// living map shows travel progress at a glance, a Brass seal tucked at the
/// pin's shoulder. Additive; compose over `PlacePinBadge` when
/// `VisitStore.hasVisited(place.id)` is true.
struct VisitedPinAccent: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(LoreColor.brass)
            .background(Circle().fill(LoreColor.ink).padding(-1))
            .accessibilityLabel(Text("Visited"))
    }
}
