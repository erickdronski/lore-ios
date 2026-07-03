import CoreLocation
import SwiftUI

/// "Around you right now" — the near-me shelf (task requirement 4, and the
/// first-night arrival flow's §5.4 answer to *"what am I surrounded by?"*). A
/// horizontal shelf of the nearest N places with **live distance labels** that
/// re-rank as the user moves, fed by `NearMeLocationProvider` and the map's
/// already-loaded `[Place]`.
///
/// Additive: the integrator overlays this at the bottom of the map (below the
/// filter chips) without editing `MapScreen`. Selecting a card calls
/// `onSelect(place)` so the host presents the same place card the map's pin tap
/// does. Each card carries an inline `VisitToggle`, so marking "been here" is
/// zero extra navigation.
///
/// Honors the persona lens and hard filter: `MapRelevance.arrange` orders the
/// candidates (for-you first, hidden kinds dropped) before the nearest-N cut, so
/// the shelf shows what's both *close* and *relevant*, never a hidden kind.
struct NearMeShelf: View {
    /// The city's places (the same array the map renders).
    let places: [Place]
    /// Persona weighting + hard filter, so the shelf respects the map's lens.
    let relevance: MapRelevance
    /// Present the place (host reuses its pin-tap sheet).
    let onSelect: (Place) -> Void
    /// Nudge sign-in when a visit toggle is tapped signed-out.
    var onNeedsSignIn: () -> Void = {}
    /// How many cards to show.
    var maxCount: Int = 8
    /// The city these places belong to — published to the home-screen widget
    /// alongside the nearest places (docs/16 §7). Defaults to the pilot city.
    var city: String = Config.defaultCity

    @State private var provider = NearMeLocationProvider()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once per shelf population so the cards cascade in (LUXURY-MOTION §6).
    @State private var appeared = false

    private var ranked: [RankedPlace] {
        NearMe.nearest(
            to: provider.location,
            among: places,
            relevance: relevance,
            limit: maxCount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if provider.location == nil {
                locationPrompt
            } else if ranked.isEmpty {
                emptyState
            } else {
                shelf
            }
        }
        .onAppear { provider.start() }
        .onDisappear { provider.stop() }
        // Publish the nearest places to the home-screen widget whenever the
        // ranking shifts (a new fix, a filter change). No-op until the App Group
        // is provisioned (docs/16 §7).
        .onChange(of: provider.location) { _, _ in
            WidgetPublisher.publishNearby(ranked, city: city)
        }
        .onChange(of: places) { _, _ in
            WidgetPublisher.publishNearby(ranked, city: city)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
            Text("Around you right now")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.bone)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: Shelf

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Cards cascade in with the shared 40 ms fade+rise (LUXURY-MOTION
                // §6). A horizontal shelf can't use the VStack `StaggeredReveal`
                // container, so we drive `StaggerChild` per card off a local flag.
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, ranked in
                    NearMeCard(
                        ranked: ranked,
                        onSelect: { onSelect(ranked.place) },
                        onNeedsSignIn: onNeedsSignIn
                    )
                    .modifier(StaggerChild(
                        index: index,
                        appeared: appeared,
                        reduceMotion: reduceMotion
                    ))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation { appeared = true }
            }
        }
    }

    // MARK: Degraded states

    private var locationPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.isDenied ? "location.slash" : "location.magnifyingglass")
                .foregroundStyle(LoreColor.amber)
            Text(provider.isDenied
                 ? "Turn on location to see what's around you."
                 : "Finding your block…")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.75))
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(LoreColor.ink800))
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        Text("No places nearby yet. Pan the map to explore.")
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.bone.opacity(0.7))
            .padding(.horizontal, 16)
    }
}

// MARK: - Card

/// One near-you card: emoji medallion, name, live distance, and an inline
/// "been here" toggle. Compact by doctrine (brand/ELEVATION.md §5b) — a taste,
/// not a wall; the full dossier is one tap via `onSelect`.
struct NearMeCard: View {
    let ranked: RankedPlace
    let onSelect: () -> Void
    var onNeedsSignIn: () -> Void = {}

    @Environment(VisitStore.self) private var visits

    private var place: Place { ranked.place }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        medallion
                        Spacer()
                        if visits.hasVisited(place.id) {
                            VisitedPinAccent()
                        }
                    }
                    Text(place.name)
                        .font(LoreType.display(size: 17, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(ranked.distanceLabel, systemImage: "figure.walk")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.amber)
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.plain)

            VisitToggle(place: place, source: .map, onNeedsSignIn: onNeedsSignIn)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 200, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(LoreColor.ink800))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(place.name), \(ranked.distanceLabel) away"))
        .accessibilityHint(Text("Opens the place. Contains a visited toggle."))
    }

    private var medallion: some View {
        Text(place.displayEmoji)
            .font(.system(size: 22))
            .frame(width: 44, height: 44)
            .background(Circle().fill(LoreColor.ink900))
            .overlay(Circle().strokeBorder(LoreColor.brass300.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Ranking

/// A place paired with its live distance from the user, for the shelf.
struct RankedPlace: Identifiable {
    let place: Place
    /// Straight-line distance from the user, meters.
    let meters: Double

    var id: String { place.id }

    /// "600 m" / "1.2 km" — reuses the scanner's shared formatter so distance
    /// labels read identically everywhere (docs/05 §5 rung 2).
    var distanceLabel: String { BearingProjector.distanceLabel(meters: meters) }
}

/// The nearest-N computation, factored out so it's pure and testable.
enum NearMe {
    /// The nearest `limit` places to `location`, after the persona lens orders
    /// candidates and the hard filter drops hidden kinds. With no `location`
    /// (permission pending), returns empty so the shelf shows its prompt.
    static func nearest(
        to location: CLLocation?,
        among places: [Place],
        relevance: MapRelevance,
        limit: Int
    ) -> [RankedPlace] {
        guard let location else { return [] }
        let allowed = places.filter { !relevance.isHidden($0) }
        let ranked = allowed
            .map { RankedPlace(place: $0, meters: location.distance(from: $0.location)) }
            .sorted { $0.meters < $1.meters }
        return Array(ranked.prefix(limit))
    }
}
