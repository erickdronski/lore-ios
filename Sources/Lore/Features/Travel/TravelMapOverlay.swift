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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Collapsed hides the chips + shelf so the map gets the whole screen
    /// (TestFlight feedback: "I should be able to minimize / collapse / hide
    /// this whole section"). Drag the handle down to hide, tap it to bring it
    /// back. Persisted so the map remembers the choice.
    @AppStorage("lore.map.nearMeCollapsed") private var collapsed = false

    /// Relevance derived from the current prefs + whether a filter is active.
    let relevance: MapRelevance

    /// Places after the hard filter, for the shelf (pins are filtered by the
    /// map cell reading `filters.allows`).
    private var filteredPlaces: [Place] {
        places.filter { filters.allows($0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            handle

            if !collapsed {
                VStack(spacing: 12) {
                    MapFilterChips()

                    NearMeShelf(
                        places: filteredPlaces,
                        relevance: relevance,
                        onSelect: onSelect,
                        onNeedsSignIn: onNeedsSignIn
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            // The ink fade only exists to keep the shelf text legible over the
            // map. When collapsed there is nothing to protect, so it disappears
            // entirely, leaving just the floating "Around you" pill over a clean
            // map (no lingering grey haze).
            Group {
                if !collapsed {
                    LinearGradient(
                        colors: [LoreColor.ink900.opacity(0), LoreColor.ink900.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        )
        .gesture(collapseDrag)
        .onAppear { filters.syncCategories(from: places) }
        .onChange(of: places) { _, newValue in
            filters.syncCategories(from: newValue)
        }
    }

    /// The grip: a grab bar plus, when collapsed, a labelled "Around you" pill so
    /// it's obvious how to bring the shelf back. Tap toggles; drag toggles too.
    private var handle: some View {
        Button {
            setCollapsed(!collapsed)
        } label: {
            HStack(spacing: 8) {
                if collapsed {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LoreColor.amber)
                    Text("Around you")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone)
                }
                Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LoreColor.bone.opacity(0.85))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "Show places around you" : "Hide places around you")
    }

    /// Drag the handle/panel down to collapse, up to expand.
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                if value.translation.height > 28 { setCollapsed(true) }
                else if value.translation.height < -28 { setCollapsed(false) }
            }
    }

    private func setCollapsed(_ value: Bool) {
        guard value != collapsed else { return }
        Haptics.play(.chipTap)
        withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { collapsed = value }
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

    /// The queue the host raises an `UnlockCelebration` for. Set by the
    /// `VisitStore.onUnlocks` bridge; cleared by the host on dismiss.
    var pendingUnlocks: [Achievement] = []

    /// - Parameter credentials: `(userID, accessToken)` or `nil` when signed
    ///   out, usually `{ auth.session.map { ($0.user.id, $0.accessToken) } }`.
    init(credentials: @escaping () -> (userID: String, accessToken: String)?) {
        self.visits = VisitStore(credentials: credentials)
        self.filters = MapFilterStore(credentials: credentials)
        // Now that both stored properties exist, `self` is fully initialized —
        // wire the unlock bridge so a logged visit raises the celebration queue.
        self.visits.onUnlocks = { [weak self] unlocked in
            self?.enqueue(unlocked)
        }
    }

    /// Adopt persisted prefs (persona/interests → weighting, hidden_kinds →
    /// chips) once they've loaded. Also hydrate the visit set.
    func bootstrap(prefs: UserPrefs?) async {
        filters.adopt(prefs: prefs)
        await visits.load()
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
