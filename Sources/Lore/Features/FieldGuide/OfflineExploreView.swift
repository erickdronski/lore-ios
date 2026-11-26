import MapKit
import SwiftUI

enum OfflineExploreMode: Hashable { case map, nearby }

/// MapKit draws the streets. All brass landmarks and their details come from
/// the bundled guide. Blue points from Apple only appear after a local search.
struct OfflineExploreView: View {
    let cities: [City]
    let places: [Place]
    let followUserOnLaunch: Bool
    let onWalks: (() -> Void)?
    let onSaved: (() -> Void)?
    let onSearch: (() -> Void)?
    let onAccount: (() -> Void)?
    let onInteraction: (() -> Void)?
    let onOpen: (Place) -> Void

    @State private var citySlug: String?
    @State private var mode: OfflineExploreMode
    @State private var position: MapCameraPosition
    @State private var visible: MKCoordinateRegion
    @State private var selection: String?
    @State private var showsDirectory = false
    @State private var storiesOnly = false
    @State private var query = ""
    @State private var applePlace: AtlasMapPlace?
    @State private var locator = AtlasLocation()
    @State private var apple = AtlasAppleSearch()
    @State private var awaitingFix: Bool
    @State private var centeredOnUser = false
    @State private var screenVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    init(cities: [City], places: [Place], initialCity: String,
         initialMode: OfflineExploreMode = .map, followUserOnLaunch: Bool = false,
         onWalks: (() -> Void)? = nil, onSaved: (() -> Void)? = nil,
         onSearch: (() -> Void)? = nil, onAccount: (() -> Void)? = nil, onInteraction: (() -> Void)? = nil,
         onOpen: @escaping (Place) -> Void) {
        self.cities = cities
        self.places = places
        self.followUserOnLaunch = followUserOnLaunch
        self.onWalks = onWalks
        self.onSaved = onSaved
        self.onSearch = onSearch
        self.onAccount = onAccount
        self.onInteraction = onInteraction
        self.onOpen = onOpen
        let preferred = followUserOnLaunch ? UserDefaults.standard.string(forKey: "atlas.manualCity") : nil
        let city = cities.first { $0.slug == preferred } ?? cities.first { $0.slug == initialCity } ?? cities.first
        let center = city?.coordinate ?? CLLocationCoordinate2D(latitude: 39, longitude: -98)
        let region = Self.region(center, meters: city == nil ? 4_000_000 : 3_100)
        _visible = State(initialValue: region)
        _position = State(initialValue: .region(region))
        _citySlug = State(initialValue: city?.slug)
        _mode = State(initialValue: initialMode)
        _awaitingFix = State(initialValue: followUserOnLaunch)
    }

    var body: some View {
        Group {
            if mode == .map { atlas }
            else { OfflineNearbyFinder(places: places, onOpen: onOpen) { mode = .map } }
        }
        .background(LoreColor.bone100)
        .foregroundStyle(LoreColor.ink)
        .tint(LoreColor.brass700)
        .environment(\.colorScheme, .light)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(LoreColor.bone50, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(mode == .map ? "Lore" : "Nearby finder")
                    .font(.system(.title2, design: .serif, weight: .bold))
            }
            if mode == .map, let onAccount {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAccount) { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Account").accessibilityIdentifier("starter.account")
                }
            } else if mode == .nearby {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Map") { mode = .map }.accessibilityIdentifier("atlas.return")
                }
            }
        }
        .onAppear { screenVisible = true; resumeLocation() }
        .onDisappear { screenVisible = false; locator.stop(); apple.reset() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { locator.stop() }
            if phase == .active { resumeLocation() }
        }
        .onChange(of: mode) { _, mode in
            if mode == .map { resumeLocation() } else { locator.stop() }
        }
        .onChange(of: selection) { _, newValue in if newValue != nil { onInteraction?() } }
        .onChange(of: showsDirectory) { _, presented in if presented { onInteraction?() } }
        .onChange(of: locator.fix) { _, fix in
            guard locator.authorized, let fix else { return }
            if awaitingFix || (centeredOnUser && fix.distance(from: center) > 450) { moveToUser(fix) }
        }
        .sheet(isPresented: $showsDirectory) { directory }
        .sheet(item: $applePlace) { item in appleDetail(item) }
    }

    private var city: City? { cities.first { $0.slug == citySlug } }
    private var selected: Place? { places.first { $0.id == selection } }
    private var selectedApple: AtlasMapPlace? { apple.places.first { $0.id.uuidString == selection } }
    private var areaName: String { centeredOnUser ? "Around you" : city?.name ?? "This area" }
    private var center: CLLocation { CLLocation(latitude: visible.center.latitude, longitude: visible.center.longitude) }
    private var nearby: [Place] {
        let origin = centeredOnUser ? locator.fix ?? center : center
        let candidates = citySlug.map { slug in places.filter { $0.city == slug } }
            ?? FieldGuideRegion.localCandidates(in: places, from: origin)
        return candidates.map { ($0, $0.location.distance(from: origin)) }
            .filter { citySlug != nil || $0.1 <= FieldGuideRegion.radius }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }

    private var atlas: some View {
        VStack(spacing: 0) {
            Map(position: $position, selection: $selection) {
                if locator.authorized && (centeredOnUser || awaitingFix) { UserAnnotation() }
                ForEach(visiblePlaces) { place in
                    Marker(place.name, systemImage: place.hookText == nil ? mapSymbol(for: place.kind) : "book.fill",
                           coordinate: place.coordinate)
                        .tint(LoreColor.brass700).tag(place.id)
                }
                ForEach(apple.places) { place in
                    Marker(place.title, systemImage: "mappin", coordinate: place.coordinate)
                        .tint(.blue).tag(place.id.uuidString)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .accessibilityIdentifier("atlas.map")
            .onMapCameraChange(frequency: .onEnd) { context in
                let moved = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                    .distance(from: center)
                if position.positionedByUser { onInteraction?() }
                if position.positionedByUser && moved > 150 {
                    selection = nil
                    awaitingFix = false
                    centeredOnUser = false
                    locator.stop()
                    citySlug = nil
                    if moved > 1_000 { apple.reset() }
                }
                visible = context.region
            }
            .overlay(alignment: .topLeading) { cityMenu.padding(12) }
            .overlay(alignment: .topTrailing) { locateButton.padding(12) }

            shelf
        }
    }

    private func mapSymbol(for kind: String) -> String {
        switch kind {
        case "bridge": return "road.lanes"
        case "park", "nature": return "leaf.fill"
        case "venue": return "ticket.fill"
        case "statue", "monument": return "star.fill"
        case "stadium": return "sportscourt.fill"
        case "district", "plaza": return "square.grid.2x2.fill"
        case "market": return "basket.fill"
        case "infrastructure": return "gearshape.fill"
        default: return "building.columns.fill"
        }
    }

    private var visiblePlaces: [Place] {
        let lat = visible.center.latitude, lon = visible.center.longitude
        return places.filter {
            abs($0.lat - lat) <= visible.span.latitudeDelta &&
                abs(BearingProjector.angleDelta($0.lng, lon)) <= visible.span.longitudeDelta
        }
    }

    private var cityMenu: some View {
        Menu {
            ForEach(cities) { city in Button(city.name) { moveToCity(city) } }
        } label: {
            Label(city?.name ?? "Cities", systemImage: "building.2")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
        }.accessibilityLabel("Choose city").accessibilityIdentifier("atlas.city")
    }

    private var locateButton: some View {
        Button {
            onInteraction?()
            if locator.denied, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            else {
                awaitingFix = true
                if let fix = locator.fix, (-1...90).contains(-fix.timestamp.timeIntervalSinceNow) { moveToUser(fix) }
                locator.start(request: true)
            }
        } label: {
            Label(centeredOnUser ? "Recenter" : "Use my location", systemImage: centeredOnUser ? "location.fill" : "location")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
        }.accessibilityHint(locator.denied ? "Opens location permissions in Settings" : "Center the map on your location")
            .accessibilityIdentifier("atlas.locate")
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selected {
                Button { onOpen(selected) } label: {
                    shelfHeading(selected.name, caption: selected.teaser ?? selected.kind.capitalized, icon: "arrow.up.right")
                }.accessibilityIdentifier("atlas.selectedPlace")
            } else if let selectedApple {
                Button { applePlace = selectedApple } label: {
                    shelfHeading(selectedApple.title, caption: "Place from Apple Maps", icon: "arrow.up.right")
                }.accessibilityIdentifier("atlas.selectedApple")
            } else {
                let count = nearby.count
                Button { query = ""; storiesOnly = false; showsDirectory = true } label: {
                    shelfHeading(areaName, caption: count == 0 ? "Browse this area" :
                        "\(count) \(count == 1 ? "landmark" : "landmarks") in the field guide", icon: "list.bullet")
                }.accessibilityIdentifier("atlas.directory")
                if locator.denied {
                    Text("Location is off. Choose a city or explore the map.").font(.caption).foregroundStyle(.secondary)
                } else if locator.failed && awaitingFix {
                    Text("Waiting for a location signal. You can keep exploring.").font(.caption).foregroundStyle(.secondary)
                } else if centeredOnUser && locator.reduced {
                    Text("Showing your approximate location.").font(.caption).foregroundStyle(.secondary)
                }
                if count < 4 || apple.status != .idle { appleButton }
            }
            Divider()
            HStack {
                shortcut("Finder", "viewfinder", id: "guide.finder") { onInteraction?(); mode = .nearby }
                if let onWalks { shortcut("Walks", "figure.walk", id: "atlas.walks", action: onWalks) }
                if let onSaved { shortcut("Saved", "bookmark", id: "atlas.saved", action: onSaved) }
                if let onSearch { shortcut("Search", "magnifyingglass", id: "atlas.search", action: onSearch) }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
        .background(LoreColor.bone50)
    }

    private func shelfHeading(_ title: String, caption: String, icon: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.title2, design: .serif, weight: .semibold)).lineLimit(2)
                Text(caption).font(.subheadline).lineLimit(2).foregroundStyle(LoreColor.ink600)
            }
            Spacer()
            Image(systemName: icon).font(.headline).foregroundStyle(LoreColor.brass700)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }

    private func shortcut(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body.weight(.semibold))
                Text(title).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity, minHeight: 48)
        }.accessibilityIdentifier(id)
    }

    @ViewBuilder private var appleButton: some View {
        VStack(alignment: .leading, spacing: 3) {
            if apple.status == .ready && showsDirectory {
                Text("Results from Apple Maps")
            } else if apple.status == .ready {
                Button("View \(apple.places.count) places from Apple Maps") { showsDirectory = true }
            } else {
                Button {
                    onInteraction?()
                    let location = visible.center
                    Task { await apple.find(near: location) }
                } label: {
                    Label(apple.status == .loading ? "Searching Apple Maps…" : "Search Apple Maps nearby", systemImage: "map")
                }.disabled(apple.status == .loading)
            }
            if apple.status == .empty { Text("Apple Maps found no places here.").font(.caption) }
            if apple.status == .unavailable { Text("Apple Maps search is unavailable. Check your connection.").font(.caption) }
        }.font(.subheadline.weight(.medium)).foregroundStyle(LoreColor.brass700)
            .accessibilityIdentifier("atlas.appleSearch")
    }

    private var directory: some View {
        let landmarks = nearby
        let stories = landmarks.filter { $0.hookText != nil }
        return NavigationStack {
            List {
                if !apple.places.isEmpty {
                    Section("Apple Maps") {
                        ForEach(apple.places) { item in
                            Button(item.title) {
                                selection = item.id.uuidString
                                showsDirectory = false
                            }.accessibilityIdentifier("atlas.applePlace")
                        }
                    }
                }
                Section("Lore landmarks") {
                    if !stories.isEmpty {
                        Toggle(isOn: $storiesOnly) {
                            Label("Only places with stories", systemImage: "book.fill")
                        }.accessibilityIdentifier("atlas.onlyStories")
                    }
                    let shown = (storiesOnly && !stories.isEmpty ? stories : landmarks).filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                    }
                    ForEach(shown) { place in
                        Button {
                            selection = place.id
                            showsDirectory = false
                            onOpen(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.system(.headline, design: .serif))
                                Text(place.kind.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("atlas.place.\(place.slug)")
                    }
                    if shown.isEmpty { Text("No matching landmarks in the bundled guide.").foregroundStyle(.secondary) }
                }
                Section {
                    appleButton
                } footer: { Text("Lore’s landmark details work offline. Apple street maps and nearby search may need a connection.") }
            }
            .searchable(text: $query, prompt: "Find a landmark")
            .navigationTitle(areaName)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsDirectory = false } } }
        }.tint(LoreColor.brass700).presentationDetents([.medium, .large])
    }

    private func appleDetail(_ place: AtlasMapPlace) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Apple Maps", systemImage: "map").foregroundStyle(.secondary)
            Text(place.title).font(.system(.title, design: .serif, weight: .bold))
            if let address = place.item.placemark.title { Text(address) }
            Button {
                place.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: {
                Text("Walking directions in Maps").foregroundStyle(.white)
            }.buttonStyle(.borderedProminent)
            Button("Done") { applePlace = nil }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.medium]).tint(LoreColor.brass700)
    }

    private func resumeLocation() {
        guard screenVisible, mode == .map, scenePhase == .active else { return }
        if awaitingFix || centeredOnUser { locator.start() }
    }

    private func moveToUser(_ fix: CLLocation) {
        awaitingFix = false
        centeredOnUser = true
        citySlug = nil
        apple.reset()
        selection = nil
        let region = Self.region(fix.coordinate, meters: max(2_700, min(60_000, fix.horizontalAccuracy * 4)))
        visible = region
        position = .region(region)
    }

    private func moveToCity(_ city: City) {
        onInteraction?()
        if followUserOnLaunch { UserDefaults.standard.set(city.slug, forKey: "atlas.manualCity") }
        awaitingFix = false
        centeredOnUser = false
        citySlug = city.slug
        locator.stop()
        selection = nil
        apple.reset()
        let region = Self.region(city.coordinate, meters: 3_100)
        visible = region
        position = .region(region)
    }

    private static func region(_ coordinate: CLLocationCoordinate2D, meters: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}
