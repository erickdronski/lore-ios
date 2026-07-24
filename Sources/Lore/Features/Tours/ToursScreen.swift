import SwiftUI

/// Curated walking tours, listed by city, each opening a stop-by-stop
/// stepper detail.
struct ToursScreen: View {
    /// The shared active city (same source the map reads). Switching it here
    /// re-scopes the whole Tours surface, the 1-Hour hero and the curated list.
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var model = ToursModel()
    /// The paywall raised by the offline-pack button's locked state.
    @State private var showPackPaywall = false
    /// The generated "1 Hour In" walk, presented in a sheet once routed.
    @State private var generatedTour: Tour?
    /// Chosen length for the generated walk (30 / 60 / 90 minutes).
    @State private var oneHourMinutes = 60
    /// Surfaced when the 1-hour walk can't be built (too few stops, or offline).
    @State private var oneHourError: String?
    /// The city whose walk is currently being routed (drives the hero spinner).
    @State private var generatingCity: String?
    /// The city switcher sheet (TestFlight feedback: "how does a user change
    /// the city here?").
    @State private var showCitySwitcher = false

    var body: some View {
        NavigationStack {
            List {
                madeForYouSection

                // Take this city with you: pins every story, tour, and photo
                // so the walk survives subways and roaming dead zones (Lore+).
                Section {
                    CityPackButton(city: router.selectedCity) {
                        showPackPaywall = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // City passes & standing deals (Lore+): the day-planner's
                // money section. Self-hides for cities with nothing real.
                Section {
                    CityDealsSection(city: router.selectedCity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                switch model.state {
                case .loading:
                    ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
                case .failed(let message):
                    Text(message)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                case .empty:
                    Text("Curated walks are landing city by city. Your 1-hour walk above already works wherever we have stories.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                case .loaded:
                    ForEach(model.cities, id: \.self) { city in
                        Section {
                            ForEach(model.toursByCity[city] ?? []) { tour in
                                NavigationLink(value: tour) {
                                    TourRow(
                                        tour: tour,
                                        isPlus: entitlements.isPlus,
                                        userID: auth.session?.user.id
                                    )
                                }
                            }
                        } header: {
                            Text(city.capitalized)
                                .font(LoreType.displayM)
                                .foregroundStyle(LoreColor.ink)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(LoreColor.bone100)
            .navigationTitle("Tours")
            .navigationDestination(for: Tour.self) { tour in
                TourDetailView(tour: tour)
            }
            .sheet(item: $generatedTour) { tour in
                NavigationStack { TourDetailView(tour: tour) }
            }
            .sheet(isPresented: $showCitySwitcher) {
                CitySwitcherView(router: router)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPackPaywall) {
                PaywallView(entitlements: entitlements, store: store, auth: auth, context: .tours)
            }
            // Load (and reload) the selected city's tours; switching cities in
            // the sheet re-scopes the list without leaving Tours.
            .task(id: router.selectedCity) { await model.load(city: router.selectedCity) }
            .alert("Walk unavailable", isPresented: oneHourErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(oneHourError ?? "")
            }
        }
    }

    private var oneHourErrorBinding: Binding<Bool> {
        Binding(get: { oneHourError != nil }, set: { if !$0 { oneHourError = nil } })
    }

    /// City slug → display name, e.g. "san-francisco" → "San Francisco".
    private func cityLabel(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// The always-available generated walk (strategy Phase 2). Works in every
    /// seeded city even before curated tours land, so the feature is never empty.
    private var madeForYouSection: some View {
        Section {
            OneHourHero(
                city: router.selectedCity,
                minutes: oneHourMinutes,
                isGenerating: generatingCity == router.selectedCity
            ) {
                let city = router.selectedCity
                let minutes = oneHourMinutes
                generatingCity = city
                Task {
                    do {
                        if let tour = try await model.oneHourTour(city: city, durationMin: minutes) {
                            generatedTour = tour
                        } else {
                            oneHourError = "There aren't enough stops in \(cityLabel(city)) yet for a full walk. Try another city."
                        }
                    } catch {
                        oneHourError = "Couldn't build your walk. Check your connection and try again."
                    }
                    generatingCity = nil
                }
            }

            Picker("Walk length", selection: $oneHourMinutes) {
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("90 min").tag(90)
            }
            .pickerStyle(.segmented)
        } header: {
            HStack(spacing: 10) {
                Text("Build a city walk")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
                    .textCase(nil)
                Spacer(minLength: 8)
                citySwitcherChip
            }
        }
    }

    /// The Brass city chip in the section header: shows the active city and
    /// opens the switcher so Tours can be re-scoped to any city.
    private var citySwitcherChip: some View {
        Button {
            Haptics.play(.chipTap)
            showCitySwitcher = true
        } label: {
            HStack(spacing: 6) {
                Text(cityLabel(router.selectedCity))
                    .font(LoreType.display(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(LoreColor.brass700)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(LoreColor.bone200, in: Capsule())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel(Text("Current city, \(cityLabel(router.selectedCity))"))
        .accessibilityHint(Text("Switch cities to see their tours."))
    }
}

/// The featured "1 Hour In {city}" entry: an Ink medallion, the promise, and a
/// Brass go-arrow. Taps generate the walk on the fly (a brief routing spinner),
/// then push the standard tour stepper.
struct OneHourHero: View {
    let city: String
    var minutes: Int = 60
    var isGenerating: Bool = false
    let action: () -> Void

    private var cityLabel: String {
        city.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var titleText: String {
        switch minutes {
        case 30: return "30 Minutes In \(cityLabel)"
        case 90: return "90 Minutes In \(cityLabel)"
        default: return "1 Hour In \(cityLabel)"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LoreColor.ink)
                        .frame(width: 52, height: 52)
                    if isGenerating {
                        ProgressView().tint(LoreColor.amber)
                    } else {
                        Text("⏱️").font(.system(size: 26))
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(LoreType.display(size: 19, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                    Text(isGenerating ? "Routing your walk…" : "Auto-routed from published Lore stops")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(LoreColor.brass)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
}

struct TourRow: View {
    let tour: Tour
    /// Whether the viewer is a Lore+ member (drives the premium lock marker).
    var isPlus: Bool = false
    var userID: String?
    @State private var progress = TourProgressStore.Progress.empty

    var body: some View {
        HStack(spacing: 12) {
            Text(tour.displayEmoji)
                .font(.system(size: 28))
            VStack(alignment: .leading, spacing: 4) {
                Text(tour.title)
                    .font(LoreType.display(size: 18, weight: .medium))
                    .foregroundStyle(LoreColor.ink)
                if let blurb = tour.blurb {
                    Text(blurb)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .lineLimit(2)
                }
                if !tour.summaryLine.isEmpty {
                    Text(tour.summaryLine)
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.brass700)
                }
                if progress.isCompleted {
                    Label("Completed", systemImage: "checkmark.seal.fill")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass700)
                } else if let stopIndex = progress.stopIndex {
                    Label("Resume at stop \(stopIndex + 1)", systemImage: "arrow.clockwise")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.brass700)
                }
            }
            // A curated premium walk reads as Lore+ to a free member, so the
            // gate on the detail screen is never a surprise.
            if tour.isPremium && !isPlus {
                Spacer(minLength: 8)
                LockChip(label: "Lore+", showsLock: true)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            progress = TourProgressStore.progress(
                for: tour.slug,
                userID: userID,
                stopCount: tour.stops.count
            )
        }
    }
}

// MARK: - Model

@Observable
@MainActor
final class ToursModel {
    enum State {
        case loading
        case empty
        case failed(String)
        case loaded
    }

    private(set) var state: State = .loading
    private(set) var toursByCity: [String: [Tour]] = [:]
    /// The city the current `toursByCity` was loaded for, so a re-scope reloads
    /// and the same city doesn't refetch.
    private var loadedCity: String?

    var cities: [String] { toursByCity.keys.sorted() }

    /// Load the curated tours for `city`. Reloads when the city changes;
    /// re-selecting the same city is a no-op.
    func load(city: String) async {
        guard city != loadedCity else { return }
        state = .loading
        do {
            let tours = try await LoreAPI.shared.tours(city: city)
            toursByCity = Dictionary(grouping: tours, by: \.city)
            loadedCity = city
            state = tours.isEmpty ? .empty : .loaded
        } catch {
            state = .failed("Check your connection and try again.")
        }
    }

    /// Build the "1 Hour In {city}" walk on demand (strategy Phase 2). Fetches
    /// the city's places and routes them. Throws on a network failure (so the
    /// caller can distinguish "offline" from "too few stops"); returns nil when
    /// the fetch succeeds but there aren't enough stops to route a walk.
    func oneHourTour(city: String, durationMin: Int = 60) async throws -> Tour? {
        let places = try await LoreAPI.shared.places(city: city)
        return OneHourTour.generate(city: city, places: places, from: nil, durationMin: durationMin)
    }
}
