import CoreLocation
import Foundation

/// The scanner's **intelligence layer** — the `docs/12-SCANNER-INTELLIGENCE.md`
/// §2 resolution ladder and §3 ranking, sitting on top of `BearingProjector`'s
/// pose math. Pure value logic, no I/O and no frameworks beyond CoreLocation
/// value types, so it parses/tests without the AR stack (same doctrine as
/// `BearingProjector` and the P1 `Resolver`, docs/03 §2).
///
/// Two jobs:
/// 1. **Rank** every projected candidate by the §3 formula — proximity +
///    prominence + gaze + novelty + a persona/interest term borrowed from
///    `InterestMap.relevanceScore`, with the weights swapped per mode (§4).
/// 2. **Classify confidence** into the honest Tier A / B / C treatment (§2 +
///    docs/05 §4.2): a locked pin only when the geometry earns it, a bearing
///    chip when we know the direction but not the façade, a directional hint
///    when heading itself is noisy. The scanner would rather say "one of these
///    three" than point confidently at the wrong glass tower.
enum ScannerRanking {

    // MARK: - Confidence tiers (docs/12 §2, docs/05 §4.2)

    /// The in-camera treatment a candidate has *earned*. Never inflate: a
    /// locked pin looks different from a bearing chip on purpose (§2 honesty
    /// contract). `D` (off-map) is handled a rung up, at city resolution.
    enum Tier: Int, Comparable {
        /// **A — Locked pin.** The math clears the footprint: a landmark-scale
        /// silhouette near enough that heading error stays inside its width.
        /// Solid Amber pin anchored on the building, tap → dossier.
        case a
        /// **B — Confident chip.** Direction is trustworthy, the façade claim
        /// is not: a floating bearing chip (emoji + name + distance).
        case b
        /// **C — Directional.** Coarse only: a cardinal-cluster hint, no
        /// on-building claim at all ("The Loop's icons are that way →").
        case c

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Sensor-quality inputs that gate the tier ceiling for the whole frame.
    /// Mirrors the `σ_lat = horizontalAccuracy + d·tan(yawAccuracy)` model in
    /// docs/05 §4.2 without needing the VPS pose — compass-grade honesty.
    struct PoseQuality {
        /// Horizontal position accuracy, meters (CLLocation.horizontalAccuracy).
        let horizontalAccuracyM: Double
        /// Heading accuracy, degrees (CLHeading.headingAccuracy). Negative =
        /// invalid; treated as the worst case.
        let headingAccuracyDeg: Double
        /// True when a VPS-class fix backs the pose (ARGeoTracking coverage).
        /// P0 is always `false` — the coarse scanner never claims Tier A from
        /// footprint math alone unless the silhouette is unmistakable.
        let hasVPS: Bool

        /// Effective heading uncertainty in degrees, flooring invalid readings
        /// at the compass-fallback worst case (docs/05 §4.1 source 4: ±25°).
        var effectiveHeadingDeg: Double {
            headingAccuracyDeg < 0 ? 25 : max(headingAccuracyDeg, 1)
        }

        /// A usable coarse fix in an urban canyon (docs/05 §4.1 sources 3–4).
        static let coarseUrban = PoseQuality(
            horizontalAccuracyM: 20, headingAccuracyDeg: 18, hasVPS: false
        )
    }

    /// Predicted lateral error at a target `distance`, meters:
    /// `σ_lat = horizontalAccuracy + d · tan(yawAccuracy)` (docs/05 §4.2).
    /// This is the honesty math — it decides whether a pin would be a lie.
    static func lateralErrorMeters(distance: Double, quality: PoseQuality) -> Double {
        let yawRadians = quality.effectiveHeadingDeg * .pi / 180
        return quality.horizontalAccuracyM + distance * tan(yawRadians)
    }

    /// Approximate footprint half-width for a place, meters. Real footprints
    /// live in the P1 chunk data; here we estimate from `kind` + height so the
    /// tier math has something honest to compare against (docs/05 §4.2 note:
    /// "footprint width"). Supertall towers read wide even head-on; statues are
    /// points and can never earn a coarse-mode lock.
    static func footprintHalfWidth(for place: Place) -> Double {
        switch place.kind {
        case "statue", "sculpture", "memorial", "monument":
            return 4
        case "bridge":
            return 30
        case "park", "nature":
            return 120
        default:
            // Towers: taller → broader silhouette. Willis-class (~440 m) reads
            // ~60 m wide; a mid-rise ~15 m. Clamp to a sane band.
            let h = place.heightM ?? 40
            return min(max(h * 0.14, 12), 70)
        }
    }

    /// Classify one candidate into its earned tier (docs/05 §4.2 thresholds):
    /// - Tier A when `σ_lat < 0.5 × footprintWidth` (exact pin), **or** a VPS
    ///   fix backs it — the geometry clears the building.
    /// - Tier B up to `2 × footprintWidth` — direction good, façade not.
    /// - Tier C beyond that, or whenever heading is compass-noisy — no claim.
    ///
    /// `footprintWidth` here is the full width (2× half-width) to match the
    /// doc's "× footprint width" phrasing.
    static func tier(for projected: ProjectedPlace, quality: PoseQuality) -> Tier {
        let sigma = lateralErrorMeters(distance: projected.distance, quality: quality)
        let fullWidth = footprintHalfWidth(for: projected.place) * 2

        // Compass-only heading can never carry an on-building claim beyond a
        // literal arm's-length target (docs/05 §4.2 refuse-to-guess).
        let compassNoisy = quality.effectiveHeadingDeg > 15 && !quality.hasVPS

        if quality.hasVPS && sigma < fullWidth { return .a }
        if !compassNoisy && sigma < fullWidth * 0.5 { return .a }
        if sigma < fullWidth * 2 && !compassNoisy { return .b }
        // A place we can't stand behind on the façade is still a real bearing;
        // it degrades to a directional hint rather than vanishing.
        return .c
    }

    // MARK: - Ranking weights (docs/12 §3 + §4 modes)

    /// The §3 score weights. These are a **mode**, not constants (§4): the same
    /// corner ranks differently for a traveler vs. an architect. Derived from a
    /// persona so the caller never hand-tunes at the call site.
    struct Weights {
        var proximity: Double   // w_dist  — closer = higher, steep past 300 m
        var prominence: Double  // w_rank  — height, landmark status
        var gaze: Double        // w_gaze  — centered in the reticle
        var novelty: Double     // w_fresh — unseen-by-this-user nudge
        var context: Double     // w_ctx   — persona/interest/tour/haunted

        /// Mode weights per persona (docs/12 §4 ranking-bias column). The
        /// leading term for each mode gets the heaviest weight; the rest stay
        /// present so ranking *leans*, never forks the content (§4).
        static func forPersona(_ persona: UserPrefs.Persona) -> Weights {
            switch persona {
            case .traveler:
                // Famous icons + the one arresting fact: prominence + proximity.
                return Weights(proximity: 1.0, prominence: 1.2, gaze: 0.9, novelty: 0.3, context: 0.6)
            case .local:
                // Novelty — the thing walked past 1,000× and never known.
                return Weights(proximity: 0.9, prominence: 0.5, gaze: 0.9, novelty: 1.3, context: 0.8)
            case .architect:
                // Style/structure: dive-richness + engineering-feat tags.
                return Weights(proximity: 0.8, prominence: 1.1, gaze: 1.0, novelty: 0.3, context: 1.1)
            case .historian:
                // Deep timeline + what happened here: context + prominence.
                return Weights(proximity: 0.9, prominence: 0.9, gaze: 0.9, novelty: 0.4, context: 1.1)
            case .family:
                // Emoji-forward, one wow-fact, things to point at: gaze + fun.
                return Weights(proximity: 1.1, prominence: 1.0, gaze: 1.1, novelty: 0.5, context: 0.9)
            case .explorer:
                // Hidden gems and the roads less walked: novelty + context.
                return Weights(proximity: 0.9, prominence: 0.6, gaze: 0.9, novelty: 1.2, context: 0.9)
            case .nightlife:
                return Weights(proximity: 1.0, prominence: 0.7, gaze: 0.9, novelty: 0.7, context: 1.1)
            case .curator:
                // Everything, unfiltered: flat, honest, geometry-led.
                return Weights(proximity: 1.0, prominence: 1.0, gaze: 1.0, novelty: 0.5, context: 0.5)
            }
        }
    }

    /// The §3 register the scanner should speak in for this persona — the
    /// "voice register" column of docs/12 §4. Copy only; never a content fork.
    static func voiceRegister(for persona: UserPrefs.Persona) -> String {
        switch persona {
        case .traveler:  return "You're standing in front of"
        case .local:     return "Bet you didn't know"
        case .architect: return "Structure and span"
        case .historian: return "What happened here"
        case .family:    return "Look up, here's the wow"
        case .explorer:  return "Off the worn path"
        case .nightlife: return "After dark, here"
        case .curator:   return "Everything, unfiltered"
        }
    }

    // MARK: - Scored candidate

    /// One projected place carried through ranking, with its earned tier and
    /// final score. Wraps `ProjectedPlace` rather than replacing it so the
    /// bearing math stays the single source of pose truth.
    struct Ranked: Identifiable {
        let projected: ProjectedPlace
        let tier: Tier
        let score: Double
        /// The interests this place matched for the current user (drives the
        /// "for you" emphasis; empty for everyone else, §3 curation-nudge).
        let matchedInterests: Set<String>

        var id: String { projected.id }
        var place: Place { projected.place }
    }

    // MARK: - Scoring

    /// Proximity term: 1.0 at the user's feet, falling steeply past 300 m
    /// (docs/12 §3 "steep falloff past 300 m"). Exponential so a place at
    /// 300 m still scores ~0.37 and a 1.5 km tower barely registers on
    /// distance alone — prominence has to carry the far field.
    static func proximityScore(distance: Double) -> Double {
        exp(-distance / 300)
    }

    /// Prominence term: height + landmark/dive richness, normalized to ~[0, 1].
    /// A supertall skyline icon with a rich Layer-1 pins near 1; a plain
    /// low-rise sits low. This is what lets a distant Willis Tower still lead.
    static func prominenceScore(for place: Place) -> Double {
        var score = 0.0
        // Height: 0 at ground, ~1 by 300 m. Supertall silhouettes dominate.
        if let h = place.heightM { score += min(h / 300, 1.0) * 0.6 }
        // Landmark tags earn a flat bump.
        if place.tags.contains("skyline-icon") { score += 0.3 }
        if place.tags.contains("monument") || place.tags.contains("observation-deck") { score += 0.15 }
        // Dive richness: an authored hook means there's a payoff behind the pin.
        if place.layer1?.hook?.isEmpty == false { score += 0.15 }
        return min(score, 1.0)
    }

    /// Gaze term: how centered the place is in the reticle. 1.0 dead-center,
    /// falling off across the FOV (docs/12 §3 "what you point *at* beats what's
    /// merely near"). Uses the already-computed screen fraction so it matches
    /// exactly where the chip renders.
    static func gazeScore(screenFraction: Double) -> Double {
        // 0.5 = center. Distance from center in [0, 0.5]; invert to [0, 1].
        let offset = abs(screenFraction - 0.5)
        return max(0, 1 - offset / 0.5)
    }

    /// Novelty term: an unseen-by-this-user place gets a nudge (docs/12 §3
    /// `w_fresh`). `seenPlaceIDs` is the set the caller tracks (visited /
    /// already-tapped); unseen → 1.0, seen → 0.
    static func noveltyScore(place: Place, seenPlaceIDs: Set<String>) -> Double {
        seenPlaceIDs.contains(place.id) ? 0 : 1
    }

    /// Rank a frame of projected candidates. `prefs` supplies the persona lens
    /// (weights + the `InterestMap` context term); pass `nil` to fall back to
    /// the traveler default — the app works signed-out (docs/12 §4: chosen at
    /// onboarding, but never required to scan).
    static func rank(
        _ projected: [ProjectedPlace],
        prefs: UserPrefs?,
        quality: PoseQuality,
        seenPlaceIDs: Set<String> = []
    ) -> [Ranked] {
        let persona = prefs?.persona ?? .traveler
        let weights = Weights.forPersona(persona)

        return projected.compactMap { p -> Ranked? in
            // `hidden_kinds` is the one hard wall (docs/13 §3): drop entirely.
            if let prefs, InterestMap.isHidden(place: p.place, prefs: prefs) {
                return nil
            }

            let context: Double = prefs
                .map { InterestMap.relevanceScore(place: p.place, prefs: $0) }
                ?? 0

            let score =
                weights.proximity  * proximityScore(distance: p.distance) +
                weights.prominence * prominenceScore(for: p.place) +
                weights.gaze       * gazeScore(screenFraction: p.screenFraction) +
                weights.novelty    * noveltyScore(place: p.place, seenPlaceIDs: seenPlaceIDs) +
                weights.context    * context

            let matched = prefs
                .map { InterestMap.matchedInterests(place: p.place, prefs: $0) }
                ?? []

            return Ranked(
                projected: p,
                tier: tier(for: p, quality: quality),
                score: score,
                matchedInterests: matched
            )
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Disambiguation clustering (docs/12 §2.1 — the "stack")

    /// A cluster of candidates that fall inside one bearing cone (a dense
    /// skyline, a row of Beaux-Arts façades). The scanner shows a single stack
    /// chip with a count; tapping opens the distance-sorted, live-reordering
    /// list (docs/12 §2.1). The lead is the top-ranked member.
    struct Cluster: Identifiable {
        let members: [Ranked]
        var id: String { lead.id }
        var lead: Ranked { members[0] }
        var count: Int { members.count }
        var isStack: Bool { members.count > 1 }
        /// Center of the cone, screen fraction — where the chip renders.
        var screenFraction: Double { lead.projected.screenFraction }
    }

    /// Group ranked candidates whose bearings fall within `coneDegrees` of each
    /// other into stacks (docs/12 §2.1). Greedy by score: each cluster is
    /// seeded by the highest-scoring un-clustered candidate, then absorbs
    /// nearby-in-bearing members. Members within a cluster are distance-sorted
    /// so the stack list reads nearest-first (docs/12 §2.1).
    static func cluster(_ ranked: [Ranked], coneDegrees: Double = 8) -> [Cluster] {
        var remaining = ranked
        var clusters: [Cluster] = []

        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            var members = [seed]
            remaining.removeAll { candidate in
                let close = abs(
                    BearingProjector.angleDelta(
                        candidate.projected.bearing,
                        seed.projected.bearing
                    )
                ) <= coneDegrees
                if close { members.append(candidate) }
                return close
            }
            // Nearest-first inside the stack (the confirm-a-look list order).
            members.sort { $0.projected.distance < $1.projected.distance }
            clusters.append(Cluster(members: members))
        }

        return clusters
    }
}

// MARK: - Story proximity (docs/12 §3.1 — "meanwhile-nearby")

/// A `story` row floated at its real spot when the user's pose comes within
/// range (docs/12 §3.1: *"On this corner, 1934…"*). The scanner projects it
/// with the same bearing math as places so it can pin to the right point in
/// the FOV; it never claims a building, it marks a moment.
struct ProjectedStory: Identifiable {
    let story: Story
    let bearing: Double
    let delta: Double
    let distance: Double
    let screenFraction: Double
    let isInView: Bool

    var id: String { story.id }
    var distanceLabel: String { BearingProjector.distanceLabel(meters: distance) }
    var arrow: String { BearingProjector.arrowGlyph(delta: delta) }
}

extension ScannerRanking {
    /// Project the nearby `story` layer against the current pose, keeping only
    /// moments within `radius` meters (docs/12 §3.1: "within ~150 m"). Honors a
    /// per-frame budget so a dense historic core can't crowd the viewfinder
    /// (docs/12 open Q3) — overflow is the caller's "stories that way →".
    /// When `hauntedOnly` is set (the night/spooky toggle, §3.1 layer 3) only
    /// ghost-tagged moments float.
    static func nearbyStories(
        _ stories: [Story],
        from location: CLLocation,
        heading: Double,
        fovDegrees: Double,
        radius: Double = 150,
        budget: Int = 4,
        hauntedOnly: Bool = false
    ) -> [ProjectedStory] {
        stories
            .filter { !hauntedOnly || $0.isHaunted }
            .compactMap { story -> ProjectedStory? in
                let distance = story.distance(from: location)
                guard distance <= radius else { return nil }
                let bearing = BearingProjector.bearing(
                    from: location.coordinate,
                    to: story.coordinate
                )
                let delta = BearingProjector.angleDelta(bearing, heading)
                let fraction = BearingProjector.screenFraction(delta: delta, fovDegrees: fovDegrees)
                return ProjectedStory(
                    story: story,
                    bearing: bearing,
                    delta: delta,
                    distance: distance,
                    screenFraction: fraction,
                    isInView: abs(delta) <= fovDegrees / 2
                )
            }
            .sorted { $0.distance < $1.distance }
            .prefix(budget)
            .map { $0 }
    }
}
