import CoreLocation
import SwiftUI
import UIKit

/// "Around you right now", the near-me shelf (task requirement 4, and the
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
    /// The city these places belong to, published to the home-screen widget
    /// alongside the nearest places (docs/16 §7). Defaults to the pilot city.
    var city: String = Config.defaultCity
    /// Current city theme, applied as a restrained room-tone on shelf cards.
    var theme: CityTheme? = nil

    @State private var provider = NearMeLocationProvider()
    @Environment(MapFilterStore.self) private var filters
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flips once per shelf population so the cards cascade in (LUXURY-MOTION §6).
    @State private var appeared = false
    /// Which of the shelf's places have a live offer — one bulk query per
    /// ranking, so a tile can wear a quiet "offers here" mark. Shown to
    /// everyone (the honest hook); the detail unlocks with Lore+.
    @State private var offerPlaceIDs: Set<String> = []

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
        .onAppear {
            // The map is mounted beneath first-run onboarding. Do not let it
            // trigger Apple's prompt before Lore shows the location rationale.
            let onboardingComplete = UserDefaults.standard.bool(
                forKey: OnboardingStore.didOnboardDefaultsKey
            )
            provider.start(requestPermission: onboardingComplete)
        }
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
        // One bulk "which of these have an offer" query per ranking. Keyed to
        // the ranked IDs so it re-runs when the shelf's places change, not on
        // every distance re-sort. Failure keeps the last known set.
        .task(id: ranked.map(\.id)) {
            let ids = ranked.map(\.id)
            guard !ids.isEmpty else { offerPlaceIDs = []; return }
            if let found = try? await LoreAPI.shared.placesWithOffers(placeIDs: ids) {
                offerPlaceIDs = found
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LoreColor.amber.opacity(0.16))
                Image(systemName: "location.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LoreColor.amber)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("LIVE FIELD NOTES")
                    .loreLabelStyle()
                    .tracking(1.1)
                    .foregroundStyle(LoreColor.brass300)
                Text("Around you right now")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
            }
            Spacer()

            if provider.location != nil, !ranked.isEmpty {
                Text("\(ranked.count) nearby")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(LoreColor.ink800))
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
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
                        hasOffer: offerPlaceIDs.contains(ranked.place.id),
                        isForYou: relevance.prefs != nil && relevance.isRelevant(ranked.place),
                        onSelect: { onSelect(ranked.place) },
                        onNeedsSignIn: onNeedsSignIn,
                        theme: theme
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: provider.isDenied ? "location.slash.fill" : "location.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LoreColor.amber)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(LoreColor.ink900))
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationPromptTitle)
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.bone)
                    Text(locationPromptMessage)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if provider.isDenied {
                Button("Open Location Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.amber)
            } else if provider.lastError != nil {
                Button("Try location again") {
                    provider.start(requestPermission: true)
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.amber)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LoreColor.ink800)
                .overlay(alignment: .trailing) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(LoreColor.brass300.opacity(0.08))
                        .padding(.trailing, 18)
                        .accessibilityHidden(true)
                }
        )
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: filters.hasActiveFilter ? "line.3.horizontal.decrease.circle" : "map")
                .foregroundStyle(LoreColor.amber)
            Text(emptyStateMessage)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if filters.hasActiveFilter {
                Button("Clear filters") { filters.clear() }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.amber)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }

    private var locationPromptTitle: String {
        if provider.isDenied { return "Location is resting" }
        if provider.lastError != nil { return "Location unavailable" }
        return "Finding your block"
    }

    private var locationPromptMessage: String {
        if provider.isDenied { return "Turn on location to reveal nearby field notes." }
        if let error = provider.lastError { return error }
        return "Measuring the closest stories and landmarks…"
    }

    private var emptyStateMessage: String {
        if filters.hasActiveFilter { return "No nearby places match this view." }
        if places.isEmpty { return "No field notes are published here yet." }
        return "You’re outside this city’s nearby range. Explore its map or switch cities."
    }
}

// MARK: - Card

/// One near-you card: emoji medallion, name, live distance, and an inline
/// "been here" toggle. Compact by doctrine (brand/ELEVATION.md §5b), a taste,
/// not a wall; the full dossier is one tap via `onSelect`.
struct NearMeCard: View {
    let ranked: RankedPlace
    /// True when this place has a live offer — draws a quiet brass mark on the
    /// medallion. The hook is honest: it only shows when an offer truly exists.
    var hasOffer: Bool = false
    /// True when the current traveler lens considers this place a match.
    var isForYou: Bool = false
    let onSelect: () -> Void
    var onNeedsSignIn: () -> Void = {}
    /// Current city theme, if curated. Used for the medallion ring and top rule.
    var theme: CityTheme? = nil

    @Environment(VisitStore.self) private var visits
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var place: Place { ranked.place }
    private var accent: Color { theme?.accentColor ?? LoreColor.brass300 }
    private var cardWidth: CGFloat { dynamicTypeSize.isAccessibilitySize ? 260 : 220 }
    private var cardMinimumHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 300 : 246 }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top) {
                        medallion
                        Spacer()
                        if isForYou {
                            Label("For you", systemImage: "sparkles")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.brass300)
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .background(Capsule().fill(LoreColor.ink900.opacity(0.78)))
                        }
                        if visits.hasVisited(place.id) {
                            VisitedPinAccent()
                        }
                    }

                    Text(kindLabel.uppercased())
                        .loreLabelStyle()
                        .tracking(1)
                        .foregroundStyle(accent)

                    Text(place.name)
                        .font(LoreType.display(size: 17, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(.leading)

                    if let hook = place.layer1?.hook, !hook.isEmpty {
                        Text(hook)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.bone.opacity(0.7))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .multilineTextAlignment(.leading)
                    }

                    proximityRow
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(cardAccessibilityLabel))
            .accessibilityHint(Text("Opens this field note"))

            Spacer(minLength: 0)

            // Marking visited here flows straight into the place, where the
            // "your lore" editor lives — so adding a lore is one gesture from
            // the shelf, not a scavenger hunt.
            VisitToggle(place: place, source: .map, onNeedsSignIn: onNeedsSignIn, onLogged: onSelect)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: cardWidth, alignment: .topLeading)
        .frame(minHeight: cardMinimumHeight, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accent.opacity(theme == nil ? 0.18 : 0.42), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(accent.opacity(theme == nil ? 0 : 0.82))
                .frame(width: 38, height: 3)
                .padding(.leading, 14)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var medallion: some View {
        ZStack {
            Circle().fill(LoreColor.ink900)
            Image(systemName: contextSymbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(accent)
            Text(place.displayEmoji)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .background(Circle().fill(LoreColor.bone50))
                .offset(x: 17, y: 16)
        }
            .frame(width: 48, height: 48)
            .overlay(Circle().strokeBorder(accent.opacity(0.55), lineWidth: 1))
            // A quiet brass "offers here" mark, only when one truly exists.
            .overlay(alignment: .bottomTrailing) {
                if hasOffer { offerMark }
            }
            .accessibilityHidden(true)
    }

    /// The offer hook: a small brass sparkles disc tucked on the medallion.
    /// Deliberately understated — a whisper, not a banner.
    private var offerMark: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(LoreColor.ink900)
            .frame(width: 18, height: 18)
            .background(Circle().fill(LoreColor.brass300))
            .overlay(Circle().strokeBorder(LoreColor.ink800, lineWidth: 1.5))
            .offset(x: 3, y: 3)
            .accessibilityLabel(Text("Offers available here"))
    }

    private var proximityRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LoreColor.ink900)
                .frame(width: 28, height: 28)
                .background(Circle().fill(LoreColor.amber))

            VStack(alignment: .leading, spacing: 1) {
                Text(proximityLabel)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                Text(ranked.distanceLabel)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.amber)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 2 ? accent : LoreColor.bone.opacity(0.28))
                        .frame(width: index == 2 ? 6 : 4, height: index == 2 ? 6 : 4)
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .accessibilityHidden(true)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [LoreColor.ink800, LoreColor.ink900],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: contextSymbol)
                    .font(.system(size: 84, weight: .thin))
                    .foregroundStyle(accent.opacity(0.07))
                    .offset(x: 16, y: -10)
                    .accessibilityHidden(true)
            }
    }

    private var proximityLabel: String {
        switch ranked.meters {
        case ..<250: return "Steps away"
        case ..<900: return "Easy walk"
        case ..<2_000: return "A short wander"
        default: return "Worth the detour"
        }
    }

    private var kindLabel: String {
        switch place.kind {
        case "statue", "sculpture": return "Public art"
        case "monument", "memorial": return "Landmark"
        case "church", "temple", "synagogue", "mosque": return "Sacred place"
        case "bar", "restaurant", "cafe", "market": return "Local flavor"
        case "museum", "gallery": return "Culture"
        case "park", "garden": return "Open air"
        default: return place.kind.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private var contextSymbol: String {
        switch place.kind {
        case "statue", "sculpture": return "figure.stand"
        case "monument", "memorial": return "building.columns.fill"
        case "bridge": return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case "park", "garden": return "leaf.fill"
        case "church", "temple", "synagogue", "mosque": return "sparkles"
        case "museum", "gallery": return "photo.artframe"
        case "bar": return "wineglass.fill"
        case "restaurant", "cafe", "market": return "fork.knife"
        case "theater", "theatre": return "theatermasks.fill"
        case "library": return "books.vertical.fill"
        default: return "building.2.fill"
        }
    }

    private var cardAccessibilityLabel: String {
        var parts = [place.name, kindLabel, "\(ranked.distanceLabel) away", proximityLabel]
        if isForYou { parts.append("Recommended for you") }
        if hasOffer { parts.append("Offers available") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Ranking

/// A place paired with its live distance from the user, for the shelf.
struct RankedPlace: Identifiable {
    let place: Place
    /// Straight-line distance from the user, meters.
    let meters: Double

    var id: String { place.id }

    /// "600 m" / "1.2 km", reuses the scanner's shared formatter so distance
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
        limit: Int,
        // "Around you right now" must mean it. If the user switched to a far city
        // while physically elsewhere, its places are thousands of km away — a
        // walking distance on those is a lie, so cap the shelf to a metro radius.
        maxMeters: Double = 50_000
    ) -> [RankedPlace] {
        guard let location else { return [] }
        let allowed = places.filter { !relevance.isHidden($0) }
        let ranked = allowed
            .map { RankedPlace(place: $0, meters: location.distance(from: $0.location)) }
            .filter { $0.meters <= maxMeters }
            .sorted { $0.meters < $1.meters }
        return Array(ranked.prefix(limit))
    }
}
