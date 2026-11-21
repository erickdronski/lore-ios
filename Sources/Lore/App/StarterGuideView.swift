import Foundation
import SwiftUI

struct StarterCatalog: Decodable {
    let cities: [City]
    let places: [Place]
    let dives: [Dive]
    let tours: [Tour]
    let placesByCity: [String: [Place]]
    let placesByID: [String: Place]
    let divesByID: [String: Dive]
    let sources: [String: PlaceSource]

    struct PlaceSource: Decodable {
        let id: String
        let source_url: URL?
        let source_name: String?
        let geom_source_url: URL?
    }
    enum CodingKeys: String, CodingKey { case cities, places, dives, tours }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cities = try values.decode([City].self, forKey: .cities)
        places = try values.decode([Place].self, forKey: .places)
        dives = try values.decode([Dive].self, forKey: .dives)
        tours = try values.decode([Tour].self, forKey: .tours)
        placesByCity = Dictionary(grouping: places, by: \.city)
        placesByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        divesByID = Dictionary(dives.map { ($0.placeID, $0) }, uniquingKeysWith: { first, _ in first })
        let records = try values.decode([PlaceSource].self, forKey: .places)
        sources = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static let bundled: StarterCatalog? = {
        guard let url = Bundle.main.url(forResource: "LoreStarterCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StarterCatalog.self, from: data)
    }()
}

private enum StarterPage: Hashable {
    case atlas(String, nearby: Bool)
    case walks(String?)
    case guide
    case saved
    case cities
    case city(String)
    case place(String)
}

struct StarterGuideView: View {
    let checking: Bool
    let tried: Bool
    @Binding var pendingLink: URL?
    let retry: () -> Void
    @State private var path: [StarterPage] = []
    @State private var query = ""
    @State private var lastDiscovery: String?
    @State private var account = false
    @State private var linkUnavailable = false
    @State private var savedIDs: Set<String> = []
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog = StarterCatalog.bundled {
                    OfflineExploreView(cities: catalog.cities, places: catalog.places, initialCity: Config.defaultCity,
                                       followUserOnLaunch: true,
                                       onWalks: { path.append(.walks(nil)) }, onSaved: { path.append(.saved) },
                                       onSearch: { path.append(.guide) }, onAccount: { account = true }) {
                        path.append(.place($0.id))
                    }
                        .navigationDestination(for: StarterPage.self) { page in
                            switch page {
                            case .atlas(let city, let nearby):
                                OfflineExploreView(cities: catalog.cities, places: catalog.places, initialCity: city,
                                                   initialMode: nearby ? .nearby : .map) {
                                    path.append(.place($0.id))
                                }
                            case .walks(let city):
                                OfflineWalksView(tours: catalog.tours, places: catalog.places, dives: catalog.dives,
                                                 initialCity: city, cities: catalog.cities)
                            case .guide:
                                home(catalog).navigationTitle("Field guide")
                            case .saved:
                                savedPage(catalog)
                            case .cities:
                                List(catalog.cities) { city in cityLink(city, catalog) }.navigationTitle("City index")
                            case .city(let slug):
                                if let city = catalog.cities.first(where: { $0.slug == slug }) {
                                    cityPage(city, catalog)
                                }
                            case .place(let id):
                                if let place = catalog.placesByID[id] {
                                    StarterPlaceDetail(place: place, cityName: catalog.cities.first { $0.slug == place.city }?.name ?? place.city,
                                                       dive: catalog.divesByID[id], source: catalog.sources[id],
                                                       saved: savedIDs.contains(id)) { toggleSaved(id) }
                                        .id(auth.session?.user.id)
                                }
                            }
                        }
                } else {
                    ContentUnavailableView("Guide unavailable", systemImage: "book.closed",
                                           description: Text("Please reinstall Lore or contact support."))
                }
            }
        }
        .onChange(of: auth.session?.user.id, initial: true) { _, _ in
            savedIDs = Set(UserDefaults.standard.stringArray(forKey: savesKey) ?? [])
        }
        .sheet(isPresented: $account) { StarterAccountView() }
        .onChange(of: pendingLink, initial: true) { _, url in
            guard let url else { return }
            pendingLink = nil
            guard let catalog = StarterCatalog.bundled else { return }
            let parts = url.pathComponents.filter { $0 != "/" }
            let city = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "city" }?.value?.lowercased()
            switch (url.host?.lowercased(), parts.count) {
            case ("map", 0):
                if let city, catalog.placesByCity[city] != nil { path = [.atlas(city, nearby: false)] }
                else { path = [] }
            case ("place", 1):
                if let place = catalog.places.first(where: {
                    $0.id.caseInsensitiveCompare(parts[0]) == .orderedSame || $0.slug == parts[0]
                }) { path = [.place(place.id)] } else { linkUnavailable = true }
            case ("tour", 1):
                if let tour = catalog.tours.first(where: { $0.slug == parts[0] }) {
                    path = [.walks(tour.city)]
                } else { linkUnavailable = true }
            default:
                break
            }
        }
        .alert("Available with the full catalog", isPresented: $linkUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("This link is outside the guide stored on your device.") }
    }

    private var savesKey: String { "lore.starter.saved." + (auth.session?.user.id ?? "guest") }

    private func toggleSaved(_ id: String) {
        if savedIDs.contains(id) { savedIDs.remove(id) } else { savedIDs.insert(id) }
        UserDefaults.standard.set(savedIDs.sorted(), forKey: savesKey)
    }

    @ViewBuilder
    private func savedPage(_ catalog: StarterCatalog) -> some View {
        let places = catalog.places.filter { savedIDs.contains($0.id) }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        Group {
            if places.isEmpty {
                ContentUnavailableView("No saved places yet", systemImage: "bookmark",
                                       description: Text("Open a pin on the map and tap Save to find it here."))
            } else {
                List(places) { placeLink($0) }
            }
        }.navigationTitle("Saved places")
    }

    private func home(_ catalog: StarterCatalog) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cities = catalog.cities.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
        let matches = term.isEmpty ? [] : catalog.places.filter { $0.name.localizedCaseInsensitiveContains(term) }
        return List {
            if term.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        Image("ChicagoRiverArchive").resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 136).clipped()
                            .accessibilityLabel("Steamboat passing the State Street bridge in Chicago")
                        Link("Chicago River, 1900–1915 · Library of Congress",
                             destination: URL(string: "https://www.loc.gov/item/2016818012/")!)
                            .font(.caption).foregroundStyle(LoreColor.bone).padding(10)
                    }.background(LoreColor.ink).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("starter.home")
                }
            }
            Section {
                TextField("Search cities and places", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("starter.search")
            }
            if term.isEmpty {
                Section("Explore") {
                    NavigationLink(value: StarterPage.atlas(Config.defaultCity, nearby: true)) {
                        Label("Find a landmark nearby", systemImage: "viewfinder")
                    }.accessibilityIdentifier("guide.finder")
                    NavigationLink(value: StarterPage.atlas(Config.defaultCity, nearby: false)) {
                        Label("Explore the atlas", systemImage: "map")
                    }.accessibilityIdentifier("guide.atlas")
                    if !catalog.tours.isEmpty {
                        NavigationLink(value: StarterPage.walks(nil)) { Label("Start a city walk", systemImage: "figure.walk") }
                            .accessibilityIdentifier("guide.walks")
                    }
                    Button {
                        let choices = catalog.dives.filter { $0.placeID != lastDiscovery }
                        if let id = (choices.randomElement() ?? catalog.dives.first)?.placeID {
                            lastDiscovery = id
                            path.append(.place(id))
                        }
                    } label: { Label("Surprise me with a story", systemImage: "shuffle") }
                }
            }
            if term.isEmpty && !savedIDs.isEmpty {
                Section("Saved on this device") {
                    ForEach(catalog.places.filter { savedIDs.contains($0.id) }) { placeLink($0) }
                }
            }
            if !cities.isEmpty {
                Section("Cities") {
                    ForEach(cities.prefix(term.isEmpty ? 5 : 50)) { city in cityLink(city, catalog) }
                    if term.isEmpty && cities.count > 5 {
                        NavigationLink("All \(cities.count) cities", value: StarterPage.cities)
                    }
                }
            }
            if !matches.isEmpty {
                Section("Places") {
                    ForEach(matches.prefix(50)) { placeLink($0) }
                    if matches.count > 50 { Text("Refine your search to see more places.").font(.footnote) }
                }
            }
            if cities.isEmpty && matches.isEmpty { Text("No matches in the field guide.") }
            Section {
                Button(checking ? "Checking connection…" : "Open online catalog", action: retry)
                    .disabled(checking)
            } footer: {
                Text(tried ? "Online services are currently unavailable. You can keep exploring the map." : "The field guide is stored on this device.")
            }
        }.scrollContentBackground(.hidden).background(LoreColor.bone).environment(\.colorScheme, .light)
    }

    private func cityLink(_ city: City, _ catalog: StarterCatalog) -> some View {
        NavigationLink(value: StarterPage.city(city.slug)) {
            HStack {
                Text(city.name).font(.system(.headline, design: .serif))
                Spacer()
                Text("\(catalog.placesByCity[city.slug]?.count ?? 0) places")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("starter.city.\(city.slug)")
    }

    private func cityPage(_ city: City, _ catalog: StarterCatalog) -> some View {
        let places = catalog.placesByCity[city.slug] ?? []
        let stories = places.filter { catalog.divesByID[$0.id] != nil }
        return List {
            Section {
                NavigationLink("See places on the map", value: StarterPage.atlas(city.slug, nearby: false))
                if catalog.tours.contains(where: { $0.city == city.slug }) {
                    NavigationLink("Walk this city", value: StarterPage.walks(city.slug))
                }
            }
            if !stories.isEmpty { Section("Stories to discover") { ForEach(stories) { placeLink($0) } } }
            let markers = places.filter { catalog.divesByID[$0.id] == nil }
            if !markers.isEmpty { Section("Atlas places") { ForEach(markers) { placeLink($0) } } }
        }.scrollContentBackground(.hidden).background(LoreColor.bone)
            .environment(\.colorScheme, .light).navigationTitle(city.name)
    }

    private func placeLink(_ place: Place) -> some View {
        NavigationLink(value: StarterPage.place(place.id)) {
            VStack(alignment: .leading, spacing: 5) {
                Text(place.name).font(.system(.headline, design: .serif))
                if let teaser = place.teaser { Text(teaser).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("starter.place.\(place.slug)")
    }
}

private struct StarterPlaceDetail: View {
    let place: Place
    let cityName: String
    let dive: Dive?
    let source: StarterCatalog.PlaceSource?
    @State private var narration = NarrationService()
    let saved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(cityName).font(.headline).foregroundStyle(LoreColor.brass700)
                Text(place.name).font(.system(.largeTitle, design: .serif, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if let teaser = place.teaser { Text(teaser).font(.title3) }
                if let narrative = dive?.narrative {
                    Button {
                        if narration.isActive { narration.stop() } else { narration.speakDossier(narrative) }
                    } label: {
                        Label(narration.isActive ? "Stop reading" : "Listen to the story", systemImage: narration.isActive ? "stop.fill" : "speaker.wave.2")
                    }
                    Text(narrative).lineSpacing(4)
                } else {
                    Text(place.kind.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                    if let year = place.layer1?.yearBuilt { Text("Built in \(String(year))") }
                    if let architect = place.layer1?.architect { Text(architect) }
                    if let style = place.layer1?.style { Text(style) }
                }
                if let url = dive?.links.sourceRecordURL ?? dive?.links.websiteURL ?? source?.source_url, url.scheme == "https" {
                    Link(destination: url) { Label(dive?.source ?? source?.source_name ?? url.host ?? "Read the source", systemImage: "book") }
                        .accessibilityIdentifier("starter.sources")
                }
                if let url = source?.geom_source_url, url.scheme == "https", url != source?.source_url {
                    Link("Map coordinates · Wikidata", destination: url).font(.footnote)
                }
                if let dive, !dive.timeline.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Timeline").font(.headline)
                        ForEach(dive.timeline) { event in
                            Text("\(String(event.year)) · \(event.title)")
                            if let detail = event.detail { Text(detail).font(.subheadline) }
                        }
                    }
                }
                Divider()
                if let url = URL(string: "https://maps.apple.com/?daddr=\(place.lat),\(place.lng)&dirflg=w") {
                    Link("Walking directions in Maps", destination: url)
                }
                Button(action: toggleSaved) {
                    Label(saved ? "Saved on this device" : "Save place on this device", systemImage: saved ? "bookmark.fill" : "bookmark")
                }
            }.frame(maxWidth: 680, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.background(LoreColor.bone).foregroundStyle(LoreColor.ink)
            .tint(LoreColor.brass700).navigationBarTitleDisplayMode(.inline)
            .onDisappear { narration.stop() }
    }
}
