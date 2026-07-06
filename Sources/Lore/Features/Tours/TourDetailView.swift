import CoreLocation
import SwiftUI

/// One tour as a stop stepper: progress rail, current stop's place card
/// content + curator note, previous/next controls.
struct TourDetailView: View {
    let tour: Tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = TourDetailModel()
    @State private var stopIndex = 0
    /// Drives the active-tour Live Activity + Dynamic Island (docs/16 §8).
    @State private var liveActivity = TourLiveActivityController()

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
                        // The stop card slides+fades to the next stop rather than
                        // hot-swapping its text (LUXURY-MOTION §6 continuity).
                        .id(stopIndex)
                        .transition(stopTransition)
                        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
                    liveActivityControl
                    stepperControls
                }
            }
            .padding(16)
        }
        .background(LoreColor.bone100)
        .navigationTitle(tour.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(city: tour.city) }
        // Push each stop change into the Live Activity so the Lock Screen /
        // Dynamic Island track the walk (docs/16 §8). No-op when not running.
        .onChange(of: stopIndex) { _, _ in syncLiveActivity() }
        // End the activity if the user leaves the tour screen without finishing.
        .onDisappear { liveActivity.end() }
    }

    // MARK: Live Activity

    /// Start / stop the active-tour Live Activity. Only meaningful when the tour
    /// has stops and the system permits Live Activities.
    @ViewBuilder
    private var liveActivityControl: some View {
        if !tour.stops.isEmpty && liveActivity.areActivitiesEnabled {
            Button {
                if liveActivity.isRunning {
                    liveActivity.end()
                } else {
                    startLiveActivity()
                }
            } label: {
                Label(
                    liveActivity.isRunning ? "End Live Activity" : "Start walking tour",
                    systemImage: liveActivity.isRunning ? "stop.circle" : "figure.walk.circle.fill"
                )
                .font(LoreType.button)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    liveActivity.isRunning ? LoreColor.bone200 : LoreColor.brass700,
                    in: Capsule()
                )
                .foregroundStyle(liveActivity.isRunning ? LoreColor.ink : LoreColor.bone)
            }
            .buttonStyle(.pressable)
        }
    }

    /// Kick off the Live Activity from the current stop.
    private func startLiveActivity() {
        liveActivity.start(
            tour: tour,
            initialStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: liveStopName(at: stopIndex + 1),
            distanceToNextMeters: liveDistanceToNext()
        )
    }

    /// Reflect the current stopIndex into a running Live Activity.
    private func syncLiveActivity() {
        guard liveActivity.isRunning else { return }
        liveActivity.updateProgress(
            currentStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: liveStopName(at: stopIndex + 1),
            distanceToNextMeters: liveDistanceToNext()
        )
    }

    /// A display name for the stop at `index`, the resolved place name, else a
    /// "Stop N" fallback. Returns "" past the end (no next stop).
    private func liveStopName(at index: Int) -> String {
        guard tour.stops.indices.contains(index) else { return "" }
        let stop = tour.stops[index]
        return model.place(id: stop.placeID)?.name ?? "Stop \(index + 1)"
    }

    /// Straight-line distance (m) from the current stop's place to the next
    /// stop's place, when both resolve, a scaffold stand-in for the real
    /// user→next-stop distance a Core Location fix would give (docs/16 §8 TODO).
    private func liveDistanceToNext() -> Double? {
        guard
            tour.stops.indices.contains(stopIndex),
            tour.stops.indices.contains(stopIndex + 1),
            let here = model.place(id: tour.stops[stopIndex].placeID),
            let next = model.place(id: tour.stops[stopIndex + 1].placeID)
        else { return nil }
        return here.location.distance(from: next.location)
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

    /// Amber node rail, one dot per stop, filled up to the current one. The
    /// current dot swells (a spring pop) so the route reads its position; tapping
    /// a dot springs the stepper to that stop (LUXURY-MOTION §6 tour stepper).
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
                    .scaleEffect(index == stopIndex && !reduceMotion ? 1.35 : 1.0)
                    .onTapGesture {
                        withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
                            stopIndex = index
                        }
                    }
            }
            Spacer()
            Text("Stop \(stopIndex + 1) of \(tour.stops.count)")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
        // Dot fills + the current-dot swell settle on one spring, no cut.
        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
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
                SkeletonRow()
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
                withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { stopIndex -= 1 }
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LoreColor.bone200, in: Capsule())
                    .foregroundStyle(LoreColor.ink)
            }
            .buttonStyle(.pressable)
            .disabled(stopIndex == 0)

            Button {
                withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { stopIndex += 1 }
            } label: {
                Label("Next stop", systemImage: "chevron.right")
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
            }
            .buttonStyle(.pressable)
            .disabled(stopIndex >= tour.stops.count - 1)
        }
    }

    /// Directional slide: advancing pushes the new stop in from the trailing
    /// edge; going back pulls it from the leading edge. Reduce Motion → crossfade.
    private var stopTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
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
