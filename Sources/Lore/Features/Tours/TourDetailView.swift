import SwiftUI

/// One tour as a stop stepper: progress rail, current stop's place card
/// content + curator note, previous/next controls.
struct TourDetailView: View {
    let tour: Tour
    @State private var model = TourDetailModel()
    @State private var stopIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if tour.stops.isEmpty {
                    ContentUnavailableView(
                        "No stops yet",
                        systemImage: "mappin.slash",
                        description: Text("This tour hasn't been routed.")
                    )
                } else {
                    progressRail
                    stopCard
                    stepperControls
                }
            }
            .padding(16)
        }
        .background(LoreColor.bone100)
        .navigationTitle(tour.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(city: tour.city) }
    }

    private var currentStop: TourStop? {
        guard tour.stops.indices.contains(stopIndex) else { return nil }
        return tour.stops[stopIndex]
    }

    private var currentPlace: Place? {
        guard let currentStop else { return nil }
        return model.place(id: currentStop.placeID)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(tour.displayEmoji).font(.system(size: 32))
                Text(tour.title)
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.ink)
            }
            if let blurb = tour.blurb {
                Text(blurb)
                    .font(LoreType.hook)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tour.summaryLine.isEmpty {
                Text(tour.summaryLine)
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass700)
            }
        }
    }

    /// Amber node rail — one dot per stop, filled up to the current one.
    private var progressRail: some View {
        HStack(spacing: 6) {
            ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, _ in
                Circle()
                    .fill(index <= stopIndex ? LoreColor.amber : LoreColor.bone300)
                    .strokeBorder(
                        index <= stopIndex ? LoreColor.ink : LoreColor.bone300,
                        lineWidth: 1
                    )
                    .frame(width: 12, height: 12)
                    .onTapGesture {
                        withAnimation(LoreMotion.tap) { stopIndex = index }
                    }
            }
            Spacer()
            Text("Stop \(stopIndex + 1) of \(tour.stops.count)")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    @ViewBuilder
    private var stopCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let place = currentPlace {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(place.displayEmoji).font(.system(size: 28))
                    Text(place.name)
                        .font(LoreType.displayL)
                        .foregroundStyle(LoreColor.ink)
                    Spacer()
                    if let year = place.layer1?.yearBuilt {
                        YearChip(year: year)
                    }
                }
                if let hook = place.layer1?.hook {
                    Text(hook)
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if model.isLoading {
                ProgressView()
            } else if let stop = currentStop {
                Text("Place \(stop.placeID)")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
            }

            if let note = currentStop?.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12))
                        .foregroundStyle(LoreColor.brass700)
                    Text(note)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 14))
    }

    private var stepperControls: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(LoreMotion.unfurl) { stopIndex -= 1 }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .background(LoreColor.bone200, in: Capsule())
            .foregroundStyle(LoreColor.ink)
            .disabled(stopIndex == 0)

            Button {
                withAnimation(LoreMotion.unfurl) { stopIndex += 1 }
            } label: {
                Label("Next stop", systemImage: "chevron.right")
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .background(LoreColor.ink, in: Capsule())
            .foregroundStyle(LoreColor.bone)
            .disabled(stopIndex >= tour.stops.count - 1)
        }
    }
}

// MARK: - Model

/// Resolves stop `place_id`s against the city's `place_explore` rows.
@Observable
@MainActor
final class TourDetailModel {
    private var placesByID: [String: Place] = [:]
    private(set) var isLoading = false

    func place(id: String) -> Place? { placesByID[id] }

    func load(city: String) async {
        guard placesByID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let places = try? await LoreAPI.shared.places(city: city) {
            placesByID = Dictionary(
                uniqueKeysWithValues: places.map { ($0.id, $0) }
            )
        }
    }
}
