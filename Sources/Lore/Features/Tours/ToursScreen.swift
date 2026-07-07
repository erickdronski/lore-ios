import SwiftUI

/// Curated walking tours, listed by city, each opening a stop-by-stop
/// stepper detail.
struct ToursScreen: View {
    /// The shared active city (same source the map reads). Switching it here
    /// re-scopes the whole Tours surface, the 1-Hour hero and the curated list.
    @Environment(AppRouter.self) private var router
    @State private var model = ToursModel()
    /// The generated "1 Hour In" walk, presented in a sheet once routed.
    @State private var generatedTour: Tour?
    /// The city whose walk is currently being routed (drives the hero spinner).
    @State private var generatingCity: String?
    /// The city switcher sheet (TestFlight feedback: "how does a user change
    /// the city here?").
    @State private var showCitySwitcher = false

    var body: some View {
        NavigationStack {
            List {
                madeForYouSection

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
                                    TourRow(tour: tour)
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
            // Load (and reload) the selected city's tours; switching cities in
            // the sheet re-scopes the list without leaving Tours.
            .task(id: router.selectedCity) { await model.load(city: router.selectedCity) }
        }
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
                isGenerating: generatingCity == router.selectedCity
            ) {
                let city = router.selectedCity
                generatingCity = city
                Task {
                    let tour = await model.oneHourTour(city: city)
                    generatingCity = nil
                    generatedTour = tour
                }
            }
        } header: {
            HStack(spacing: 10) {
                Text("Made for you")
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
    var isGenerating: Bool = false
    let action: () -> Void

    private var cityLabel: String {
        city.replacingOccurrences(of: "-", with: " ").capitalized
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
                    Text("1 Hour In \(cityLabel)")
                        .font(LoreType.display(size: 19, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                    Text(isGenerating ? "Routing your walk…" : "Auto-routed · a perfect hour on foot")
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
            }
        }
        .padding(.vertical, 4)
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
    /// the city's places and routes them; nil if there are too few to walk.
    func oneHourTour(city: String) async -> Tour? {
        let places = (try? await LoreAPI.shared.places(city: city)) ?? []
        return OneHourTour.generate(city: city, places: places, from: nil)
    }
}
