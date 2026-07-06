import SwiftUI

/// The city switcher: the live roster from `GET /city?status=eq.live&order=sort`,
/// grouped United States first, then International, each city a tappable row
/// with its emoji. A search field at the top filters the loaded roster locally;
/// once the roster outgrows what's worth loading whole, the same field falls
/// back to the `search_lore` RPC (city hits only) so it scales past the local
/// list. Tapping a city routes through the injected router (`switchCity`).
struct CitySwitcherView: View {
    /// Called with the chosen city slug. The sheet dismisses first, then invokes
    /// this, the host flies the map / refilters reads.
    let onSelect: (String) -> Void
    /// The currently-active city slug, checkmarked in the list.
    let currentCity: String?

    @Environment(\.dismiss) private var dismiss
    @State private var model = CitySwitcherModel()

    /// Hook to the shared router: taps drive `router.switchCity(to:)` and the
    /// current selection is read from `router.selectedCity`.
    init(router: AppRouter) {
        let current = router.selectedCity
        self.currentCity = current
        self.onSelect = { [weak router] slug in router?.switchCity(to: slug) }
    }

    /// Hook to an arbitrary handler (previews / tests / non-`AppRouter` hosts).
    init(currentCity: String?, onSelect: @escaping (String) -> Void) {
        self.currentCity = currentCity
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LoreColor.bone100.ignoresSafeArea()
                content
            }
            .navigationTitle("Choose a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search cities"
            )
            .onChange(of: model.query) { _, newValue in
                model.queryChanged(newValue)
            }
            .task { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            loadingSkeleton
        case .failed(let message):
            ContentUnavailableView(
                "Can't load cities",
                systemImage: "building.2.crop.circle.badge.questionmark",
                description: Text(message)
            )
        case .empty:
            ContentUnavailableView(
                "No cities yet",
                systemImage: "building.2",
                description: Text("Live cities appear here as they're chronicled.")
            )
        case .loaded:
            if model.isFiltering && model.filteredSections.allSatisfy({ $0.cities.isEmpty }) {
                ContentUnavailableView.search(text: model.query)
            } else {
                cityList
            }
        }
    }

    /// Content-shaped loading state (LUXURY-MOTION §3): city-row skeletons
    /// cascading in, no spinner.
    private var loadingSkeleton: some View {
        ScrollView {
            StaggeredReveal(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    SkeletonRow().staggerChild(index: i)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .accessibilityLabel("Loading cities")
    }

    private var cityList: some View {
        List {
            ForEach(model.filteredSections) { section in
                if !section.cities.isEmpty {
                    Section {
                        ForEach(section.cities) { city in
                            Button {
                                select(city)
                            } label: {
                                CityRow(
                                    city: city,
                                    isCurrent: city.slug == currentCity
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(LoreColor.bone50)
                        }
                    } header: {
                        Text(section.title)
                            .font(LoreType.label)
                            .tracking(0.6)
                            .foregroundStyle(LoreColor.ink600)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func select(_ city: City) {
        Haptics.play(.chipTap)
        let slug = city.slug
        dismiss()
        onSelect(slug)
    }
}

/// One city row: emoji, name, country subtitle, and a Brass checkmark when it's
/// the active city.
struct CityRow: View {
    let city: City
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(city.displayEmoji)
                .font(.system(size: 26))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(city.name)
                    .font(LoreType.display(size: 17, weight: .medium))
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(1)
                if let country = city.country, !country.isEmpty {
                    Text(CityRegion.displayCountry(country))
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LoreColor.brass700)
                    .accessibilityLabel("Current city")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Region grouping

/// US-then-International split for the switcher, plus country-code display
/// names. Kept tiny and local, the roster is small and curated; this is copy,
/// not a locale engine.
enum CityRegion: String, CaseIterable, Identifiable {
    case unitedStates
    case international

    var id: String { rawValue }

    /// Section header copy.
    var title: String {
        switch self {
        case .unitedStates: return "United States"
        case .international: return "International"
        }
    }

    /// Curated order: US first, then International.
    var sortIndex: Int {
        switch self {
        case .unitedStates: return 0
        case .international: return 1
        }
    }

    /// Which region a city's ISO country code belongs to. Missing/blank codes
    /// default to International (never crash, never drop a city).
    static func region(forCountry code: String?) -> CityRegion {
        guard let code, !code.isEmpty else { return .international }
        return code.uppercased() == "US" ? .unitedStates : .international
    }

    /// A friendly country label for the row subtitle. Falls back to the raw
    /// code for anything not spelled out here.
    static func displayCountry(_ code: String) -> String {
        switch code.uppercased() {
        case "US": return "United States"
        case "GB", "UK": return "United Kingdom"
        case "FR": return "France"
        case "DE": return "Germany"
        case "IT": return "Italy"
        case "ES": return "Spain"
        case "JP": return "Japan"
        case "CN": return "China"
        case "CA": return "Canada"
        case "MX": return "Mexico"
        case "BR": return "Brazil"
        case "AU": return "Australia"
        case "IN": return "India"
        case "AE": return "United Arab Emirates"
        case "NL": return "Netherlands"
        case "SE": return "Sweden"
        default: return code.uppercased()
        }
    }
}

/// A rendered region section, its cities in curated (`sort`) order.
struct CityRegionSection: Identifiable {
    let region: CityRegion
    let cities: [City]

    var id: String { region.id }
    var title: String { region.title }
}

// MARK: - Model

@Observable
@MainActor
final class CitySwitcherModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded
    }

    /// The live search/filter text.
    var query: String = ""

    private(set) var state: State = .loading
    /// The full loaded roster, in curated `sort` order.
    private(set) var cities: [City] = []
    /// City slugs surfaced by the `search_lore` fallback for the current query
    /// (used only when the local list is large enough to warrant it).
    private(set) var remoteMatchSlugs: Set<String>?

    private var loaded = false
    private var searchTask: Task<Void, Never>?

    /// Above this many loaded cities, a query also consults the `search_lore`
    /// RPC (city hits) so matching scales past the local roster. Below it, the
    /// local `name`/`slug`/`country` filter is exhaustive and instant.
    private let remoteSearchThreshold = 30
    private let debounce: Duration = .milliseconds(250)

    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func load() async {
        guard !loaded else { return }
        do {
            let rows = try await LoreAPI.shared.cities()
            cities = rows
            loaded = true
            state = rows.isEmpty ? .empty : .loaded
        } catch {
            state = .failed("Check your connection and try again.")
        }
    }

    /// The regions to render, each filtered by the current query. Sections with
    /// no matches are still returned (empty) so the view can decide whether to
    /// show them; `cityList` skips empty ones.
    var filteredSections: [CityRegionSection] {
        let matches = filteredCities
        let byRegion = Dictionary(grouping: matches) {
            CityRegion.region(forCountry: $0.country)
        }
        return CityRegion.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { region in
                CityRegionSection(
                    region: region,
                    cities: (byRegion[region] ?? []).sorted(by: Self.curatedOrder)
                )
            }
    }

    /// The roster narrowed to the current query. Local substring match on name
    /// / slug / country; when a remote fallback has run, its slugs are unioned
    /// in so RPC-only hits (e.g. fuzzy / synonym matches) also surface.
    private var filteredCities: [City] {
        let q = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !q.isEmpty else { return cities }

        return cities.filter { city in
            if city.name.lowercased().contains(q) { return true }
            if city.slug.lowercased().contains(q) { return true }
            if let country = city.country?.lowercased(), country.contains(q) { return true }
            if let remote = remoteMatchSlugs, remote.contains(city.slug) { return true }
            return false
        }
    }

    /// Debounced query handler. Local filtering is synchronous (recomputed via
    /// `filteredSections`); this only schedules the *remote* fallback when the
    /// roster is large enough to need it.
    func queryChanged(_ raw: String) {
        searchTask?.cancel()
        remoteMatchSlugs = nil

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cities.count >= remoteSearchThreshold, trimmed.count >= 2 else {
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.remoteSearch(trimmed)
        }
    }

    /// Consult `search_lore` for city hits and stash their slugs. Best-effort:
    /// a failure just leaves the local filter in place.
    private func remoteSearch(_ q: String) async {
        do {
            let results = try await LoreAPI.shared.search(q, maxResults: 30)
            guard !Task.isCancelled else { return }
            let current = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == q else { return }

            let slugs = results
                .filter { $0.kind == .city }
                .compactMap { $0.slug ?? $0.city }
            remoteMatchSlugs = Set(slugs)
        } catch {
            // Silent, local filter remains authoritative.
            remoteMatchSlugs = nil
        }
    }

    /// Stable city ordering within a region: curated `sort` first (nils last),
    /// then name as a tiebreak.
    private static func curatedOrder(_ a: City, _ b: City) -> Bool {
        switch (a.sort, b.sort) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.name < b.name
        }
    }
}
