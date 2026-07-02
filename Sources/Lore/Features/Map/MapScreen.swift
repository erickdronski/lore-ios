import MapKit
import SwiftUI

/// The 2D living map — degraded-modes rung 3 surface (docs/05 §5) and the
/// App-Review-reviewable surface from anywhere on Earth (docs/10 §5 row 4).
/// MapKit at P0; the locked production stack is MapLibre GL Native +
/// OpenFreeMap PMTiles (docs/03 §2 `MapKitFallback`) — swap when tiles land.
///
/// This is the composed Explorer: the base map + persona-weighted pins
/// (`MapRelevance`), the Travel controls (filter chips + near-me shelf, both
/// reading the shared `MapFilterStore` / `VisitStore` from the environment),
/// and the top header that opens global search, the city switcher, and
/// Meet-the-City. City scoping is driven from the outside (the shared
/// `AppRouter.selectedCity`), so switching cities re-flies the camera and
/// refetches pins here without the tab root knowing map internals.
struct MapScreen: View {
    /// The active city slug (from the shared router). The map refetches + flies
    /// when this changes.
    let city: String
    /// Persona/interest weighting for the pins + shelf (from `PrefsCoordinator`).
    let prefs: UserPrefs?

    // Header actions — injected so the map never imports the tab structure.
    /// Open the global search sheet.
    var onOpenSearch: () -> Void = {}
    /// Open the city switcher sheet.
    var onOpenCitySwitcher: () -> Void = {}
    /// Open "Meet {City}" (the culture surface) for the current city.
    var onMeetCity: (String) -> Void = { _ in }
    /// Nudge sign-in (a visit toggle tapped while signed out).
    var onNeedsSignIn: () -> Void = {}

    @Environment(MapFilterStore.self) private var filters
    @State private var model = MapScreenModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPlaceID: String?

    /// The relevance lens for the current prefs + whether a hard filter is on.
    private var relevance: MapRelevance {
        MapRelevance(prefs: prefs, hasActiveFilter: filters.hasActiveFilter)
    }

    /// Pins after the hard filter, arranged for-you-first so blooms cascade and
    /// dimmed kinds cluster last (§3 / `MapRelevance.arrange`).
    private var visiblePlaces: [Place] {
        relevance.arrange(model.places).filter { filters.allows($0) }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedPlaceID) {
                ForEach(visiblePlaces) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        PlacePinBadge(
                            place: place,
                            weighting: relevance.weighting(for: place)
                        )
                    }
                    .tag(place.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onChange(of: selectedPlaceID) { _, newValue in
                // Pin tap — light impact (brand/ELEVATION.md §4).
                if newValue != nil { Haptics.play(.pinTap) }
            }
            .safeAreaInset(edge: .top) {
                MapHeader(
                    cityName: model.cityDisplayName(for: city),
                    onSearch: onOpenSearch,
                    onSwitchCity: onOpenCitySwitcher,
                    onMeetCity: { onMeetCity(city) }
                )
            }
            .overlay(alignment: .top) {
                if let status = model.statusLine {
                    StatusChip(text: status)
                        .padding(.top, 56)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // The composed Travel controls: filter chips over the near-me
                // shelf, both reading the environment stores. Selecting a card
                // opens the same place sheet a pin tap does.
                TravelMapControls(
                    places: model.places,
                    onSelect: { selectedPlaceID = $0.id },
                    onNeedsSignIn: onNeedsSignIn,
                    relevance: relevance
                )
            }
            .sheet(item: selectedPlaceBinding) { place in
                PlaceCardView(place: place, onMeetCity: onMeetCity)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
                    .presentationCornerRadius(24)
            }
            .navigationTitle("Lore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: city) { await model.load(city: city) }
            .onChange(of: model.cameraTarget) { _, target in
                guard let target else { return }
                withAnimation(LoreMotion.unfurl) { position = .region(target) }
            }
        }
    }

    /// Bridges Map's tag selection to a `.sheet(item:)` presentation.
    private var selectedPlaceBinding: Binding<Place?> {
        Binding(
            get: { model.places.first { $0.id == selectedPlaceID } },
            set: { newValue in selectedPlaceID = newValue?.id }
        )
    }
}

@Observable
@MainActor
final class MapScreenModel {
    var places: [Place] = []
    var errorMessage: String?
    /// The camera region to fly to when a (new) city loads. The view observes
    /// this and eases to it (§7 "flyTo eases").
    private(set) var cameraTarget: MKCoordinateRegion?

    /// City slug → display name, learned from the `city` table so the header
    /// reads "Chicago", not "chicago".
    private var cityNames: [String: String] = [:]
    /// The city the current `places` were loaded for.
    private var loadedCity: String?

    var statusLine: String? {
        if let errorMessage { return errorMessage }
        if loadedCity == nil { return "Loading the city…" }
        if places.isEmpty { return "No places published here yet" }
        return nil
    }

    /// Human city name for the header; falls back to a title-cased slug.
    func cityDisplayName(for slug: String) -> String {
        cityNames[slug] ?? slug.capitalized
    }

    func load(city: String) async {
        guard city != loadedCity else { return }
        errorMessage = nil
        do {
            // Best-effort roster (for the display name + fly-to center); a
            // failure here never blocks pins.
            async let citiesTask = try? LoreAPI.shared.cities()
            let loaded = try await LoreAPI.shared.places(city: city)
            places = loaded
            loadedCity = city

            if let cities = await citiesTask {
                cityNames = Dictionary(
                    cities.map { ($0.slug, $0.name) },
                    uniquingKeysWith: { first, _ in first }
                )
                if let match = cities.first(where: { $0.slug == city }) {
                    cameraTarget = MKCoordinateRegion(
                        center: match.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
                    )
                }
            }
            // Fall back to the centroid of loaded pins if the roster missed.
            if cameraTarget == nil, !loaded.isEmpty {
                cameraTarget = Self.regionFitting(loaded)
            }
        } catch {
            errorMessage = "Offline — pull to retry"
            loadedCity = city
        }
    }

    /// A region roughly framing all loaded pins, as a fly-to fallback.
    private static func regionFitting(_ places: [Place]) -> MKCoordinateRegion? {
        guard !places.isEmpty else { return nil }
        let lats = places.map(\.lat)
        let lngs = places.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.02, (maxLng - minLng) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Header

/// The one top-of-map header (brand/DESIGN.md §7): a Bone-on-Ink strip with the
/// current city (tap to switch), a global search entry, and the Meet-the-City
/// affordance. App chrome, so Ink/Brass — never Amber (Amber is the world's).
struct MapHeader: View {
    let cityName: String
    let onSearch: () -> Void
    let onSwitchCity: () -> Void
    let onMeetCity: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSwitchCity) {
                HStack(spacing: 6) {
                    Text(cityName)
                        .font(LoreType.display(size: 18, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LoreColor.ink600)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Current city, \(cityName)"))
            .accessibilityHint(Text("Switch cities."))

            Spacer(minLength: 8)

            Button(action: onMeetCity) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Meet \(cityName)"))

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search Lore"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// The map pin: compound render per brand/DESIGN.md §4 — Amber fill, 1.5 pt
/// Ink stroke, Ink shadow (y1 / blur 3 / 35%) — with the place emoji badged
/// in the middle. Persona weighting dims/emphasizes it (`MapRelevance`) without
/// ever removing it, and a visited pin carries the Brass seal.
struct PlacePinBadge: View {
    let place: Place
    /// The persona-relevance weighting for this pin (opacity/scale/z). Identity
    /// when there's no lens or no active filter.
    var weighting: PinWeighting = PinWeighting(
        opacity: 1, scale: 1, zPriority: 1, isRelevant: true
    )

    @Environment(VisitStore.self) private var visits
    @State private var bloomed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(LoreColor.amber)
                    .strokeBorder(LoreColor.ink, lineWidth: 1.5)
                    .shadow(
                        color: LoreColor.ink.opacity(0.35),
                        radius: 3,
                        x: 0,
                        y: 1
                    )
                Text(place.displayEmoji)
                    .font(.system(size: 15))
            }
            .frame(width: 32, height: 32)

            if visits.hasVisited(place.id) {
                VisitedPinAccent()
                    .offset(x: 4, y: -4)
            }
        }
        .scaleEffect(bloomed ? 1.0 : 0.6)
        .opacity(bloomed ? 1.0 : 0.0)
        .relevanceWeighted(weighting)
        .onAppear {
            withAnimation(LoreMotion.bloom) { bloomed = true }
        }
        .accessibilityLabel(Text(place.name))
        .accessibilityValue(Text(visits.hasVisited(place.id) ? "Visited" : ""))
    }
}

/// Passive top strip — the only top-of-screen element (brand/DESIGN.md §7).
struct StatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
