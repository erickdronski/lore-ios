import CoreLocation
import MapKit
import SwiftUI

/// Sheet host for tour routes that are not pushed from the Tours stack. The
/// explicit close control keeps the route recoverable when swipe dismissal is
/// unavailable or undiscoverable.
struct TourSheet: View {
    let tour: Tour
    var onMeetCity: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TourDetailView(tour: tour, onMeetCity: onMeetCity)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close tour")
                    }
                }
        }
    }
}

/// One tour as a stop stepper: progress rail, current stop's place card
/// content + curator note, previous/next controls.
struct TourDetailView: View {
    let tour: Tour
    var onMeetCity: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var model = TourDetailModel()
    /// The stop currently being inspected. Browsing the map or itinerary moves
    /// this index without claiming that the traveler reached a checkpoint.
    @State private var stopIndex = 0
    /// Highest checkpoint reached through an explicit Next action or a verified
    /// GPS arrival. This is the only in-progress value persisted for resume.
    @State private var furthestReachedStopIndex = 0
    /// Drives the active-tour Live Activity + Dynamic Island (docs/16 §8).
    @State private var liveActivity = TourLiveActivityController()
    /// Present the paywall when a free user opens a premium curated walk.
    @State private var showPaywall = false
    /// Hands-free audio-tour narration: the current stop's dossier read aloud
    /// (Lore+). Manual per-stop for now; GPS auto-advance is a device-tested
    /// follow-up. One narrator, stopped on stop-change + disappear.
    @State private var narration = NarrationService()
    @State private var currentNarrative: String?
    /// Pre-rendered studio narration for the current stop, when its dive has
    /// one (tools/narration). Preferred over TTS by every play path.
    @State private var currentAudioURL: URL?
    @State private var narrativeLoadFailed = false
    /// Hands-free geofenced guiding (Lore+): auto-advance + auto-play as the
    /// walker reaches each stop. Foreground-only v1 (When-In-Use permission).
    @State private var walkGuide = TourWalkGuide()
    /// Stops the walker has physically arrived at this session. Drives the
    /// guide's target: the current stop until you reach it, then the next one.
    @State private var arrivedStops: Set<Int> = []
    /// Set on arrival; `loadNarrative()` speaks once the narrative is in, so
    /// auto-play can never race the per-stop load (which stops the narrator).
    @State private var pendingAutoPlay = false
    /// Camera for the route overview map. Framed to fit every stop once the
    /// city's places resolve (an explicit region, never `.automatic`, which
    /// mis-frames a sparse set of pins).
    @State private var mapCamera: MapCameraPosition = .automatic
    /// Restore once before accepting deliberate progress updates.
    @State private var didRestoreProgress = false
    /// Full-screen completion beat at the final stop.
    @State private var showCompletion = false
    /// A completed walk opens as a keepsake until the traveler explicitly starts
    /// it again; merely browsing its stops must not erase the completion seal.
    @State private var wasCompleted = false
    /// Whether the current stop's curator note is expanded to its full length.
    /// Reset to collapsed whenever the stop changes.
    @State private var noteExpanded = false
    /// The tour stop whose full place dossier is open.
    @State private var selectedStopPlace: Place?

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
                    if wasCompleted { completedTourBanner }
                    progressRail
                    if hasTourPlaceIssue { tourPlaceLoadIssue }
                    // See the whole walk first: every stop laid out in order, the
                    // current one highlighted. A tour that starts with a map reads
                    // as a real guided walk, not just a list of write-ups.
                    routeMap
                    stopCard
                        // The stop card slides+fades to the next stop rather than
                        // hot-swapping its text (LUXURY-MOTION §6 continuity).
                        .id(stopIndex)
                        .transition(stopTransition)
                        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
                    // A walker's per-stop actions, top to bottom in the order they
                    // are used: listen hands-free, let the walk drive itself,
                    // then walk there, then advance.
                    audioControl
                    guideControl
                    directionsControl
                    stepperControls
                    // The Live Activity is a companion, not the "start" button, so
                    // it sits last with a caption explaining what it does (it used
                    // to head the screen labelled "Start walking tour", which read
                    // as broken when nothing changed in-app).
                    liveActivityControl
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .background(LoreColor.bone100)
        .navigationTitle(tour.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            restoreProgress()
            await model.load(city: tour.city)
            await loadNarrative()
            focusRouteMap()
            retargetGuide()
        }
        // Push each stop change into the Live Activity so the Lock Screen /
        // Dynamic Island track the walk (docs/16 §8). No-op when not running.
        .onChange(of: stopIndex) { _, _ in
            syncLiveActivity()
            retargetGuide()
            Task { await loadNarrative() }
        }
        // A moving walker updates the Lock-Screen distance live while guiding.
        .onChange(of: walkGuide.distanceToTarget) { _, _ in
            syncLiveActivity()
        }
        .onChange(of: entitlements.isPlus) { _, isPlus in
            guard !isPlus else { return }
            narration.stop()
            walkGuide.stop()
        }
        // End the activity if the user leaves the tour screen without finishing.
        .onDisappear { liveActivity.end(); narration.stop(); walkGuide.stop() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .tours)
        }
        .loreDossierPresentation(item: $selectedStopPlace) { place in
            PlaceCardView(
                place: place,
                onMeetCity: {
                    selectedStopPlace = nil
                    onMeetCity($0)
                }
            )
        }
        .overlay {
            if showCompletion {
                TourCompletionView(tour: tour) {
                    showCompletion = false
                    dismiss()
                }
                .transition(.opacity)
            }
        }
    }

    /// Locked premium tour: a numbered preview of the stops so a shopper can see
    /// what the walk covers before deciding, then the Lore+ unlock. The guided
    /// experience (route order, turn-by-turn notes, live activity, audio) stays
    /// gated, only the "what you'll see" list is shown.
    private var lockedTourPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ROUTE PREVIEW")
                            .font(LoreType.micro)
                            .tracking(1.2)
                            .foregroundStyle(LoreColor.brass700)
                        Text("\(tour.stops.count) checkpoints on this walk")
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.ink)
                    }
                    Spacer()
                    Image(systemName: "map.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LoreColor.brass700)
                        .accessibilityHidden(true)
                }
                .padding(.bottom, 4)

                ForEach(Array(tour.stops.enumerated()), id: \.offset) { i, stop in
                    HStack(alignment: .top, spacing: 11) {
                        VStack(spacing: 0) {
                            Text("\(i + 1)")
                                .font(LoreType.micro)
                                .foregroundStyle(LoreColor.bone)
                                .frame(width: 25, height: 25)
                                .background(LoreColor.ink, in: Circle())
                            if i < tour.stops.count - 1 {
                                Rectangle()
                                    .fill(LoreColor.brass.opacity(0.45))
                                    .frame(width: 1.5, height: 24)
                            }
                        }
                        Text(model.place(id: stop.placeID)?.name ?? "Stop \(i + 1)")
                            .font(LoreType.body)
                            .foregroundStyle(LoreColor.ink)
                            .lineLimit(1)
                            .padding(.top, 2)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LoreColor.bone300, lineWidth: 1)
            }
            .loreElevation(.elev1)

            PlusGate(isPlus: false, feature: .tours, onUnlock: { showPaywall = true }) {
                EmptyView()
            }
        }
    }

    // MARK: Live Activity (Lock-Screen companion)

    /// Pin the walk to the Lock Screen / Dynamic Island. Deliberately *not* the
    /// headline "start" of the tour: it drives an Activity that lives OUTSIDE the
    /// app, so tapping it changes nothing on this screen (and shows nothing at
    /// all on Simulator, which doesn't render Live Activities). It used to be
    /// labelled "Start walking tour", which read as broken. Now it names exactly
    /// what it does, with a caption, and reads as an optional extra.
    @ViewBuilder
    private var liveActivityControl: some View {
        if !tour.stops.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if liveActivity.areActivitiesEnabled {
                    Button {
                        Haptics.play(.chipTap)
                        if liveActivity.isRunning {
                            liveActivity.end()
                        } else {
                            startLiveActivity()
                        }
                    } label: {
                        Label(
                            liveActivity.isRunning ? "Pinned to Lock Screen · tap to stop" : "Pin tour to Lock Screen",
                            systemImage: liveActivity.isRunning ? "checkmark.circle.fill" : "lock.iphone"
                        )
                        .font(LoreType.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            liveActivity.isRunning ? LoreColor.brass700 : LoreColor.bone200,
                            in: Capsule()
                        )
                        .foregroundStyle(liveActivity.isRunning ? LoreColor.bone : LoreColor.ink)
                        .overlay {
                            if !liveActivity.isRunning {
                                Capsule().strokeBorder(LoreColor.ink.opacity(0.15), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.pressable)
                } else {
                    Label("Lock Screen companion unavailable", systemImage: "iphone.slash")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink600)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 13))
                }

                Text(liveActivity.startFailure?.message ?? (liveActivity.isRunning
                    ? "Your current stop now shows on the Lock Screen and Dynamic Island as you walk."
                    : (liveActivity.areActivitiesEnabled
                        ? "Optional. Keeps your current stop on the Lock Screen and Dynamic Island so you can glance at it without opening Lore. Shows on a real iPhone, not the Simulator."
                        : TourLiveActivityController.StartFailure.disabled.message)))
                    .font(LoreType.micro)
                    .foregroundStyle(liveActivity.startFailure == .systemRejected ? LoreColor.error : LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    // MARK: Route map (TestFlight feedback: "let me see the whole walk")

    /// The tour's stops in order, paired with their resolved place. Empty until
    /// the city's places load; drives both the overview map and its framing.
    private var orderedStopPlaces: [(index: Int, place: Place)] {
        tour.stops.enumerated().compactMap { i, stop in
            model.place(id: stop.placeID).map { (i, $0) }
        }
    }

    private var hasTourPlaceIssue: Bool {
        model.loadFailed
            || (model.loadSucceeded && orderedStopPlaces.count != tour.stops.count)
    }

    /// An overview map of the entire walk: every stop as a numbered pin, the
    /// current stop swollen + amber, and a dotted line threading them in order.
    /// Tapping a pin springs the stepper to that stop. The dotted segments show
    /// stop *order*, not the routed path — Apple Maps draws the real walking
    /// route from the "Walking directions" button, so this never needs a network
    /// round-trip and never shows a route it can't stand behind.
    @ViewBuilder
    private var routeMap: some View {
        let stops = orderedStopPlaces
        if stops.count == tour.stops.count, stops.count >= 2 {
            VStack(spacing: 0) {
                HStack {
                    Label("ROUTE OVERVIEW", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(LoreType.micro)
                        .tracking(1)
                        .foregroundStyle(LoreColor.brass700)
                    Spacer()
                    Text("Tap a checkpoint")
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                }
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(LoreColor.bone50)

                Map(position: $mapCamera, interactionModes: [.pan, .zoom]) {
                    MapPolyline(coordinates: stops.map(\.place.coordinate))
                        .stroke(
                            LoreColor.brass700.opacity(0.55),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7])
                        )
                    ForEach(stops, id: \.index) { item in
                        Annotation(item.place.name, coordinate: item.place.coordinate) {
                            Button {
                                withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
                                    stopIndex = item.index
                                }
                            } label: {
                                routePin(number: item.index + 1, active: item.index == stopIndex)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Stop \(item.index + 1), \(item.place.name)"))
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: horizontalSizeClass == .regular ? 250 : 190)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LoreColor.bone300.opacity(0.9), lineWidth: 1)
            }
            .loreElevation(.elev1)
            .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
        }
    }

    /// A numbered map pin; the active stop swells to amber so the route reads
    /// which stop the stepper is on.
    private func routePin(number: Int, active: Bool) -> some View {
        Text("\(number)")
            .font(.system(size: active ? 13 : 11, weight: .bold))
            .foregroundStyle(active ? LoreColor.ink : LoreColor.bone)
            .frame(width: active ? 30 : 24, height: active ? 30 : 24)
            .background(active ? LoreColor.amber : LoreColor.brass700, in: Circle())
            .overlay(Circle().strokeBorder(LoreColor.bone, lineWidth: 2))
            .shadow(color: LoreColor.ink950.opacity(0.25), radius: active ? 4 : 1, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// Frame the overview map to fit every stop once the places resolve. An
    /// explicit region (never `.automatic`, which mis-frames a sparse pin set).
    private func focusRouteMap() {
        let coords = orderedStopPlaces.map(\.place.coordinate)
        guard coords.count >= 2 else { return }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.006, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.006, (maxLng - minLng) * 1.5)
        )
        mapCamera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private var tourPlaceLoadIssue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Tour details unavailable",
                systemImage: model.loadFailed ? "wifi.exclamationmark" : "exclamationmark.triangle.fill"
            )
                .font(LoreType.body.weight(.semibold))
                .foregroundStyle(LoreColor.error)
            Text(
                model.loadFailed
                    ? "Lore couldn't load this route's place details. Your saved tour progress is safe."
                    : "One or more checkpoints are missing place details, so Lore won't draw an incomplete route. Your saved progress is safe."
            )
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await retryTourPlaces() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(LoreType.button)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(LoreColor.ink)
            .disabled(model.isLoading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoreColor.error.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func retryTourPlaces() async {
        await model.load(city: tour.city, retry: true)
        guard !hasTourPlaceIssue else { return }
        focusRouteMap()
        retargetGuide()
    }

    /// A REAL live distance to the NEXT stop, and only that (docs/16 §8 TODO,
    /// now closed): available exactly when the walk guide is running with a
    /// trustworthy fix AND its target is the next stop (i.e. the walker has
    /// reached the current one). Anything else stays nil — never a stale or
    /// mislabelled number on the Lock Screen.
    private var liveNextStopMeters: Double? {
        guard walkGuide.isGuiding,
              arrivedStops.contains(stopIndex),
              guideTargetIndex == stopIndex + 1
        else { return nil }
        return walkGuide.distanceToTarget
    }

    /// Kick off the Live Activity from the current stop.
    private func startLiveActivity() {
        liveActivity.start(
            tour: tour,
            initialStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: nextLiveStopName(at: stopIndex + 1),
            distanceToNextMeters: liveNextStopMeters
        )
    }

    /// Reflect the current stopIndex into a running Live Activity.
    private func syncLiveActivity() {
        guard liveActivity.isRunning else { return }
        liveActivity.updateProgress(
            currentStopIndex: stopIndex + 1,
            currentStopName: liveStopName(at: stopIndex),
            nextStopName: nextLiveStopName(at: stopIndex + 1),
            distanceToNextMeters: liveNextStopMeters
        )
    }

    /// A display name for the stop at `index`, the resolved place name, else a
    /// "Stop N" fallback. Returns "" past the end (no next stop).
    private func liveStopName(at index: Int) -> String {
        guard tour.stops.indices.contains(index) else { return "" }
        let stop = tour.stops[index]
        return model.place(id: stop.placeID)?.name ?? "Stop \(index + 1)"
    }

    /// Optional next-stop label for Live Activities. Nil at the final stop so
    /// the Lock Screen never renders a bare "Next:" line.
    private func nextLiveStopName(at index: Int) -> String? {
        guard tour.stops.indices.contains(index) else { return nil }
        return liveStopName(at: index)
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
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [LoreColor.ink800, LoreColor.ink950],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            TourRouteConstellation(nodeCount: min(max(tour.stops.count, 3), 7))
                .frame(width: 190, height: 125)
                .padding(.top, 34)
                .padding(.trailing, -24)
                .opacity(0.5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(tour.isPremium ? "LORE+ FIELD WALK" : "CITY FIELD WALK", systemImage: "map")
                        .font(LoreType.micro)
                        .tracking(1.2)
                        .foregroundStyle(LoreColor.brass300)
                    Spacer()
                    Text("\(tour.stops.count) STOPS")
                        .font(LoreType.micro)
                        .tracking(0.8)
                        .foregroundStyle(LoreColor.bone.opacity(0.8))
                }

                ZStack {
                    Circle().fill(LoreColor.bone.opacity(0.1))
                    Circle().strokeBorder(LoreColor.amber.opacity(0.75), lineWidth: 1)
                        .padding(3)
                    Text(tour.displayEmoji).font(.system(size: 31))
                }
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)

                Text(tour.title)
                    .font(LoreType.display(size: 28, weight: .semibold))
                    .foregroundStyle(LoreColor.bone)

                if let blurb = tour.blurb {
                    Text(blurb)
                        .font(LoreType.hook)
                        .foregroundStyle(LoreColor.bone.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                tripFacts
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .loreElevation(.elev1)
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
        if distanceText != nil || minutesText != nil || !tour.stops.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    if let distanceText { tripFact(system: "figure.walk", text: distanceText) }
                    if let minutesText { tripFact(system: "clock", text: minutesText) }
                    tripFact(system: "mappin.and.ellipse", text: "\(tour.stops.count) stops")
                }
                VStack(alignment: .leading, spacing: 5) {
                    if let distanceText { tripFact(system: "figure.walk", text: distanceText) }
                    if let minutesText { tripFact(system: "clock", text: minutesText) }
                    tripFact(system: "mappin.and.ellipse", text: "\(tour.stops.count) stops")
                }
            }
            .padding(.top, 2)
        }
    }

    private func tripFact(system: String, text: String) -> some View {
        Label(text, systemImage: system)
            .font(LoreType.caption)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(LoreColor.bone)
    }

    /// A horizontally scrolling checkpoint itinerary. Shape, number, fill, and
    /// connecting segments all communicate visited/current/upcoming state;
    /// tapping a checkpoint springs the stepper to that stop.
    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR ITINERARY")
                        .font(LoreType.micro)
                        .tracking(1.2)
                        .foregroundStyle(LoreColor.brass700)
                    Text("Checkpoint \(stopIndex + 1) of \(tour.stops.count)")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                }
                Spacer()
                Text("\(Int(progressFraction * 100))%")
                    .font(LoreType.display(size: 18, weight: .semibold))
                    .foregroundStyle(LoreColor.brass700)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, _ in
                        Button {
                            withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
                                stopIndex = index
                            }
                        } label: {
                            RouteCheckpoint(
                                number: index + 1,
                                isVisited: index != stopIndex
                                    && (wasCompleted || index <= furthestReachedStopIndex),
                                isCurrent: index == stopIndex
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Stop \(index + 1) of \(tour.stops.count)"))
                        .accessibilityValue(
                            Text(
                                index == stopIndex
                                    ? "Currently viewing"
                                    : ((wasCompleted || index <= furthestReachedStopIndex) ? "Reached" : "Upcoming")
                            )
                        )

                        if index < tour.stops.count - 1 {
                            Capsule()
                                .fill(
                                    wasCompleted || index < furthestReachedStopIndex
                                        ? LoreColor.amber
                                        : LoreColor.bone300
                                )
                                .frame(width: 28, height: 3)
                                .padding(.horizontal, 3)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LoreColor.bone300.opacity(0.8), lineWidth: 1)
        }
        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: stopIndex)
    }

    private var progressFraction: Double {
        if wasCompleted { return 1 }
        guard !tour.stops.isEmpty else { return 0 }
        return Double(furthestReachedStopIndex + 1) / Double(tour.stops.count)
    }

    private var completedTourBanner: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                completedTourLabel
                Spacer()
                walkAgainButton
            }
            VStack(alignment: .leading, spacing: 12) {
                completedTourLabel
                walkAgainButton
            }
        }
        .padding(14)
        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .contain)
    }

    private var completedTourLabel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(LoreColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Walk completed")
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink)
                Text("Your trail seal is saved. Start again whenever you want a fresh guided pass.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

    private var walkAgainButton: some View {
        Button("Walk again") {
            TourProgressStore.restart(tourSlug: tour.slug, userID: auth.session?.user.id)
            wasCompleted = false
            furthestReachedStopIndex = 0
            stopIndex = 0
        }
        .font(LoreType.caption)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var stopCard: some View {
        ZStack(alignment: .topTrailing) {
            Text(String(format: "%02d", stopIndex + 1))
                .font(.system(size: 78, weight: .black, design: .serif))
                .foregroundStyle(LoreColor.bone200.opacity(0.65))
                .offset(x: 8, y: -9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("FIELD STOP / \(String(format: "%02d", stopIndex + 1))")
                        .font(LoreType.micro)
                        .tracking(1.2)
                        .foregroundStyle(LoreColor.brass700)
                    Spacer()
                    Image(systemName: "scope")
                        .foregroundStyle(LoreColor.brass700)
                        .accessibilityHidden(true)
                }

                if let place = currentPlace {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle().fill(LoreColor.ink)
                            Circle().strokeBorder(LoreColor.amber, lineWidth: 1)
                                .padding(3)
                            Text(place.displayEmoji).font(.system(size: 28))
                        }
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(place.name)
                                .font(LoreType.displayL)
                                .foregroundStyle(LoreColor.ink)
                            if let year = place.layer1?.yearBuilt {
                                YearChip(year: year)
                            }
                        }
                    }

                    if let hook = place.teaser {
                        Text(hook)
                            .font(LoreType.hook)
                            .foregroundStyle(LoreColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Haptics.play(.dossierOpen)
                        selectedStopPlace = place
                    } label: {
                        Label("Open full dossier", systemImage: "books.vertical.fill")
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.bone)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(LoreColor.ink, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens this stop's history, timeline, sources, offers, and visit controls")
                } else if model.isLoading {
                    SkeletonRow()
                } else if model.loadFailed {
                    Text("Place details unavailable. Use Retry above to reload this route.")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                } else if currentStop != nil {
                    Text("Place details are missing for this checkpoint.")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink600)
                }

                if let note = currentStop?.note {
                    // Long notes collapse to a few lines with a "Read more"
                    // toggle so a full field note is always reachable in-line.
                    let isLong = note.count > 220
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(LoreColor.amber)
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 5) {
                            Label("CURATOR'S FIELD NOTE", systemImage: "eye")
                                .font(LoreType.micro)
                                .tracking(0.8)
                                .foregroundStyle(LoreColor.brass700)
                            Text(note)
                                .font(LoreType.body)
                                .foregroundStyle(LoreColor.ink)
                                .lineLimit(isLong && !noteExpanded ? 6 : nil)
                                .fixedSize(horizontal: false, vertical: true)
                            if isLong {
                                Button {
                                    withAnimation(reduceMotion ? nil : LoreMotion.tap) {
                                        noteExpanded.toggle()
                                    }
                                } label: {
                                    Text(noteExpanded ? "Read less" : "Read more")
                                        .font(LoreType.button)
                                        .foregroundStyle(LoreColor.brass700)
                                }
                                .buttonStyle(.plain)
                                .frame(minHeight: 44, alignment: .leading)
                                .accessibilityLabel(Text(noteExpanded ? "Read less of the field note" : "Read the full field note"))
                            }
                        }
                    }
                    .padding(12)
                    .background(LoreColor.bone200.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .onChange(of: currentStop?.id) { _, _ in noteExpanded = false }
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LoreColor.bone300.opacity(0.9), lineWidth: 1)
        }
        .loreElevation(.elev1)
    }

    /// The hands-free "listen to this stop" control (Lore+). Speaks the current
    /// stop's dossier so a walker can pocket the phone. Free users get a locked
    /// affordance that opens the paywall.
    @ViewBuilder
    private var audioControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if entitlements.isPlus {
                    Haptics.play(.chipTap)
                    if narration.isPaused {
                        narration.resume()
                    } else if narration.isSpeaking {
                        narration.pause()
                    } else if currentNarrative != nil || currentAudioURL != nil {
                        narration.narrateDossier(text: currentNarrative, audioURL: currentAudioURL)
                    } else if narrativeLoadFailed {
                        Task { await loadNarrative() }
                    }
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: narration.isPaused ? "play.circle.fill" : (narration.isSpeaking ? "pause.circle.fill" : "headphones"))
                        .font(.system(size: 18))
                    Text(audioButtonTitle)
                        .font(LoreType.button)
                    Spacer()
                    if !entitlements.isPlus {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundStyle(LoreColor.ink)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(LoreColor.bone200, in: Capsule())
                .overlay(Capsule().strokeBorder(LoreColor.brass700.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .disabled(entitlements.isPlus && currentNarrative == nil && currentAudioURL == nil && !narrativeLoadFailed)
            .accessibilityLabel(audioAccessibilityLabel)

            if narration.isActive {
                HStack(spacing: 10) {
                    if narration.canSeek {
                        narrationControl(system: "gobackward.15", label: "Back 15 seconds") {
                            narration.skip(seconds: -15)
                        }
                    }
                    Button {
                        narration.cyclePlaybackRate()
                    } label: {
                        Text("\(playbackRateText)x")
                            .font(LoreType.micro)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(LoreColor.bone200, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Playback speed, \(playbackRateText) times"))
                    if narration.canSeek {
                        narrationControl(system: "goforward.15", label: "Forward 15 seconds") {
                            narration.skip(seconds: 15)
                        }
                    }
                    Spacer()
                    Button("Stop") { narration.stop() }
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.error)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 8)
            }

            if let error = narration.playbackError {
                Text(error)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            } else if narrativeLoadFailed {
                Text("Narration couldn't load. Tap above to retry; downloaded city audio still works without signal.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var audioButtonTitle: String {
        if !entitlements.isPlus { return "Play this stop" }
        if narration.isPaused { return "Resume audio" }
        if narration.isSpeaking { return "Pause audio" }
        if narrativeLoadFailed { return "Retry narration" }
        return "Play this stop"
    }

    private var playbackRateText: String {
        String(format: "%.2g", Double(narration.playbackRate))
    }

    private var audioAccessibilityLabel: Text {
        if !entitlements.isPlus { return Text("Play this stop's audio, a Lore Plus feature") }
        if narration.isPaused { return Text("Resume this stop's audio") }
        if narration.isSpeaking { return Text("Pause this stop's audio") }
        if narrativeLoadFailed { return Text("Retry loading this stop's narration") }
        return Text("Play this stop's audio")
    }

    private func narrationControl(system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LoreColor.ink)
                .frame(width: 44, height: 44)
                .background(LoreColor.bone200, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Geofenced auto-play (Lore+)

    /// The stop the guide should steer the walker toward: the current stop
    /// until they've physically arrived at it, then the next one — so the
    /// distance line and the arrival trigger always mean "your next waypoint".
    private var guideTargetIndex: Int? {
        guard !tour.stops.isEmpty else { return nil }
        if !arrivedStops.contains(stopIndex) { return stopIndex }
        let next = stopIndex + 1
        return tour.stops.indices.contains(next) ? next : nil
    }

    private var guideTargetName: String? {
        guard let guideTargetIndex else { return nil }
        return model.place(id: tour.stops[guideTargetIndex].placeID)?.name
    }

    /// "Auto-play as you walk": the toggle that turns the tour into a
    /// self-driving audio walk. Free users get the locked affordance.
    @ViewBuilder
    private var guideControl: some View {
        Button {
            if entitlements.isPlus {
                Haptics.play(.chipTap)
                if walkGuide.isDenied {
                    OnboardingSettings.open()
                } else {
                    toggleGuide()
                }
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: walkGuide.isGuiding ? "location.fill" : "location")
                    .font(.system(size: 18))
                    .foregroundStyle(walkGuide.isGuiding ? LoreColor.brass700 : LoreColor.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(walkGuide.isDenied
                        ? "Location needed for auto-play"
                        : (walkGuide.isGuiding ? "Guiding — auto-play is on" : "Auto-play as you walk"))
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                    if walkGuide.isDenied {
                        Text("Tap to open Settings. Manual stops and narration still work.")
                            .font(LoreType.caption).foregroundStyle(LoreColor.error)
                    } else if walkGuide.isGuiding {
                        // One honest status line: denied, locating, or a live
                        // "next waypoint · distance" once a good fix exists.
                        if let meters = walkGuide.distanceToTarget, let name = guideTargetName {
                            Text("\(name) · \(BearingProjector.distanceLabel(meters: meters))")
                                .font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                        } else if guideTargetIndex == nil {
                            Text("Final stop reached — that's the walk.")
                                .font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                        } else {
                            Text("Finding you…")
                                .font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                        }
                    } else {
                        Text("Each stop plays itself as you walk up to it.")
                            .font(LoreType.caption).foregroundStyle(LoreColor.ink600)
                    }
                }
                Spacer()
                if !entitlements.isPlus {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        walkGuide.isGuiding ? LoreColor.brass700.opacity(0.8) : LoreColor.brass700.opacity(0.4),
                        lineWidth: walkGuide.isGuiding ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(entitlements.isPlus
            ? (walkGuide.isDenied
                ? "Location is off. Open Settings for walking auto-play"
                : (walkGuide.isGuiding ? "Stop auto-play guiding" : "Auto-play each stop as you walk up to it"))
            : "Auto-play as you walk, a Lore Plus feature")
    }

    private func toggleGuide() {
        if walkGuide.isGuiding {
            walkGuide.stop()
            return
        }
        walkGuide.onArrive = { index in handleArrival(at: index) }
        walkGuide.start()
        retargetGuide()
    }

    /// Point the guide at the walker's next waypoint. Idempotent; called on
    /// guide start, stop changes, and after each arrival.
    private func retargetGuide() {
        guard walkGuide.isGuiding else { return }
        guard let index = guideTargetIndex else { return }
        let coordinate = model.place(id: tour.stops[index].placeID)?.coordinate
        walkGuide.setTarget(index: index, coordinate: coordinate)
    }

    /// The arrival moment: haptic, advance the stepper to the reached stop,
    /// queue auto-play (spoken by `loadNarrative`'s tail once the text is in),
    /// and steer the guide onward to the following stop.
    private func handleArrival(at index: Int) {
        Haptics.play(.scannerLock)
        arrivedStops.insert(index)
        recordProgress(at: index)
        pendingAutoPlay = true
        if stopIndex != index {
            // onChange(stopIndex) syncs the Live Activity, retargets the guide,
            // and reloads the narrative, whose tail speaks this arrival.
            withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { stopIndex = index }
        } else {
            retargetGuide()
            Task { await loadNarrative() }
        }
    }

    /// Load the current stop's dossier narrative for audio playback, stopping any
    /// in-flight narration so switching stops never overlaps two voices. When an
    /// arrival queued auto-play, speak as soon as the narrative lands (never
    /// before, so the load's `stop()` can't cut our own speech off).
    private func loadNarrative() async {
        narration.stop()
        currentNarrative = nil
        currentAudioURL = nil
        narrativeLoadFailed = false
        guard let placeID = currentStop?.placeID else { return }
        let dive: Dive?
        do {
            dive = try await LoreAPI.shared.dive(placeID: placeID)
        } catch {
            guard currentStop?.placeID == placeID else { return }
            narrativeLoadFailed = true
            pendingAutoPlay = false
            return
        }
        guard currentStop?.placeID == placeID else { return }
        currentNarrative = dive?.narrative
        currentAudioURL = dive?.audioURL
        if pendingAutoPlay {
            pendingAutoPlay = false
            if entitlements.isPlus, currentNarrative != nil || currentAudioURL != nil {
                narration.narrateDossier(text: currentNarrative, audioURL: currentAudioURL)
            }
        }
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
                if stopIndex >= tour.stops.count - 1 {
                    finishTour()
                } else {
                    let nextIndex = stopIndex + 1
                    recordProgress(at: nextIndex)
                    withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) {
                        stopIndex = nextIndex
                    }
                }
            } label: {
                Label(
                    stopIndex >= tour.stops.count - 1 ? "Finish tour" : "Next stop",
                    systemImage: stopIndex >= tour.stops.count - 1 ? "checkmark" : "chevron.right"
                )
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
            }
            .buttonStyle(.pressable)
        }
    }

    private func restoreProgress() {
        guard !didRestoreProgress else { return }
        didRestoreProgress = true
        let progress = TourProgressStore.progress(
            for: tour.slug,
            userID: auth.session?.user.id,
            stopCount: tour.stops.count
        )
        if let savedIndex = progress.stopIndex {
            stopIndex = savedIndex
            furthestReachedStopIndex = savedIndex
        }
        wasCompleted = progress.isCompleted
    }

    private func recordProgress(at index: Int) {
        guard didRestoreProgress, !wasCompleted else { return }
        furthestReachedStopIndex = max(furthestReachedStopIndex, index)
        TourProgressStore.advance(
            to: furthestReachedStopIndex,
            for: tour.slug,
            userID: auth.session?.user.id
        )
    }

    private func finishTour() {
        TourProgressStore.complete(
            tourSlug: tour.slug,
            userID: auth.session?.user.id
        )
        wasCompleted = true
        liveActivity.end()
        narration.stop()
        walkGuide.stop()
        withAnimation(LoreMotion.tap) { showCompletion = true }
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

/// One tap target on the itinerary rail. Completed, current, and upcoming
/// checkpoints differ by shape as well as color so the state survives without
/// color perception.
private struct RouteCheckpoint: View {
    let number: Int
    let isVisited: Bool
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isCurrent ? LoreColor.amber : (isVisited ? LoreColor.ink : LoreColor.bone200))
            Circle()
                .strokeBorder(
                    isCurrent || isVisited ? LoreColor.ink : LoreColor.bone300,
                    lineWidth: isCurrent ? 2 : 1
                )
            if isVisited {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LoreColor.bone)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isCurrent ? LoreColor.ink : LoreColor.ink600)
            }
        }
        .frame(width: 31, height: 31)
        .scaleEffect(isCurrent ? 1.1 : 1)
    }
}

/// Decorative route line for the editorial tour cover. Deliberately uses a
/// fixed, calm geometry rather than live animation so the card stays quiet in
/// a long scrolling detail view.
private struct TourRouteConstellation: View {
    let nodeCount: Int

    var body: some View {
        GeometryReader { proxy in
            let points = routePoints(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(
                    LoreColor.brass300.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 7])
                )

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    ZStack {
                        Circle().fill(index == points.count - 1 ? LoreColor.amber : LoreColor.brass300)
                        if index == points.count - 1 {
                            Circle().strokeBorder(LoreColor.bone.opacity(0.8), lineWidth: 1)
                                .padding(-3)
                        }
                    }
                    .frame(width: index == points.count - 1 ? 10 : 6, height: index == points.count - 1 ? 10 : 6)
                    .position(point)
                }
            }
        }
    }

    private func routePoints(in size: CGSize) -> [CGPoint] {
        let count = max(nodeCount, 2)
        return (0..<count).map { index in
            let fraction = CGFloat(index) / CGFloat(count - 1)
            let x = 8 + fraction * max(size.width - 16, 0)
            let pattern: [CGFloat] = [0.72, 0.32, 0.58, 0.2]
            return CGPoint(x: x, y: size.height * pattern[index % pattern.count])
        }
    }
}

private struct TourCompletionView: View {
    let tour: Tour
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var burst = false

    var body: some View {
        ZStack {
            LoreColor.ink950.opacity(0.94).ignoresSafeArea()
            TourRouteConstellation(nodeCount: min(max(tour.stops.count, 4), 8))
                .frame(maxWidth: 520)
                .frame(height: 230)
                .opacity(0.22)
                .rotationEffect(.degrees(-8))
                .accessibilityHidden(true)
            if !reduceMotion {
                ConfettiBurst(active: burst, tier: .gold)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 18) {
                Text(tour.displayEmoji)
                    .font(.system(size: 58))
                    .scaleEffect(appeared ? 1 : 0.65)
                Text("Walk complete")
                    .loreLabelStyle()
                    .tracking(1.2)
                    .foregroundStyle(LoreColor.brass300)
                Text(tour.title)
                    .font(LoreType.displayL)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                Text("Every stop is now part of your Lore trail. You can replay this route any time.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Back to tours", action: onDismiss)
                    .font(LoreType.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(LoreColor.bone, in: Capsule())
                    .foregroundStyle(LoreColor.ink)
                    .buttonStyle(.pressable)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Haptics.play(.badgeEarned)
            withAnimation(LoreSpring.bounce(reduceMotion: reduceMotion)) {
                appeared = true
            }
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { burst = true }
            }
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
    private(set) var loadFailed = false
    private(set) var loadSucceeded = false

    func place(id: String) -> Place? { placesByID[id] }

    func load(city: String, retry: Bool = false) async {
        guard !isLoading, retry || placesByID.isEmpty else { return }
        isLoading = true
        loadFailed = false
        loadSucceeded = false
        defer { isLoading = false }
        do {
            let places = try await LoreAPI.shared.places(city: city)
            placesByID = Dictionary(
                uniqueKeysWithValues: places.map { ($0.id, $0) }
            )
            loadSucceeded = true
        } catch is CancellationError {
            return
        } catch {
            loadFailed = true
        }
    }
}
