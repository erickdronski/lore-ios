import SwiftUI

/// The composition layer (integrator convenience): a single additive overlay
/// that stacks the filter chips + the near-me shelf at the bottom of the map,
/// plus the shared stores wired together, so the four Travel pieces can be
/// adopted without editing `MapScreen`.
///
/// The integrator has two adoption paths:
///
/// 1. **Overlay only**, keep the existing `MapScreen` and add
///    `.overlay(alignment: .bottom) { TravelMapControls(...) }`, passing the
///    map's loaded `places`. This lands the chips + shelf + visit toggles.
///
/// 2. **Weighted pins**, additionally read `relevance.weighting(for:)` per
///    annotation and apply `.relevanceWeighted(_:)` to `PlacePinBadge`, and
///    badge visited pins with `VisitedPinAccent`. That realizes the persona
///    dimming on the pins themselves. (`MapScreen` composes these; it isn't
///    edited here.)
///
/// The stores are created by `TravelSession` (below) so one owner holds the
/// visit set, the filter state, and the unlock bridge to the Passport.

/// The bottom controls stack: filter chips over the near-me shelf, on a soft
/// Ink-fade so text stays legible over the map (grad.ink-fade, ELEVATION §2).
struct TravelMapControls: View {
    let places: [Place]
    let onSelect: (Place) -> Void
    var onNeedsSignIn: () -> Void = {}

    @Environment(MapFilterStore.self) private var filters
    /// The Travel session, so the map can bring auto-capture up for the loaded
    /// places. Reading it here keeps `MapScreen` untouched (it already composes
    /// `TravelMapControls`); `startAutoCapture` is a no-op unless the user has
    /// opted into "Record my travels", so this changes nothing until then.
    @Environment(TravelSession.self) private var travel

    /// Relevance derived from the current prefs + whether a filter is active.
    let relevance: MapRelevance

    /// Places after the hard filter, for the shelf (pins are filtered by the
    /// map cell reading `filters.allows`).
    private var filteredPlaces: [Place] {
        places.filter { filters.allows($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            MapFilterChips()

            NearMeShelf(
                places: filteredPlaces,
                relevance: relevance,
                onSelect: onSelect,
                onNeedsSignIn: onNeedsSignIn
            )
        }
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [LoreColor.ink900.opacity(0), LoreColor.ink900.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .onAppear {
            filters.syncCategories(from: places)
            // Bring auto-capture up for whatever's loaded (no-op unless opted
            // in). The tracker registers geofences around the nearest places.
            travel.startAutoCapture(with: places)
        }
        .onChange(of: places) { _, newValue in
            filters.syncCategories(from: newValue)
            // Re-fence when the city's places change (city switch, filter load).
            travel.startAutoCapture(with: newValue)
        }
    }
}

/// One owner for the Travel stores + the unlock bridge. The integrator creates a
/// `TravelSession` high enough to outlive the map tab (e.g. alongside
/// `AuthService`), injects the stores into the environment, and forwards
/// `pendingUnlocks` to the Passport's `UnlockCelebration`.
///
/// This is the "shared notification/closure" the task asks for: a visit logged
/// anywhere (map toggle, shelf card) flows into `pendingUnlocks`, which the host
/// observes to raise the celebration overlay, the same one the Passport tab
/// uses. Whether the host routes it through `PassportModel.recomputeAndCelebrate`
/// or drops a standalone `UnlockCelebration` over the map is the host's call.
@Observable
@MainActor
final class TravelSession {
    let visits: VisitStore
    let filters: MapFilterStore
    /// The auto-capture engine (docs/26 §1). Owned here so it outlives the map
    /// tab; gated behind the default-OFF "Record my travels" opt-in, so it is a
    /// no-op until the user turns it on (the app runs exactly as today).
    let tracker: VisitTracker

    /// The queue the host raises an `UnlockCelebration` for. Set by the
    /// `VisitStore.onUnlocks` bridge; cleared by the host on dismiss.
    var pendingUnlocks: [Achievement] = []

    /// - Parameter credentials: `(userID, accessToken)` or `nil` when signed
    ///   out, usually `{ auth.session.map { ($0.user.id, $0.accessToken) } }`.
    init(credentials: @escaping () -> (userID: String, accessToken: String)?) {
        self.visits = VisitStore(credentials: credentials)
        self.filters = MapFilterStore(credentials: credentials)
        self.tracker = VisitTracker(credentials: credentials)
        // Now that the stored properties exist, `self` is fully initialized.
        // Wire the unlock bridge so a logged visit raises the celebration queue,
        // and fold an auto-captured visit into the "Been here" set so the map's
        // Brass check appears the moment the tracker collects a place.
        self.visits.onUnlocks = { [weak self] unlocked in
            self?.enqueue(unlocked)
        }
        self.tracker.onAutoVisit = { [weak self] placeID in
            self?.visits.markVisitedLocally(placeID)
        }
    }

    /// Adopt persisted prefs (persona/interests → weighting, hidden_kinds →
    /// chips) once they've loaded. Also hydrate the visit set.
    func bootstrap(prefs: UserPrefs?) async {
        filters.adopt(prefs: prefs)
        await visits.load()
    }

    /// Bring auto-capture up for the map's loaded places. No-op unless the user
    /// has opted into "Record my travels" (docs/26 §1/§3); the map integrator
    /// calls this when a city's places load.
    func startAutoCapture(with places: [Place]) {
        tracker.start(with: places)
    }

    /// A `MapRelevance` for the current prefs and filter state.
    func relevance(prefs: UserPrefs?) -> MapRelevance {
        MapRelevance(prefs: prefs, hasActiveFilter: filters.hasActiveFilter)
    }

    /// Enqueue newly-unlocked badges for the host's celebration overlay.
    func enqueue(_ unlocked: [Achievement]) {
        guard !unlocked.isEmpty else { return }
        withAnimation(LoreMotion.unfurl) {
            pendingUnlocks.append(contentsOf: unlocked)
        }
    }

    /// Clear the queue after the host's `UnlockCelebration` is dismissed.
    func clearUnlocks() {
        pendingUnlocks = []
    }
}
