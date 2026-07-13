import MapKit
import SwiftUI

/// The 2D living map, degraded-modes rung 3 surface (docs/05 §5) and the
/// App-Review-reviewable surface from anywhere on Earth (docs/10 §5 row 4).
/// MapKit at P0; the locked production stack is MapLibre GL Native +
/// OpenFreeMap PMTiles (docs/03 §2 `MapKitFallback`), swap when tiles land.
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

    // Header actions, injected so the map never imports the tab structure.
    /// Open the global search sheet.
    var onOpenSearch: () -> Void = {}
    /// Open the city switcher sheet.
    var onOpenCitySwitcher: () -> Void = {}
    /// Open "Meet {City}" (the culture surface) for the current city.
    var onMeetCity: (String) -> Void = { _ in }
    /// Nudge sign-in (a visit toggle tapped while signed out).
    var onNeedsSignIn: () -> Void = {}

    @Environment(MapFilterStore.self) private var filters
    /// Read here (a normal view that inherits the environment) so the pin
    /// annotations receive `isVisited` as a plain value, never reading the
    /// Observable environment inside the MapKit-hosted annotation (which crashes).
    @Environment(VisitStore.self) private var visits
    /// Read to gate the header's "locate me" control: finding yourself on the
    /// map is a signed-in feature (founder steer: gate it so we can track and
    /// store the user's location).
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = MapScreenModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPlaceID: String?
    /// Apple Maps registers (founder steer: Apple Maps base, 3D is critical).
    /// `satellite` swaps the Ink standard style for hybrid imagery; `dimensional`
    /// pitches the camera into the 3D / Flyover read (the cinematic payoff).
    @State private var satellite = false
    @State private var dimensional = false
    // Day/night + 2D/3D, mirroring the web map controls (docs/17 §2.4). These
    // drive the native MapLibre map (LoreMapLibreView); the MapKit map ignores
    // them for now. Night + tilted is Lore's signature first impression, the
    // same defaults the web map persists to.
    @State private var mapMode: LoreMapLibreView.Mode = .night
    @State private var mapViewMode: LoreMapLibreView.ViewMode = .tilted

    /// The relevance lens for the current prefs + whether a hard filter is on.
    private var relevance: MapRelevance {
        MapRelevance(prefs: prefs, hasActiveFilter: filters.hasActiveFilter)
    }

    /// Pins after the hard filter, arranged for-you-first so blooms cascade and
    /// dimmed kinds cluster last (§3 / `MapRelevance.arrange`).
    private var visiblePlaces: [Place] {
        relevance.arrange(model.places).filter { filters.allows($0) }
    }

    /// True while a place sheet is presented, drives the map's recede (dim +
    /// blur) so the focused surface floats above it (LUXURY-MOTION §4).
    private var cardOpen: Bool { selectedPlaceID != nil }

    var body: some View {
        NavigationStack {
            baseMap
            // Depth behind an open card (LUXURY-MOTION §4): the map recedes —
            // dims to a scrim + a soft blur, so the focused place sheet floats.
            // Reduce Motion keeps the dim (a still tint is safe) but drops blur.
            .blur(radius: cardOpen && !reduceMotion ? 2 : 0)
            .overlay {
                Rectangle()
                    .fill(LoreColor.ink950.opacity(cardOpen ? 0.45 : 0))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: cardOpen)
            .onChange(of: selectedPlaceID) { _, newValue in
                // Pin tap, light impact (brand/ELEVATION.md §4).
                if newValue != nil { Haptics.play(.pinTap) }
            }
            .safeAreaInset(edge: .top) {
                MapHeader(
                    cityName: model.cityDisplayName(for: city),
                    onLocate: locateMe,
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
            .overlay(alignment: .topTrailing) {
                mapControls
                    .padding(.top, 110)
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
            .onChange(of: model.cameraTargetKey) { _, _ in
                guard let target = model.cameraTarget else { return }
                // The fly-to eases on `spring.smooth`, a settled camera glide,
                // no overshoot (LUXURY-MOTION §2, §7 "flyTo eases").
                withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
                    position = .region(target)
                }
            }
        }
    }

    /// The base map surface. MapKit is the default (Config.useMapLibreMap ==
    /// false) so the app builds and runs today; flip the flag after the
    /// MapLibre SDK compiles on device to get the flagship native map (docs/17
    /// + docs/22). Both surfaces feed the SAME `selectedPlaceID` selection, so
    /// every surrounding modifier (sheet, recede, haptics) is shared unchanged.
    @ViewBuilder
    private var baseMap: some View {
        if Config.useMapLibreMap {
            LoreMapLibreView(
                places: visiblePlaces,
                mode: mapMode,
                viewMode: mapViewMode,
                cameraTarget: model.cameraTarget?.center,
                onSelectPlace: { selectedPlaceID = $0 }
            )
            .ignoresSafeArea()
        } else {
            Map(position: $position, selection: $selectedPlaceID) {
                ForEach(Array(visiblePlaces.enumerated()), id: \.element.id) { index, place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        PlacePinBadge(
                            place: place,
                            weighting: relevance.weighting(for: place),
                            index: index,
                            isSelected: selectedPlaceID == place.id,
                            isVisited: visits.hasVisited(place.id)
                        )
                    }
                    .tag(place.id)
                }
            }
            .mapStyle(mapKitStyle)
        }
    }

    /// Bridges Map's tag selection to a `.sheet(item:)` presentation.
    private var selectedPlaceBinding: Binding<Place?> {
        Binding(
            get: { model.places.first { $0.id == selectedPlaceID } },
            set: { newValue in selectedPlaceID = newValue?.id }
        )
    }

    // MARK: Apple Maps registers (Ink / Satellite / 3D)

    /// The Apple Maps style for the current registers. `pointOfInterestFilter =
    /// .excludingAll` is the single line that makes it read as OUR map, not
    /// Apple's, only Lore's pins populate. 3D lifts elevation to realistic so
    /// Flyover geometry stands up under the pitched camera.
    private var mapKitStyle: MapStyle {
        let elevation: MapStyle.Elevation = dimensional ? .realistic : .flat
        return satellite
            ? .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
            : .standard(elevation: elevation, pointsOfInterest: .excludingAll)
    }

    /// The floating register controls: a 3D/flat toggle and an Ink/Satellite
    /// toggle. Quiet and top-trailing; 3D is the moment people screen-record.
    private var mapControls: some View {
        VStack(spacing: 10) {
            mapControlButton(
                system: dimensional ? "view.2d" : "view.3d",
                on: dimensional,
                label: dimensional ? "Flatten map" : "3D map"
            ) { toggleDimensional() }

            mapControlButton(
                system: satellite ? "map.fill" : "globe.americas.fill",
                on: satellite,
                label: satellite ? "Standard map" : "Satellite map"
            ) {
                Haptics.play(.chipTap)
                satellite.toggle()
            }
        }
        .padding(.trailing, 14)
    }

    private func mapControlButton(
        system: String, on: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LoreColor.ink)
                .frame(width: 42, height: 42)
                .background(
                    on ? AnyShapeStyle(LoreColor.amber) : AnyShapeStyle(.ultraThinMaterial),
                    in: Circle()
                )
                .overlay(Circle().strokeBorder(LoreColor.ink.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }

    /// The header "locate me" tap. Finding yourself on the map is a signed-in
    /// feature (founder steer: gate it so we can track + store where users are);
    /// signed out, it nudges sign-in instead of silently doing nothing.
    private func locateMe() {
        guard auth.isSignedIn else {
            Haptics.play(.chipTap)
            onNeedsSignIn()
            return
        }
        centerOnUser()
        // TODO(backend): persist a location ping here once the `user_location`
        // table + authenticated write land, so the signed-in locate feature is
        // tracked (founder steer). The gate + recenter ship now.
    }

    /// Follow the user's live location. MapKit resolves + tracks the fix; if
    /// location isn't authorized yet it eases to the current city frame so the
    /// tap is never a dead end. Authorization is already requested by the
    /// near-me shelf / scanner, so the button lights the map up in place.
    private func centerOnUser() {
        Haptics.play(.chipTap)
        let fallback: MapCameraPosition = model.cameraTarget.map { .region($0) } ?? .automatic
        withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
            position = .userLocation(fallback: fallback)
        }
    }

    /// Pitch into 3D (or flatten) around the current city centre with a settled
    /// spring, the cinematic-arrival read (LUXURY-MOTION §2, §7).
    private func toggleDimensional() {
        Haptics.play(.chipTap)
        dimensional.toggle()
        let center = model.cameraTarget?.center
        withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
            if dimensional, let center {
                position = .camera(MapCamera(
                    centerCoordinate: center,
                    distance: 1_500,
                    heading: 0,
                    pitch: 60
                ))
            } else if let region = model.cameraTarget {
                position = .region(region)
            }
        }
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

    /// An `Equatable` projection of `cameraTarget` for SwiftUI `onChange`, which
    /// requires an `Equatable` value and `MKCoordinateRegion` isn't one.
    var cameraTargetKey: String? {
        guard let r = cameraTarget else { return nil }
        return "\(r.center.latitude),\(r.center.longitude),\(r.span.latitudeDelta),\(r.span.longitudeDelta)"
    }

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
            errorMessage = "Offline. Check your connection."
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
/// affordance. App chrome, so Ink/Brass, never Amber (Amber is the world's).
struct MapHeader: View {
    let cityName: String
    /// Center the map on the user (gated to signed-in upstream).
    var onLocate: () -> Void = {}
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

            // Locate me: center the map on the user's live position. Amber (the
            // world's color) marks it as "you on the map"; gated to signed-in
            // upstream so tapping it signed-out nudges sign-in.
            Button(action: onLocate) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.55), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show my location on the map"))

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

/// The map pin: compound render per brand/DESIGN.md §4, Amber fill, 1.5 pt
/// Ink stroke, Ink shadow (y1 / blur 3 / 35%), with the place emoji badged
/// in the middle. Persona weighting dims/emphasizes it (`MapRelevance`) without
/// ever removing it, and a visited pin carries the Brass seal.
struct PlacePinBadge: View {
    let place: Place
    /// The persona-relevance weighting for this pin (opacity/scale/z). Identity
    /// when there's no lens or no active filter.
    var weighting: PinWeighting = PinWeighting(
        opacity: 1, scale: 1, zPriority: 1, isRelevant: true
    )
    /// This pin's position in the for-you-first arrangement, drives the
    /// near→far landing cascade on a city switch (LUXURY-MOTION §6).
    var index: Int = 0
    /// True while this pin's place sheet is open, the selected pin lifts with a
    /// spring so a tap reads as "this one" (LUXURY-MOTION §5 pin scale).
    var isSelected: Bool = false
    /// Whether the user has visited this place. Passed in from `MapScreen` (which
    /// reads `VisitStore` from the environment) rather than read here: a Map
    /// annotation is hosted in a separate view tree that does NOT inherit the
    /// `@Environment` Observable objects, so reading `@Environment(VisitStore.self)`
    /// inside a pin crashes (EXC_BREAKPOINT) when annotations rebuild on a city
    /// switch. Passing a plain value keeps the seal without the crash.
    var isVisited: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

            if isVisited {
                VisitedPinAccent()
                    .offset(x: 4, y: -4)
            }
        }
        // Landing: scale 0.6→1 on `spring.bounce` with a near→far stagger. The
        // selected pin then springs up to 1.18× so a tapped pin lifts out of the
        // field. Reduce Motion drops both transforms (a crossfade only).
        .scaleEffect(pinScale)
        .opacity(bloomed ? 1.0 : 0.0)
        .relevanceWeighted(weighting)
        // Selection re-runs on its own spring so it never fights the landing.
        .animation(LoreSpring.bounce(reduceMotion: reduceMotion), value: isSelected)
        // A city switch tears down these pins (keyed by place id) and remounts
        // the new city's set, so `.onAppear` is the fresh-field landing: each pin
        // blooms 0.6→1 on `spring.bounce`, staggered near→far (LUXURY-MOTION §6).
        .onAppear {
            if reduceMotion {
                bloomed = true
            } else {
                withAnimation(LoreSpring.bounce.delay(LoreMotion.staggerDelay(index: index))) {
                    bloomed = true
                }
            }
        }
        .accessibilityLabel(Text(place.name))
        .accessibilityValue(Text(isVisited ? "Visited" : ""))
    }

    /// Rest 0.6 → landed 1.0 → selected 1.18 (Reduce Motion: no scale, always 1).
    private var pinScale: CGFloat {
        if reduceMotion { return 1 }
        if !bloomed { return 0.6 }
        return isSelected ? 1.18 : 1.0
    }
}

/// Passive top strip, the only top-of-screen element (brand/DESIGN.md §7).
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
