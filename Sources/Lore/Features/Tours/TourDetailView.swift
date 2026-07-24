import CoreLocation
import MapKit
import SwiftUI

/// One tour as a stop stepper: progress rail, current stop's place card
/// content + curator note, previous/next controls.
struct TourDetailView: View {
    let tour: Tour
    @Environment(\.dismiss) private var dismiss
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
    /// Hands-free audio-tour narration: the current stop's dossier read aloud
    /// (Lore+). Manual per-stop for now; GPS auto-advance is a device-tested
    /// follow-up. One narrator, stopped on stop-change + disappear.
    @State private var narration = NarrationService()
    @State private var currentNarrative: String?
    /// Pre-rendered studio narration for the current stop, when its dive has
    /// one (tools/narration). Preferred over TTS by every play path.
    @State private var currentAudioURL: URL?
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
    /// Restore once, then persist every manual or guided stop change.
    @State private var didRestoreProgress = false
    /// Full-screen completion beat at the final stop.
    @State private var showCompletion = false

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
            .padding(16)
        }
        .background(LoreColor.bone100)
        .navigationTitle(tour.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load(city: tour.city)
            restoreProgress()
            await loadNarrative()
            focusRouteMap()
        }
        // Push each stop change into the Live Activity so the Lock Screen /
        // Dynamic Island track the walk (docs/16 §8). No-op when not running.
        .onChange(of: stopIndex) { _, _ in
            persistProgress()
            syncLiveActivity()
            retargetGuide()
            Task { await loadNarrative() }
        }
        // A moving walker updates the Lock-Screen distance live while guiding.
        .onChange(of: walkGuide.distanceToTarget) { _, _ in
            syncLiveActivity()
        }
        // End the activity if the user leaves the tour screen without finishing.
        .onDisappear { liveActivity.end(); narration.stop(); walkGuide.stop() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .tours)
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

    // MARK: Live Activity (Lock-Screen companion)

    /// Pin the walk to the Lock Screen / Dynamic Island. Deliberately *not* the
    /// headline "start" of the tour: it drives an Activity that lives OUTSIDE the
    /// app, so tapping it changes nothing on this screen (and shows nothing at
    /// all on Simulator, which doesn't render Live Activities). It used to be
    /// labelled "Start walking tour", which read as broken. Now it names exactly
    /// what it does, with a caption, and reads as an optional extra.
    @ViewBuilder
    private var liveActivityControl: some View {
        if !tour.stops.isEmpty && liveActivity.areActivitiesEnabled {
            VStack(alignment: .leading, spacing: 6) {
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

                Text(liveActivity.isRunning
                    ? "Your current stop now shows on the Lock Screen and Dynamic Island as you walk."
                    : "Optional. Keeps your current stop on the Lock Screen and Dynamic Island so you can glance at it without opening Lore. Shows on a real iPhone, not the Simulator.")
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
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

    /// An overview map of the entire walk: every stop as a numbered pin, the
    /// current stop swollen + amber, and a dotted line threading them in order.
    /// Tapping a pin springs the stepper to that stop. The dotted segments show
    /// stop *order*, not the routed path — Apple Maps draws the real walking
    /// route from the "Walking directions" button, so this never needs a network
    /// round-trip and never shows a route it can't stand behind.
    @ViewBuilder
    private var routeMap: some View {
        let stops = orderedStopPlaces
        if stops.count >= 2 {
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
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .shadow(color: .black.opacity(0.25), radius: active ? 4 : 1, y: 1)
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

    /// The hands-free "listen to this stop" control (Lore+). Speaks the current
    /// stop's dossier so a walker can pocket the phone. Free users get a locked
    /// affordance that opens the paywall.
    @ViewBuilder
    private var audioControl: some View {
        Button {
            if entitlements.isPlus {
                Haptics.play(.chipTap)
                if narration.isSpeaking { narration.stop() }
                else if currentNarrative != nil || currentAudioURL != nil {
                    narration.narrateDossier(text: currentNarrative, audioURL: currentAudioURL)
                }
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: narration.isSpeaking ? "stop.circle.fill" : "headphones")
                    .font(.system(size: 18))
                Text(narration.isSpeaking ? "Stop audio" : "Play this stop")
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
        .disabled(entitlements.isPlus && currentNarrative == nil && currentAudioURL == nil)
        .accessibilityLabel(entitlements.isPlus
            ? (narration.isSpeaking ? "Stop audio" : "Play this stop's audio")
            : "Play this stop's audio, a Lore Plus feature")
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
                    Text(walkGuide.isGuiding ? "Guiding — auto-play is on" : "Auto-play as you walk")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                    if walkGuide.isGuiding {
                        // One honest status line: denied, locating, or a live
                        // "next waypoint · distance" once a good fix exists.
                        if walkGuide.isDenied {
                            Text("Location is off — enable it in Settings to auto-play.")
                                .font(LoreType.caption).foregroundStyle(LoreColor.error)
                        } else if let meters = walkGuide.distanceToTarget, let name = guideTargetName {
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
            ? (walkGuide.isGuiding ? "Stop auto-play guiding" : "Auto-play each stop as you walk up to it")
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
        guard let placeID = currentStop?.placeID else { return }
        let dive = (try? await LoreAPI.shared.dive(placeID: placeID)) ?? nil
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
                    withAnimation(LoreSpring.smooth(reduceMotion: reduceMotion)) { stopIndex += 1 }
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
        }
    }

    private func persistProgress() {
        guard didRestoreProgress else { return }
        TourProgressStore.save(
            stopIndex: stopIndex,
            for: tour.slug,
            userID: auth.session?.user.id
        )
    }

    private func finishTour() {
        TourProgressStore.complete(
            tourSlug: tour.slug,
            userID: auth.session?.user.id
        )
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

private struct TourCompletionView: View {
    let tour: Tour
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var burst = false

    var body: some View {
        ZStack {
            LoreColor.ink950.opacity(0.94).ignoresSafeArea()
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
