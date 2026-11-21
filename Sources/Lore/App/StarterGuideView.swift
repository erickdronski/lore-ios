import Foundation
import SwiftUI

struct StarterCatalog: Decodable {
    let cities: [City]
    let places: [Place]
    let dives: [Dive]

    static let bundled: StarterCatalog? = {
        guard let url = Bundle.main.url(forResource: "LoreStarterCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StarterCatalog.self, from: data)
    }()
}

private enum StarterPage: Hashable {
    case city(String)
    case place(String)
}

struct StarterGuideView: View {
    let checking: Bool
    let tried: Bool
    let preferred: Bool
    @Binding var pendingLink: URL?
    let retry: () -> Void
    @State private var path: [StarterPage] = []
    @State private var query = ""
    @State private var account = false
    @State private var linkUnavailable = false
    @State private var savedIDs: Set<String> = []
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let catalog = StarterCatalog.bundled {
                    home(catalog)
                        .navigationDestination(for: StarterPage.self) { page in
                            switch page {
                            case .city(let slug):
                                if let city = catalog.cities.first(where: { $0.slug == slug }) {
                                    cityPage(city, catalog)
                                }
                            case .place(let id):
                                if let place = catalog.places.first(where: { $0.id == id }) {
                                    StarterPlaceDetail(place: place, cityName: catalog.cities.first { $0.slug == place.city }?.name ?? place.city,
                                                       dive: catalog.dives.first { $0.placeID == id },
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
            .navigationTitle("Starter Guide")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { account = true } label: { Label("Account", systemImage: "person.crop.circle") }
                        .accessibilityIdentifier("starter.account")
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
            guard url.host != "map" else { path = []; return }
            let ref = url.lastPathComponent
            if url.host == "place", let place = StarterCatalog.bundled?.places.first(where: {
                $0.id.caseInsensitiveCompare(ref) == .orderedSame || $0.slug == ref
            }) {
                path = [.city(place.city), .place(place.id)]
            } else { linkUnavailable = true }
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

    private func home(_ catalog: StarterCatalog) -> some View {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cities = catalog.cities.filter { term.isEmpty || $0.name.localizedCaseInsensitiveContains(term) }
        let matches = term.isEmpty ? [] : catalog.places.filter { $0.name.localizedCaseInsensitiveContains(term) }
        return List {
            Section {
                Text("Explore the cities and landmarks included with Lore. These stories are stored on your device.")
                    .font(.body).accessibilityIdentifier("starter.home")
                TextField("Search cities and places", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("starter.search")
            }
            if term.isEmpty && !savedIDs.isEmpty {
                Section("Saved on this device") {
                    ForEach(catalog.places.filter { savedIDs.contains($0.id) }) { placeLink($0) }
                }
            }
            if !cities.isEmpty {
                Section("Cities") {
                    ForEach(cities) { city in
                        NavigationLink(value: StarterPage.city(city.slug)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(city.name).font(.system(.headline, design: .serif))
                                Text("\(catalog.places.filter { $0.city == city.slug }.count) places")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("starter.city.\(city.slug)")
                    }
                }
            }
            if !matches.isEmpty { Section("Places") { ForEach(matches) { placeLink($0) } } }
            if cities.isEmpty && matches.isEmpty { Text("No matches in the Starter Guide.") }
            Section {
                Button(checking ? "Checking connection…" : (preferred ? "Open full catalog" : "Retry connection"), action: retry)
                    .disabled(checking)
            } footer: {
                Text(tried ? "The full catalog is still unavailable. You can keep exploring these places." :
                     (preferred ? "You are browsing the guide stored on this device." : "The full catalog and account sync are currently unavailable."))
            }
        }.scrollContentBackground(.hidden).background(LoreColor.bone).environment(\.colorScheme, .light)
    }

    private func cityPage(_ city: City, _ catalog: StarterCatalog) -> some View {
        List {
            Section("Places to explore") {
                ForEach(catalog.places.filter { $0.city == city.slug }) { placeLink($0) }
            }
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
    let saved: Bool
    let toggleSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(cityName).font(.headline).foregroundStyle(LoreColor.brass700)
                Text(place.name).font(.system(.largeTitle, design: .serif, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if let teaser = place.teaser { Text(teaser).font(.title3) }
                if let narrative = dive?.narrative { Text(narrative).lineSpacing(4) }
                if let url = dive?.links.sourceRecordURL ?? dive?.links.websiteURL {
                    Link(destination: url) { Label(dive?.source ?? url.host ?? "Read the source", systemImage: "book") }
                        .accessibilityIdentifier("starter.sources")
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
    }
}
