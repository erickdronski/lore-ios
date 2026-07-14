import CoreLocation
import MapKit
import SwiftUI

/// One tour as a stop stepper: progress rail, current stop's place card
/// content + curator note, previous/next controls.
struct TourDetailView: View {
    let tour: Tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var model = TourDetailModel()
    @State private var stopIndex = 0
    /// Drives the active-tour Live Activity + Dynamic Island (docs/16 §8).
    @State private var liveActivity = TourLiveActivityController()
    /// Present the paywall when a free user opens a premium curated walk.
    @State private var showPaywall = false

    /// A premium curated walk the current viewer hasn't unlocked.
    private var isLocked: Bool { tour.isPremium && !entitlements.isPlus }

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
                } else if isLocked {
                    // A curated Lore+ walk: preview the stops (a table of contents)
                    // so the value is visible, then the guided route, turn-by-turn
                    // notes, and audio resolve to a lock.
                    lockedTourPreview
                } else {
                    progressRail
                    stopCard
                        // The stop card slides+fades to the next stop rather than
                        // hot-swapping its text (LUXURY-MOTION §6 continuity).
                        .id(stopIndex)
                        .transition(stopTransition)
                        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
                    liveActivityControl
                    directionsControl
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .tours)
        }
    }

    /// Locked premium tour: a numbered preview of the stops so a shopper can see
    /// what the walk covers before deciding, then the Lore+ unlock. The guided
    /// experience (route order, turn-by-turn notes, live activity, audio) stays
    /// gated, only the "what you'll see" list is shown.
    private var lockedTourPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(tour.stops.count) stops on this walk")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink)
                ForEach(Array(tour.stops.enumerated()), id: \.offset) { i, stop in
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.brass700)
                            .frame(width: 18, alignment: .leading)
                        Text(model.place(id: stop.placeID)?.name ?? "Stop \(i + 1)")
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.ink600)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 14))

            PlusGate(isPlus: false, feature: .tours, onUnlock: { showPaywall = true }) {
                EmptyView()
            }
        }
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

    // MARK: Directions (TestFlight feedback: "don't we need directions here?")

    /// The `Place` for the currently-shown stop, when it has resolved.
    private var currentStopPlace: Place? {
        guard tour.stops.indices.contains(stopIndex) else { return nil }
        return model.place(id: tour.stops[stopIndex].placeID)
    }

    /// Hand off walking directions to the current stop to Apple Maps. Shown only
    /// once the stop's place (and its coordinate) has loaded.
    @ViewBuilder
    private var directionsControl: some View {
        if currentStopPlace != nil {
            Button {
                Haptics.play(.chipTap)
                openDirections()
            } label: {
                Label("Walking directions to this stop", systemImage: "figure.walk")
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(LoreColor.ink)
                    .overlay(Capsule().strokeBorder(LoreColor.ink, lineWidth: 1.5))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Walking directions to this stop"))
        }
    }

    /// Open Apple Maps with walking directions from the user's location to the
    /// current stop. Apple handles the routing + turn-by-turn.
    private func openDirections() {
        guard let place = currentStopPlace else { return }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    /// Kick off the Live Activity from the current stop.
    private func startLiveActivity() {
        liveActivity.start(
            tour: tour,
            initialStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: liveStopName(at: stopIndex + 1),
            // Omit the distance number: a real live user->stop distance needs a
            // continuous Core Location fix. Showing a static stop-to-stop leg as
            // if it were live would be dishonest (docs/16 §8 TODO).
            distanceToNextMeters: nil
        )
    }

    /// Reflect the current stopIndex into a running Live Activity.
    private func syncLiveActivity() {
        guard liveActivity.isRunning else { return }
        liveActivity.updateProgress(
            currentStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: liveStopName(at: stopIndex + 1),
            distanceToNextMeters: nil
        )
    }

    /// A display name for the stop at `index`, the resolved place name, else a
    /// "Stop N" fallback. Returns "" past the end (no next stop).
    private func liveStopName(at index: Int) -> String {
        guard tour.stops.indices.contains(index) else { return "" }
        let stop = tour.stops[index]
        return model.place(id: stop.placeID)?.name ?? "Stop \(index + 1)"
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
            tripFacts
        }
    }

    // MARK: Trip facts (TestFlight feedback: "Total distance? Total time?")

    /// Total walking distance along the routed stops, in meters, once every
    /// stop's place has resolved. Sums the consecutive stop-to-stop legs, a
    /// close proxy for the on-foot route (Apple Maps gives the exact path when
    /// the user taps directions). Nil until the stops load, so the strip only
    /// ever shows real numbers.
    private var routeMeters: Double? {
        let locations = tour.stops.compactMap { model.place(id: $0.placeID)?.location }
        guard locations.count == tour.stops.count, locations.count >= 2 else { return nil }
        return zip(locations, locations.dropFirst())
            .reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }

    /// Estimated walking time for the route at a relaxed 1.3 m/s, whole minutes.
    private var walkMinutes: Int? {
        guard let routeMeters else { return nil }
        return max(1, Int((routeMeters / 1.3) / 60))
    }

    /// One authoritative distance label: the tour's own curated distance when
    /// set, otherwise the computed route. Nil until at least one is available.
    private var distanceText: String? {
        if let km = tour.distanceKm { return String(format: "%.1f km", km) }
        if let routeMeters { return BearingProjector.distanceLabel(meters: routeMeters) }
        return nil
    }

    /// One authoritative walking-time label: the tour's own curated duration
    /// when set, otherwise the computed estimate.
    private var minutesText: String? {
        if let min = tour.durationMin { return "\(min) min" }
        if let walkMinutes { return "\(walkMinutes) min" }
        return nil
    }

    /// A compact facts strip under the tour title: total distance, walking
    /// time, and stop count. A single source of truth, so the two numbers can
    /// never disagree (they used to: a curated summary line above a recomputed
    /// strip below).
    @ViewBuilder
    private var tripFacts: some View {
        if distanceText != nil || minutesText != nil {
            HStack(spacing: 16) {
                if let distanceText { tripFact(system: "figure.walk", text: distanceText) }
                if let minutesText { tripFact(system: "clock", text: minutesText) }
                tripFact(system: "mappin.and.ellipse", text: "\(tour.stops.count) stops")
            }
            .padding(.top, 2)
        }
    }

    private func tripFact(system: String, text: String) -> some View {
        Label(text, systemImage: system)
            .font(LoreType.caption)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(LoreColor.ink)
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
            } else if currentStop != nil {
                Text("Stop \(stopIndex + 1)")
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
