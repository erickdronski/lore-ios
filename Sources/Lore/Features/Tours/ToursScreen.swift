import SwiftUI

/// Curated walking tours, listed by city, each opening a stop-by-stop
/// stepper detail.
struct ToursScreen: View {
    @State private var model = ToursModel()

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Loading tours…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView(
                        "Can't load tours",
                        systemImage: "figure.walk.motion",
                        description: Text(message)
                    )
                case .empty:
                    ContentUnavailableView(
                        "No tours yet",
                        systemImage: "figure.walk",
                        description: Text(
                            "Curated walks land with the Chicago seed — "
                            + "the Loop, the Riverwalk, Museum Campus."
                        )
                    )
                case .loaded:
                    tourList
                }
            }
            .background(LoreColor.bone100)
            .navigationTitle("Tours")
            .task { await model.load() }
        }
    }

    private var tourList: some View {
        List {
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationDestination(for: Tour.self) { tour in
            TourDetailView(tour: tour)
        }
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
}
