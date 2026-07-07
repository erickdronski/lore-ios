import SwiftUI

/// Curated walking tours, listed by city, each opening a stop-by-stop
/// stepper detail.
struct ToursScreen: View {
    @State private var model = ToursModel()
    /// The generated "1 Hour In" walk, presented in a sheet once routed.
    @State private var generatedTour: Tour?
    /// The city whose walk is currently being routed (drives the hero spinner).
    @State private var generatingCity: String?

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
            .task { await model.load() }
        }
    }

    /// The always-available generated walk (strategy Phase 2). Works in every
    /// seeded city even before curated tours land, so the feature is never empty.
    private var madeForYouSection: some View {
        Section {
            OneHourHero(
                city: Config.defaultCity,
                isGenerating: generatingCity == Config.defaultCity
            ) {
                generatingCity = Config.defaultCity
                Task {
                    let tour = await model.oneHourTour(city: Config.defaultCity)
                    generatingCity = nil
                    generatedTour = tour
                }
            }
        } header: {
            Text("Made for you")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.ink)
                .textCase(nil)
        }
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

    var cities: [String] { toursByCity.keys.sorted() }

    func load() async {
        guard toursByCity.isEmpty else { return }
        do {
            let tours = try await LoreAPI.shared.tours()
            toursByCity = Dictionary(grouping: tours, by: \.city)
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
