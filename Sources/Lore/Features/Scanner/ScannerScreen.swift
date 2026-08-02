import CoreLocation
import SwiftUI
import UIKit

/// The scanner viewfinder, **v2**, the intelligence layer over the coarse
/// GPS + compass pose (docs/12-SCANNER-INTELLIGENCE.md, on top of the docs/05
/// §5 rung-2 geometry). What v1 did with flat bearing chips, v2 does with the
/// full contract:
///
/// - **§3 ranking**, persona-weighted (`InterestMap.relevanceScore`) +
///   distance + gaze + novelty + context, only the top few rendered
///   (`ScannerRanking.rank`).
/// - **§2 confidence tiers, honest**, Tier A locked pin *only* when the
///   geometry earns it, Tier B floating bearing chip, Tier C directional
///   cluster with no on-building claim (`ScannerRanking.tier`).
/// - **§3.1 meanwhile-nearby stories**, moments floated at their real spot,
///   *"On this spot, 1934…"* (`StoryMarker`).
/// - **§2.1 disambiguation stack**, clustered candidates collapse into one
///   "one of these three" chip (`StackChip`).
/// - **reticle**, Amber corner-frame + scanline + breathing compass ring
///   (`ScannerReticle`, `CompassRing`).
/// - **§3.2 audio auto-offer**, a Tier-A lock offers the narrated hook
///   (`NarrationService`), hands-free docent mode.
/// - **haptics**, `.rigid` on lock, `.selection` as chips pass center
///   (brand/ELEVATION §4).
///
/// The honesty contract (docs/12 §2, docs/05 §4.2) is enforced in the ranking
/// layer, not here: this view only *renders* the tier a candidate earned.
///
/// **Precise mode (docs/05 §5 rung 1, pure Apple).** When the coverage probe
/// (`GeoScoutingService`) says Apple has VPS-class data here and the device
/// supports ARGeoTracking, a "Lock on" affordance appears in the bottom bar.
/// It swaps the AVCapture preview for `GeoARView` + `GeoARSessionController`:
/// ARGeoAnchors on the top-ranked candidates, world-locked cards at their
/// projected screen points once the tracker reports localized. While it is
/// still localizing the reticle keeps the scanning treatment; on any hard
/// failure the scanner falls silently back to this coarse mode, which stays
/// the default and the fallback (the ladder, docs/05 §5).
struct ScannerScreen: View {
    /// The shared curation prefs (persona lens for ranking + voice register).
    /// `nil` ⇒ the neutral traveler lens.
    let prefs: UserPrefs?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = ScannerModel()
    @State private var showPaywall = false
    @State private var isVisible = false
    @State private var showCameraRationale = false
    @State private var guidanceToast: ScannerGuidanceToast?
    @State private var guidanceToastTask: Task<Void, Never>?

    /// Raised so a scanner-opened place card can hand off to the city's culture
    /// surface (wired by the tab shell); the no-op default keeps previews working.
    var onMeetCity: (String) -> Void = { _ in }
    /// Raised when the user is outside scanner coverage and wants map browsing.
    var onBrowseCities: () -> Void = {}

    init(
        prefs: UserPrefs? = nil,
        onMeetCity: @escaping (String) -> Void = { _ in },
        onBrowseCities: @escaping () -> Void = {}
    ) {
        self.prefs = prefs
        self.onMeetCity = onMeetCity
        self.onBrowseCities = onBrowseCities
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScannerHeadingOrientationReader { orientation in
                    model.pose.updateHeadingOrientation(orientation)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                // The camera layer: AVCapture preview in coarse mode, the
                // shared ARSession's feed in precise mode. One owner at a
                // time; the model handles the handoff (docs/05 §5 ladder).
                if model.preciseMode {
                    GeoARView(controller: model.geoAR)
                        .ignoresSafeArea()
                } else {
                    CameraPreviewView(camera: model.camera)
                        .ignoresSafeArea()
                }

                // Reticle underlays the content so pins/chips sit on top of it.
                // It firms up on a coarse Tier-A lock or a precise localize.
                // Measured in the same (safe-area) space as the pins and chips
                // so the reticle center lines up with the content it frames (the
                // camera behind it still fills the full screen).
                ScannerReticle(isLocked: model.reticleLocked)

                if model.preciseMode {
                    // World-locked cards at the tracker's projected points;
                    // they only render once the state machine says locked.
                    geoPins
                } else {
                    lockedPin(size: proxy.size)
                        // A lock is an arrival, the pin blooms in with `spring.bounce`
                        // (its `.rigid` haptic fires in the model). Reduce Motion
                        // crossfades. Keyed on identity so only a *new* lock animates.
                        .animation(
                            LoreSpring.bounce(reduceMotion: reduceMotion),
                            value: model.lockedPlace?.id
                        )
                    bearingChips(size: proxy.size)
                        // Chips enter/leave and re-cluster on a settled spring so the
                        // field never snaps or jitters as the scan updates.
                        .animation(
                            LoreSpring.smooth(reduceMotion: reduceMotion),
                            value: model.inViewClusters.map(\.id)
                        )
                    storyMarkers(size: proxy.size)
                }

                VStack(spacing: 0) {
                    StatusChip(text: model.statusLine)
                        .padding(.top, 8)
                    if model.hasContentLoadError {
                        Button("Retry local stories") {
                            Task { await model.retryLoadedContent() }
                        }
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(LoreColor.amber, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    Spacer()
                    if let insight = model.lockedInsight, !model.preciseMode {
                        scannerInsightCard(insight)
                            .padding(.bottom, 8)
                    }
                    if let offered = model.narration.offered {
                        audioOffer(for: offered)
                            .padding(.bottom, 8)
                    }
                    if let guidanceToast, !model.preciseMode {
                        scannerGuidanceToast(guidanceToast)
                            .padding(.bottom, 10)
                    }
                    if !model.preciseMode {
                        directionalRail
                    }
                    bottomBar
                }

                // Camera/location denied: a first-class Settings path, never a
                // black viewfinder with pins floating on nothing.
                if showCameraRationale {
                    cameraRationaleOverlay
                } else if model.permissionDenied {
                    permissionOverlay
                } else if model.needsPreciseLocation {
                    preciseLocationOverlay
                } else if let message = model.cameraUnavailableMessage {
                    cameraUnavailableOverlay(message: message)
                } else if model.localContextBlocksScanning {
                    localContextOverlay
                }
            }
        }
        .background(LoreColor.ink950)
        .loreDossierPresentation(item: $model.selectedPlace) { place in
            PlaceCardView(
                place: place,
                visitSource: .scanner,
                onMeetCity: { model.selectedPlace = nil; onMeetCity($0) }
            )
        }
        .sheet(item: $model.selectedStory) { story in
            StorySheet(story: story)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
        }
        .sheet(item: $model.capturedShot) { shot in
            ARCaptureSheet(shot: shot)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .scanner)
        }
        .task {
            model.apply(prefs: prefs)
            let needsCameraRationale = model.needsCameraPermissionRationale
            showCameraRationale = needsCameraRationale
            await model.start(
                requestCameraPermission: !needsCameraRationale
            )
        }
        .onChange(of: prefs) { _, newValue in model.apply(prefs: newValue) }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            guidanceToastTask?.cancel()
            guidanceToastTask = nil
            guidanceToast = nil
            model.stopSensors()
        }
        .onChange(of: model.lockedPlace?.id) { _, newValue in
            guard newValue != nil, let locked = model.lockedRanked else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: ScannerAccessibilityAnnouncement.lockedPlace(locked)
            )
        }
        .onChange(of: model.scanState) { _, newValue in
            if case .nothingRecognized = newValue {
                showScannerGuidance(
                    ScannerGuidanceToast.unableToRead(visionPhrase: model.vision.latest.phrase)
                )
            } else {
                showScannerGuidance(nil)
            }
        }
        .onChange(of: model.identifyState) { _, newValue in
            guard let announcement = ScannerAccessibilityAnnouncement.identification(newValue) else { return }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
        // Pause camera/location/loop when the app leaves the foreground (privacy
        // + battery); resume when it returns while the scanner is the live tab.
        // Tab switches are covered by onAppear/onDisappear.
        .onChange(of: scenePhase) { _, phase in
            guard isVisible else { return }
            if phase == .active {
                model.resumeSensors(requestCameraPermission: !showCameraRationale)
            } else {
                model.stopSensors()
            }
        }
        // A fresh on-device read while nothing is locked — a gentle tick so the
        // user feels the scanner respond to what they aim at (never a buzz: the
        // recognizer is throttled to ~2 Hz and reads are mostly stable).
        .onChange(of: model.vision.latest.phrase) { old, new in
            guard case .nothingRecognized = model.scanState, let new, new != old else { return }
            Haptics.play(.scanRecognizing)
            showScannerGuidance(ScannerGuidanceToast.unableToRead(visionPhrase: new))
        }
    }

    // MARK: Tier A, the locked pin

    /// The single Tier-A resolve: a solid Amber pin anchored where the building
    /// sits in the FOV, name below (docs/12 §2 Tier A). Only one at a time —
    /// the scanner commits to one lock, not a field of confident claims.
    @ViewBuilder
    private func lockedPin(size: CGSize) -> some View {
        if let locked = model.lockedRanked {
            LockedPin(ranked: locked)
                .position(
                    x: chipX(fraction: locked.projected.screenFraction, width: size.width),
                    y: size.height * 0.42
                )
                // The pin glides to its new bearing on an interruptible spring so
                // the 5 Hz reprojection reads as smooth tracking, never jitter
                // (LUXURY-MOTION §5). Reduce Motion snaps (no interpolation).
                .animation(
                    reduceMotion ? nil : LoreSpring.smoothInteractive,
                    value: locked.projected.screenFraction
                )
                .onTapGesture {
                    Haptics.play(.dossierOpen)
                    model.select(locked.place)
                }
                // Lands with `spring.bounce` (a lock is an arrival) and leaves on
                // a crossfade; the `.rigid` lock haptic fires in the model.
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .id(locked.place.id)
        }
    }

    // MARK: Precise mode, world-locked pins (docs/05 §5 rung 1)

    /// The precise-mode render: each tracked geo anchor's `ProjectedPin`
    /// becomes a tappable card at its screen point, nearest N only, clamped
    /// into safe bounds. This layer owns the full screen (ignoring the safe
    /// area) so its coordinates match the AR view's viewport exactly.
    private var geoPins: some View {
        GeometryReader { proxy in
            ForEach(model.geoARPins) { display in
                GeoLockedPin(place: display.place, distanceM: display.pin.distanceM)
                    .position(clampToSafeBounds(display.pin.screenPoint, in: proxy.size))
                    // Track the projection on an interruptible spring so the
                    // 10 Hz snapshots read as smooth world-lock, never jitter.
                    .animation(
                        reduceMotion ? nil : LoreSpring.smoothInteractive,
                        value: display.pin.screenPoint
                    )
                    .onTapGesture {
                        Haptics.play(.dossierOpen)
                        model.select(display.place)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            .animation(
                LoreSpring.smooth(reduceMotion: reduceMotion),
                value: model.geoARPins.map(\.id)
            )
        }
        .ignoresSafeArea()
    }

    /// Clamp a projected point so a card never clips the screen edge or the
    /// status/bottom chrome; an edge-of-frame world lock stays reachable.
    private func clampToSafeBounds(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 60), size.width - 60),
            y: min(max(point.y, 120), size.height - 170)
        )
    }

    // MARK: Tier B, bearing chips + stacks

    /// Tier-B candidates inside the FOV, positioned by bearing. Clustered
    /// candidates render as a stack chip ("one of these three"); singletons as
    /// a plain bearing chip. Capped for clutter control (≤ 35% viewfinder,
    /// brand/DESIGN §4).
    @ViewBuilder
    private func bearingChips(size: CGSize) -> some View {
        ForEach(Array(model.inViewClusters.enumerated()), id: \.element.id) { index, cluster in
            Group {
                if cluster.isStack {
                    StackChip(cluster: cluster) { confirmed in
                        model.confirmFromStack(confirmed)
                    }
                } else {
                    BearingChip(ranked: cluster.lead, showArrow: false)
                        .onTapGesture { model.select(cluster.lead.place) }
                }
            }
            .position(
                x: chipX(fraction: cluster.screenFraction, width: size.width),
                y: size.height * 0.24 + CGFloat(index) * 56
            )
            // Track the bearing on an interruptible spring, a chip slides to its
            // new position rather than teleporting each reprojection frame.
            .animation(
                reduceMotion ? nil : LoreSpring.smoothInteractive,
                value: cluster.screenFraction
            )
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    // MARK: Database-backed scanner result

    /// A compact AR result card for the locked Lore database row. This is the
    /// bridge between "the scanner locked" and "here is the actual history,
    /// timeline, facts, and offers Lore has for that place."
    private func scannerInsightCard(_ insight: ScannerPlaceInsight) -> some View {
        Button {
            Haptics.play(.dossierOpen)
            model.select(insight.place)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Text(insight.place.displayEmoji)
                        .font(.system(size: 18))
                        .frame(width: 34, height: 34)
                        .background(LoreColor.ink, in: Circle())
                        .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.5), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("LORE PLACE")
                                .loreLabelStyle()
                                .foregroundStyle(LoreColor.amber)
                            Text(insight.source.badge)
                                .font(LoreType.micro)
                                .foregroundStyle(LoreColor.bone.opacity(0.72))
                                .lineLimit(1)
                        }
                        Text(insight.place.name)
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.bone)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if insight.isLoading {
                        ProgressView()
                            .tint(LoreColor.amber)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "book.pages")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(LoreColor.amber)
                    }
                }

                if let line = insight.leadLine {
                    Text(line)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.86))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !insight.badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(insight.badges, id: \.self) { badge in
                                Text(badge)
                                    .font(LoreType.micro)
                                    .foregroundStyle(LoreColor.bone)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(LoreColor.scrimFacade, in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(LoreColor.amber.opacity(0.35), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                HStack(spacing: 6) {
                    Text(insight.footerLine)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.bone.opacity(0.68))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LoreColor.amber)
                }
            }
            .padding(14)
            .frame(maxWidth: 360, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LoreColor.amber.opacity(0.48), lineWidth: 1)
            )
            .shadow(color: LoreColor.ink.opacity(0.35), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(insight.accessibilityLabel))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Scanner guidance

    private func scannerGuidanceToast(_ toast: ScannerGuidanceToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LoreColor.amber)
                .frame(width: 32, height: 32)
                .background(LoreColor.ink.opacity(0.65), in: Circle())
                .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.45), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(1)
                Text(toast.message)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LoreColor.amber.opacity(0.42), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(toast.title). \(toast.message)"))
        .id(toast.id)
    }

    private func showScannerGuidance(_ toast: ScannerGuidanceToast?) {
        guidanceToastTask?.cancel()
        guidanceToastTask = nil

        let animation = LoreSpring.smooth(reduceMotion: reduceMotion)
        guard let toast else {
            withAnimation(animation) { guidanceToast = nil }
            return
        }

        withAnimation(animation) { guidanceToast = toast }
        let toastID = toast.id
        let shouldReduceMotion = reduceMotion
        guidanceToastTask = Task {
            try? await Task.sleep(for: .milliseconds(shouldReduceMotion ? 1_800 : 2_400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard guidanceToast?.id == toastID else { return }
                withAnimation(LoreSpring.smooth(reduceMotion: shouldReduceMotion)) {
                    guidanceToast = nil
                }
            }
        }
    }

    // MARK: §3.1, meanwhile-nearby story markers

    @ViewBuilder
    private func storyMarkers(size: CGSize) -> some View {
        ForEach(Array(model.inViewStories.enumerated()), id: \.element.id) { index, projected in
            StoryMarker(projected: projected) {
                model.selectedStory = projected.story
            }
            .position(
                x: chipX(fraction: projected.screenFraction, width: size.width),
                // Fan concurrent moments down by index so markers at a similar
                // bearing don't stack on one constant y (they used to overlap).
                y: size.height * 0.58 + CGFloat(index) * 44
            )
            .animation(
                reduceMotion ? nil : LoreSpring.smoothInteractive,
                value: projected.screenFraction
            )
        }
    }

    // MARK: Tier C + off-screen, the directional rail

    /// Off-screen and Tier-C candidates as a distance-sorted bottom rail: the
    /// "Willis Tower ↖ 600 m" chips (docs/05 §5 rung 2) plus the Tier-C
    /// "that way →" hints that never claim a façade (docs/12 §2 Tier C).
    private var directionalRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.directionalCandidates) { ranked in
                    BearingChip(ranked: ranked, showArrow: true)
                        .onTapGesture { model.select(ranked.place) }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: Bottom bar, compass + shutter + mode

    private var bottomBar: some View {
        ZStack {
            if model.canCaptureMoment {
                shutterButton
            }
            HStack {
                CompassRing(headingDegrees: model.pose.headingDegrees)
                Spacer()
                if model.canLockOn
                    || model.preciseMode
                    || model.isTransitioningToPreciseMode
                    || model.isCheckingPreciseCoverage {
                    lockOnToggle
                } else {
                    // Balance the compass so the row reads symmetric.
                    Color.clear.frame(width: 52, height: 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// Contextual postcard capture: offered only after the scanner has resolved
    /// local content and the coarse camera owns the frame.
    private var shutterButton: some View {
        Button {
            Haptics.play(.scannerLock)
            Task { await model.captureMoment() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(LoreColor.bone.opacity(0.9), lineWidth: 2)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(LoreColor.bone)
                    .frame(width: 34, height: 34)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
            }
            .shadow(color: LoreColor.ink.opacity(0.4), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Capture Lore postcard"))
    }

    /// The precise-mode affordance (docs/05 §5): offered only when the
    /// coverage probe says Apple has VPS-class data here AND the hardware
    /// can run geo tracking. Coarse stays the default; this is an upgrade
    /// the user opts into, and the same button drops back down the ladder.
    private var lockOnToggle: some View {
        Button {
            Haptics.play(.chipTap)
            if model.preciseMode {
                model.exitPreciseMode()
            } else if !model.isTransitioningToPreciseMode {
                Task { await model.enterPreciseMode() }
            }
        } label: {
            HStack(spacing: 4) {
                if model.isTransitioningToPreciseMode || model.isCheckingPreciseCoverage {
                    ProgressView().tint(LoreColor.bone).controlSize(.small)
                } else {
                    Image(systemName: model.preciseMode ? "scope" : "dot.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(model.preciseButtonTitle)
                    .font(LoreType.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(model.preciseMode ? LoreColor.ink : LoreColor.bone)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                model.preciseMode ? LoreColor.amber : LoreColor.scrimFacade,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    LoreColor.amber.opacity(model.preciseMode ? 0 : 0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isTransitioningToPreciseMode || model.isCheckingPreciseCoverage)
        .accessibilityLabel(Text(
            model.isTransitioningToPreciseMode
                ? "Starting precise AR"
                : model.isCheckingPreciseCoverage
                ? "Checking precise AR coverage"
                : model.preciseMode
                ? "Precise AR on, tap to return to coarse mode"
                : "Lock on, start precise AR"
        ))
    }

    // MARK: §3.2, the audio auto-offer

    /// "Keep walking, I'll tell you", the hands-free offer that appears on a
    /// Tier-A lock (docs/12 §3.2). We offer, never auto-play (open Q4 etiquette).
    private func audioOffer(for place: Place) -> some View {
        // Two sibling controls (not a tap gesture nested in a Button): a play
        // area and a real 44pt dismiss button, so "dismiss" never mis-fires as
        // "play". Audio narration is a Lore+ perk, so a free tap opens the paywall.
        HStack(spacing: 4) {
            Button {
                if entitlements.isPlus {
                    model.playNarration(for: place)
                } else {
                    model.narration.dismissOffer()
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: entitlements.isPlus ? "headphones" : "headphones.circle")
                    Text("Keep walking, I'll tell you")
                        .font(LoreType.button)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if !entitlements.isPlus {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(LoreColor.bone)
                .padding(.leading, 16)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(entitlements.isPlus ? "Play narration" : "Unlock audio narration with Lore plus"))

            Button {
                model.narration.dismissOffer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoreColor.bone)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.trailing, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(LoreColor.amber.opacity(0.55), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Camera permission

    /// A first-run primer shown before Apple's system dialog. The camera does
    /// not start or request access until Continue; returning travelers who have
    /// already decided never see this surface.
    private var cameraRationaleOverlay: some View {
        ZStack {
            LoreColor.ink950.opacity(0.97).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LoreColor.amber)
                Text("Reveal the stories around you")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                Text("Lore uses your camera to match nearby places and layer their stories into the view. Live scanning stays on your device.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Continue") {
                    showCameraRationale = false
                    model.requestCameraAccess()
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.ink)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }

    // MARK: Permission dead-end

    /// Shown when the camera or location was denied: an honest explanation and a
    /// one-tap path to Settings, so the scanner never dead-ends on a black frame.
    private var permissionOverlay: some View {
        ZStack {
            LoreColor.ink950.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "viewfinder.trianglebadge.exclamationmark")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LoreColor.amber)
                Text(model.cameraDenied ? "The scanner needs camera access" : "The scanner needs your location")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                Text("Lore uses the camera to place stories on the buildings around you and your location to know which block you are on. Live scanning stays on your device, and Lore only opens a place when the local geospatial match earns it.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
        .transition(.opacity)
    }

    /// Approximate Location is a distinct, recoverable state. It cannot support
    /// block-level scanner claims, so request precise access before rendering
    /// any place overlay instead of telling the traveler to step outside.
    private var preciseLocationOverlay: some View {
        ZStack {
            LoreColor.ink950.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LoreColor.amber)
                Text("Turn on Precise Location")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                Text("The live scanner needs block-level location to place nearby stories honestly. Map and Tours still work with Approximate Location.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use Precise Location") {
                    model.requestPreciseLocation()
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.ink)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                .buttonStyle(.plain)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.brass300)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }

    /// Permission can be granted while camera hardware is absent or busy. Treat
    /// that as a recoverable degraded mode, not a black screen or a false prompt.
    private func cameraUnavailableOverlay(message: String) -> some View {
        ZStack {
            LoreColor.ink950.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill.badge.ellipsis")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(LoreColor.amber)
                Text("Live scanner unavailable")
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                Text(message)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(cameraFallbackCopy)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try camera again") {
                    model.retryCamera()
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.ink)
                .padding(.horizontal, 22)
                .frame(height: 46)
                .background(LoreColor.amber, in: Capsule())
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }

    /// Scanner coverage is resolved from the live device location. When someone
    /// is browsing a far-away city, this keeps camera claims local and gives a
    /// clean route back to map exploration.
    private var localContextOverlay: some View {
        ZStack {
            LoreColor.ink950.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: localContextIcon)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LoreColor.amber)
                Text(localContextTitle)
                    .font(LoreType.displayM)
                    .foregroundStyle(LoreColor.bone)
                    .multilineTextAlignment(.center)
                Text(localContextMessage)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if model.canRetryLocalContext {
                    Button("Try again") {
                        model.retryLocalContext()
                    }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.ink)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(LoreColor.amber, in: Capsule())
                    .buttonStyle(.plain)
                }

                Button("Browse city maps") {
                    onBrowseCities()
                }
                .font(LoreType.button)
                .foregroundStyle(LoreColor.brass300)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 430)
        }
        .accessibilityElement(children: .contain)
        .transition(.opacity)
    }

    private var localContextIcon: String {
        switch model.localContext {
        case .waitingForLocation, .loadingCities:
            return "location.magnifyingglass"
        case .unavailable:
            return "wifi.exclamationmark"
        case .outsideCoverage:
            return "map.fill"
        case .locked:
            return "camera.viewfinder"
        }
    }

    private var localContextTitle: String {
        switch model.localContext {
        case .waitingForLocation:
            return "Finding your block"
        case .loadingCities:
            return "Checking Lore coverage"
        case .unavailable:
            return "Coverage unavailable"
        case .outsideCoverage:
            return "No live scanner coverage here"
        case .locked:
            return "Scanner ready"
        }
    }

    private var localContextMessage: String {
        switch model.localContext {
        case .waitingForLocation:
            return "Lore is waiting for a current location before it loads nearby scanner stories."
        case .loadingCities:
            return "Lore is matching your current location to a live city catalog."
        case .unavailable:
            return "Lore could not load the live city roster. Map and Tours still work from the city browser."
        case .outsideCoverage(let nearest, let distance):
            if let nearest, let distance {
                return "The nearest scanner city is \(nearest.name), \(distanceLabel(distance)) away. Explore by map or try the scanner when you arrive."
            }
            return "Explore by map or try the scanner when you are in a live Lore city."
        case .locked(let city):
            return "Loading \(city.name)'s nearby stories."
        }
    }

    private func distanceLabel(_ meters: CLLocationDistance) -> String {
        if meters >= 1_000 {
            return String(format: "%.0f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private var cameraFallbackCopy: String {
        #if targetEnvironment(simulator)
        return "You can still explore every place from Map and Tours. Simulator has no live camera; use a real iPhone for scanning and AR."
        #else
        return "You can still explore every place from Map and Tours while the camera is unavailable."
        #endif
    }

    // MARK: Layout

    /// Clamp a screen fraction into the safe band so a chip never clips the
    /// edge; off-screen candidates live in the rail, not here.
    private func chipX(fraction: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(max(fraction, 0.10), 0.90)) * width
    }
}

// MARK: - Tier A pin

/// The Tier-A locked pin: compound Amber teardrop (Amber fill + Ink stroke +
/// Ink shadow, brand/DESIGN §4) with the name on a scrim below. The one
/// on-building claim the scanner is willing to make.
struct LockedPin: View {
    let ranked: ScannerRanking.Ranked

    private var accessibilityText: String {
        if ranked.projected.isAtLocation {
            return "\(ranked.place.name), locked, you're here"
        }
        return "\(ranked.place.name), locked, \(ranked.projected.distanceLabel) ahead"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LoreColor.amber)
                    .background(Circle().fill(LoreColor.ink).padding(6))
                    .shadow(color: LoreColor.ink.opacity(0.35), radius: 3, x: 0, y: 1)
                Text(ranked.place.displayEmoji)
                    .font(.system(size: 14))
            }
            Text(ranked.place.name)
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(LoreColor.scrimSky, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Precise-mode pin (docs/05 §5 rung 1)

/// The world-locked card of precise mode: the same Amber teardrop language
/// as `LockedPin`, plus a live distance caption, anchored at an ARGeoAnchor's
/// projected screen point instead of a bearing estimate. Every one of these
/// is a Tier-A claim, which is why the model only surfaces them while the
/// tracker reports locked (docs/05 §4.2 honesty contract).
struct GeoLockedPin: View {
    let place: Place
    let distanceM: Double

    private var distanceLabel: String {
        BearingProjector.distanceLabel(meters: distanceM)
    }

    private var accessibilityText: String {
        if distanceM <= BearingProjector.atLocationThresholdMeters {
            return "\(place.name), pinned, you're here"
        }
        return "\(place.name), pinned, \(distanceLabel) ahead"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(LoreColor.amber)
                    .background(Circle().fill(LoreColor.ink).padding(6))
                    .shadow(color: LoreColor.ink.opacity(0.35), radius: 3, x: 0, y: 1)
                Text(place.displayEmoji)
                    .font(.system(size: 14))
            }
            VStack(spacing: 1) {
                Text(place.name)
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.bone)
                    .lineLimit(1)
                Text(distanceLabel)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.amber)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(LoreColor.scrimSky, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Bearing chip (Tier B / directional)

/// A scanner label chip: scrim-backed (never raw text on camera,
/// brand/DESIGN §4), emoji + name + arrow/distance. Matched-interest places
/// carry a brighter Amber edge so the "for you" nudge is visible (docs/12 §3).
struct BearingChip: View {
    let ranked: ScannerRanking.Ranked
    let showArrow: Bool

    private var projected: ProjectedPlace { ranked.projected }
    private var isForYou: Bool { !ranked.matchedInterests.isEmpty }
    private var accessibilityText: String {
        if projected.isAtLocation {
            return "\(projected.place.name), you're here"
        }
        return "\(projected.place.name), \(projected.distanceLabel) away"
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(projected.place.displayEmoji)
                .font(.system(size: 13))
            Text(projected.place.name)
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
            Text(caption)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.amber)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LoreColor.scrimSky, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                LoreColor.amber.opacity(isForYou ? 0.9 : 0.55),
                lineWidth: isForYou ? 1.5 : 1
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        showArrow ? "\(projected.arrow) \(projected.distanceLabel)" : projected.distanceLabel
    }
}

private struct ScannerHeadingOrientationReader: UIViewRepresentable {
    let onChange: (UIInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> ScannerHeadingOrientationView {
        ScannerHeadingOrientationView(onChange: onChange)
    }

    func updateUIView(_ view: ScannerHeadingOrientationView, context: Context) {
        view.onChange = onChange
        view.publishCurrentOrientation()
    }
}

private final class ScannerHeadingOrientationView: UIView {
    var onChange: (UIInterfaceOrientation) -> Void
    private var lastOrientation: UIInterfaceOrientation?

    init(onChange: @escaping (UIInterfaceOrientation) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        isOpaque = false
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        publishCurrentOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishCurrentOrientation()
    }

    func publishCurrentOrientation() {
        guard let orientation = window?.windowScene?.interfaceOrientation,
              orientation != .unknown,
              orientation != lastOrientation
        else { return }
        lastOrientation = orientation
        DispatchQueue.main.async { [weak self] in
            self?.onChange(orientation)
        }
    }
}

// MARK: - Model

/// A `ProjectedPin` joined back to its `Place` for rendering. Identity is
/// the anchor id so SwiftUI diffing tracks anchors, not screen points.
struct GeoPinDisplay: Identifiable {
    let anchorID: UUID
    let place: Place
    let pin: ProjectedPin
    var id: UUID { anchorID }
}

struct ScannerGuidanceToast: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String

    static func unableToRead(visionPhrase: String?) -> ScannerGuidanceToast {
        let phrase = visionPhrase?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let phrase, !phrase.isEmpty {
            return ScannerGuidanceToast(
                title: "Try again",
                message: "No nearby place matched. Try a clearer angle.",
                systemImage: "arrow.clockwise"
            )
        }

        return ScannerGuidanceToast(
            title: "Unable to read",
            message: "Aim at a clearer facade, sign, or landmark nearby.",
            systemImage: "viewfinder"
        )
    }
}

/// A cloud landmark identification (Google Cloud Vision), the opt-in "what is
/// this?" tap. A real, specific name — the honest thing on-device Vision can't
/// give — labeled as a cloud ID.
struct LandmarkID: Equatable {
    let name: String
    let confidence: Double?
    /// The Lore place slug if this landmark sits on one we know (so we can open
    /// its real story), else nil.
    let slug: String?
    let placeID: String?
    let placeCity: String?

    init?(
        name: String,
        confidence: Double?,
        slug: String?,
        placeID: String? = nil,
        placeCity: String? = nil
    ) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }
        self.name = cleanedName
        if let confidence, confidence.isFinite {
            self.confidence = min(max(confidence, 0), 1)
        } else {
            self.confidence = nil
        }
        let cleanedSlug = slug?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.slug = cleanedSlug?.isEmpty == false ? cleanedSlug : nil
        let cleanedPlaceID = placeID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.placeID = cleanedPlaceID?.isEmpty == false ? cleanedPlaceID : nil
        let cleanedCity = placeCity?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.placeCity = cleanedCity?.isEmpty == false ? cleanedCity : nil
    }

    /// Cloud labels below this threshold are possibilities, not identities.
    var isAmbiguous: Bool { confidence.map { $0 < 0.70 } ?? true }
}

enum IdentifyFailure: Equatable {
    case capture
    case network
    case service
    case invalidResponse
    case membership

    var message: String {
        switch self {
        case .capture: return "Lore couldn't grab that frame. Aim again and retry."
        case .network: return "Landmark ID needs a connection. Check your signal and retry."
        case .service: return "Google landmark matching is temporarily unavailable. Try again in a moment."
        case .invalidResponse: return "The match came back incomplete, so Lore didn't guess. Try another angle."
        case .membership: return "Lore+ couldn't be verified for cloud identification. Sign in and restore purchases, then try again."
        }
    }
}

/// The state of the opt-in cloud landmark identification.
enum IdentifyState: Equatable {
    case idle          // not asked
    case loading       // one frame in flight to the cloud
    case result(LandmarkID)
    case none          // ran, cloud recognized no landmark
    case unavailable(IdentifyFailure)
    case quotaReached  // authenticated daily quota exhausted
}

enum ScannerMatchSource: Equatable {
    case geometryLock
    case preciseAR
    case marker
    case cloud

    var badge: String {
        switch self {
        case .geometryLock: return "geometry lock"
        case .preciseAR: return "precise AR"
        case .marker: return "Lore marker"
        case .cloud: return "Google assisted"
        }
    }
}

struct ScannerPlaceInsight: Identifiable, Equatable {
    let place: Place
    let source: ScannerMatchSource
    let distanceLabel: String?
    let isAtLocation: Bool
    let isLoading: Bool
    let dive: Dive?
    let facts: [Fact]
    let dealCount: Int?

    var id: String { place.id }

    var leadLine: String? {
        if let teaser = Self.clean(place.teaser) { return teaser }
        if let narrative = Self.clean(dive?.narrative) { return Self.firstSentence(narrative) }
        if let event = dive?.timeline.first {
            let detail = Self.clean(event.detail)
            return detail.map { "\(event.year): \($0)" } ?? "\(event.year): \(event.title)"
        }
        return nil
    }

    var badges: [String] {
        var out: [String] = []
        if let distanceLabel { out.append(distanceLabel) }
        if let year = place.layer1?.yearBuilt { out.append("Built \(year)") }
        if let style = Self.clean(place.layer1?.style) { out.append(style) }
        if let timelineCount = dive?.timeline.count, timelineCount > 0 {
            out.append(timelineCount == 1 ? "1 timeline note" : "\(timelineCount) timeline notes")
        }
        if vettedFactCount > 0 {
            out.append(vettedFactCount == 1 ? "1 vetted fact" : "\(vettedFactCount) vetted facts")
        } else if sourceBackedFactCount > 0 {
            out.append(sourceBackedFactCount == 1 ? "1 sourced fact" : "\(sourceBackedFactCount) sourced facts")
        }
        if let dealCount, dealCount > 0 {
            out.append(dealCount == 1 ? "1 offer" : "\(dealCount) offers")
        }
        if dive?.audioURL != nil { out.append("Narration") }
        return Array(out.prefix(6))
    }

    var footerLine: String {
        if isLoading { return "Loading dossier, timeline, and offers" }
        var sections: [String] = []
        if dive?.narrative?.isEmpty == false { sections.append("history") }
        if dive?.timeline.isEmpty == false { sections.append("timeline") }
        if sourceBackedFactCount > 0 { sections.append("sources") }
        if (dealCount ?? 0) > 0 { sections.append("offers") }
        if sections.isEmpty { return "Open the full place dossier" }
        return "Open \(sections.joined(separator: ", "))"
    }

    var accessibilityLabel: String {
        let distance = distanceLabel.map { ", \($0)" } ?? ""
        return "\(place.name), Lore place, \(source.badge)\(distance). \(footerLine)."
    }

    private var sourceBackedFactCount: Int {
        facts.filter {
            Self.clean($0.source) != nil || Self.clean($0.sourceURL) != nil
        }.count
    }

    private var vettedFactCount: Int {
        facts.filter {
            guard let state = Self.clean($0.verifyState)?.lowercased() else { return false }
            return Self.acceptedVerifyStates.contains(state)
        }.count
    }

    private static let acceptedVerifyStates: Set<String> = [
        "approved", "verified", "reviewed", "promoted", "public", "accepted",
    ]

    private static func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstSentence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            let sentence = String(trimmed[...end])
            return sentence.count <= 180 ? sentence : String(sentence.prefix(177)) + "..."
        }
        return trimmed.count <= 180 ? trimmed : String(trimmed.prefix(177)) + "..."
    }
}

struct ScannerConfirmationFeedback: Equatable {
    let placeName: String
    let distanceLabel: String
    let isAtLocation: Bool

    private var displayName: String {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Place" : trimmed
    }

    var statusLine: String {
        "Confirmed \(displayName)"
    }

    var accessibilityAnnouncement: String {
        if isAtLocation {
            return "\(displayName) selected from the stack. You're here."
        }
        return "\(displayName) selected from the stack. \(distanceLabel) ahead."
    }
}

enum ScannerAccessibilityAnnouncement {
    static func lockedPlace(_ ranked: ScannerRanking.Ranked) -> String {
        lockedPlace(
            name: ranked.place.name,
            distanceLabel: ranked.projected.distanceLabel,
            isAtLocation: ranked.projected.isAtLocation
        )
    }

    static func lockedPlace(
        name: String,
        distanceLabel: String,
        isAtLocation: Bool
    ) -> String {
        if isAtLocation { return "\(name) locked. You're here." }
        return "\(name) locked. \(distanceLabel) ahead."
    }

    static func identification(_ state: IdentifyState) -> String? {
        switch state {
        case .idle:
            return nil
        case .loading:
            return "Identifying one camera frame with Google Cloud Vision."
        case .result(let landmark):
            let prefix = landmark.isAmbiguous ? "Possible landmark" : "Landmark identified"
            if landmark.slug != nil || landmark.placeID != nil {
                return "\(prefix): \(landmark.name). Story available."
            }
            return "\(prefix): \(landmark.name)."
        case .none:
            return "No landmark matched. Lore will not guess."
        case .unavailable(let failure):
            return failure.message
        case .quotaReached:
            return "Today's landmark limit has been reached. Try again tomorrow."
        }
    }
}

enum LandmarkRequestOutcome: Equatable {
    case completed
    case unauthorized
    case plusRequired
}

/// The `landmark-id` edge function's JSON shape.
struct LandmarkResponse: Decodable {
    let landmark: String
    let confidence: Double?
    let slug: String?
    let placeID: String?
    let placeCity: String?

    enum CodingKeys: String, CodingKey {
        case landmark, confidence, slug
        case placeID = "place_id"
        case placeCity = "place_city"
    }
}

/// The opt-in is account-scoped, not device-scoped. A shared iPad or a sign-out
/// followed by another Lore account must show Google's one-photo disclosure to
/// the new person before any frame can leave the device.
enum CloudLandmarkDisclosureConsent {
    private static let keyPrefix = "lore.cloudLandmarkDisclosureAccepted.v2"

    static func hasAccepted(
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let key = key(userID: userID) else { return false }
        return defaults.bool(forKey: key)
    }

    static func accept(
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        guard let key = key(userID: userID) else { return }
        defaults.set(true, forKey: key)
    }

    private static func key(userID: String?) -> String? {
        guard let normalized = userID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !normalized.isEmpty
        else { return nil }
        return "\(keyPrefix).\(normalized)"
    }
}

/// The one always-alive scanner state. Every reproject resolves to exactly one
/// of these — there is no silent path. Drives the status line, the on-frame
/// readout, and the feedback haptics.
enum ScanState: Equatable {
    /// No usable GPS/heading yet — the scanner is warming up.
    case acquiringSensors
    /// Warming up has dragged on (often indoors) — nudge to step outside.
    case searchingOutside
    /// The traveler granted only Approximate Location, which cannot support
    /// honest block-level overlays.
    case preciseLocationRequired
    /// A current location exists but no valid compass heading arrived.
    case headingUnavailable
    /// Local city coverage is being resolved or content is loading.
    case resolvingCoverage
    /// The user is outside the scanner radius of every live city.
    case outsideCoverage
    /// The local coverage roster or content request failed.
    case coverageUnavailable
    /// Known places resolved around the user (a lock, chips, or rail hints).
    case foundNearby(Int)
    /// Sensors are ready but Lore knows nothing here; the honest on-device
    /// read (if any) and a "point at a real landmark" nudge are shown.
    case nothingRecognized
}

@Observable
@MainActor
final class ScannerModel {
    let camera = ScannerCameraService()
    let pose = LocationHeadingProvider()
    let scouting = GeoScoutingService()
    let narration = NarrationService()
    /// On-device Vision read of the live frame (honest category + visible text).
    /// Fused with the geospatial ranking so the scanner responds to what the
    /// camera actually sees, never a specific landmark name (that's cloud-only).
    let vision = VisionRecognitionService()
    /// The precise pipeline (docs/05 §5 rung 1): Apple ARGeoTracking behind
    /// the `VPSProvider` seam. Idle until the user opts in via "Lock on".
    let geoAR = GeoARSessionController()

    /// True while the precise pipeline owns the viewfinder. Coarse mode is
    /// the default and the fallback; this only flips on an explicit upgrade.
    private(set) var preciseMode = false
    private(set) var isTransitioningToPreciseMode = false
    private var preciseTransitionID: UUID?
    private(set) var preciseFallbackNotice: String?
    private var preciseNoticeTask: Task<Void, Never>?

    private(set) var places: [Place] = []
    private(set) var stories: [Story] = []
    private(set) var prefs: UserPrefs?
    private(set) var localContext: ScannerLocalContext = .waitingForLocation

    /// The current frame, resolved into tiers and clusters.
    private(set) var lockedRanked: ScannerRanking.Ranked?
    private(set) var inViewClusters: [ScannerRanking.Cluster] = []
    private(set) var inViewStories: [ProjectedStory] = []
    private(set) var directionalCandidates: [ScannerRanking.Ranked] = []

    /// The always-alive state (never silent). Resolved every reproject.
    private(set) var scanState: ScanState = .acquiringSensors
    /// When coarse acquisition started with no fix yet, so a long dead wait can
    /// escalate its copy ("try stepping outside") instead of spinning forever.
    private var acquiringSince: Date?

    /// The opt-in cloud landmark identification (Google Cloud Vision), fired one
    /// frame per explicit tap in the nothing-recognized state.
    private(set) var identifyState: IdentifyState = .idle
    /// A short local acknowledgement after the traveler resolves a dense stack.
    /// Durable verification remains server-owned; this only confirms selection.
    private(set) var stackConfirmationFeedback: ScannerConfirmationFeedback?
    private var stackConfirmationTask: Task<Void, Never>?
    /// Compact database-backed card for the current lock. Hydrated from the
    /// same PostgREST surfaces as the full dossier, and cleared the instant the
    /// lock is lost so stale history never follows the camera.
    private(set) var lockedInsight: ScannerPlaceInsight?
    private var lockedInsightTask: Task<Void, Never>?
    private var lockedInsightKey: String?

    /// Places the user has ever opened, the novelty signal (docs/12 §3 `w_fresh`).
    /// Persisted across launches so a repeat visitor stops re-scoring already-seen
    /// buildings as novel (was in-memory only, reset every launch).
    private static let seenDefaultsKey = "lore.scanner.seenPlaceIDs.v1"
    private var seenPlaceIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: ScannerModel.seenDefaultsKey) ?? []) {
        didSet {
            UserDefaults.standard.set(Array(seenPlaceIDs), forKey: ScannerModel.seenDefaultsKey)
        }
    }

    var selectedPlace: Place?
    var selectedStory: Story?
    /// A frozen frame awaiting the AR-postcard share sheet. Nil when idle.
    var capturedShot: CapturedShot?

    /// The night/haunted layer toggle (docs/12 §3.1 layer 3). Opt-in only.
    private(set) var hauntedOnly = false

    /// Permission dead-ends: true when the camera or location was denied, so the
    /// scanner shows a Settings path instead of a black / empty viewfinder.
    private(set) var cameraDenied = false
    private(set) var locationDenied = false
    private(set) var cameraUnavailableMessage: String?
    var permissionDenied: Bool { cameraDenied || locationDenied }
    var needsPreciseLocation: Bool {
        pose.isAuthorized && !pose.hasPreciseLocation
    }

    private var loadError = false
    private var isLoadingContent = false
    var hasContentLoadError: Bool { loadError }
    private var contentLoadID = UUID()
    private var availableCities: [City]?
    private var cityRosterTask: Task<Void, Never>?
    private var cityRosterLoadFailed = false
    /// Coverage is area-specific. Re-probe after a meaningful move instead of
    /// keeping the first block's result for the rest of the app session.
    private var lastScoutedLocation: CLLocation?
    private var projectionTask: Task<Void, Never>?
    /// Temporal lock hysteresis (scanner-lab port): confirms a Tier A over
    /// ~400ms and holds it ~650ms across gate jitter so pins never flicker.
    private let tierStabilizer = ScannerRanking.TierStabilizer()

    /// The place currently locked (Tier A), for the reticle "firm up" state.
    var lockedPlace: Place? { lockedRanked?.place }

    /// True when any nearby story is haunted, gates the "Spooky nearby" toggle.
    var hasHauntedNearby: Bool { inViewStories.contains { $0.story.isHaunted } || stories.contains(where: \.isHaunted) }

    var statusLine: String {
        if loadError { return "Couldn't load \(CityPackStore.label(loadedCity ?? "city")) stories" }
        if let preciseFallbackNotice { return preciseFallbackNotice }
        if let stackConfirmationFeedback { return stackConfirmationFeedback.statusLine }
        if isTransitioningToPreciseMode { return "Starting precise mode…" }
        if preciseMode {
            // The precise ladder rung narrated honestly: localizing keeps
            // the searching language, locked earns the claim (docs/05 §5).
            switch geoAR.state {
            case .idle, .initializing: return "Precise mode · starting…"
            case .localizing: return "Locking on · aim at the buildings"
            case .locked: return "Locked · precise mode"
            case .failed: return "Precise mode unavailable here"
            }
        }
        // Coarse mode reflects the always-alive state honestly.
        switch scanState {
        case .acquiringSensors:
            return pose.statusLine + scouting.statusSuffix
        case .searchingOutside:
            return L10n.t("scan.stepOutside")
        case .preciseLocationRequired:
            return "Precise Location is off"
        case .headingUnavailable:
            return "Compass unavailable · try away from magnetic interference"
        case .resolvingCoverage:
            return "Finding local Lore coverage"
        case .outsideCoverage:
            return "Scanner coverage not available here"
        case .coverageUnavailable:
            return "Couldn't check local scanner coverage"
        case .foundNearby(let n):
            return String(format: L10n.t("scan.foundNearby"), n) + scouting.statusSuffix
        case .nothingRecognized:
            return L10n.t("scan.nothingHere")
        }
    }

    /// The reticle firms up on a Tier-A commitment in either mode: a coarse
    /// lock, or the precise tracker reaching localized.
    var reticleLocked: Bool {
        preciseMode ? geoAR.state == .locked : lockedPlace != nil
    }

    var localContextBlocksScanning: Bool { localContext.isBlockingScanner }

    var canRetryLocalContext: Bool {
        switch localContext {
        case .unavailable, .outsideCoverage:
            return true
        case .waitingForLocation, .loadingCities, .locked:
            return false
        }
    }

    var canCaptureMoment: Bool {
        ScannerCapturePolicy.canCaptureMoment(
            preciseMode: preciseMode,
            isTransitioningToPreciseMode: isTransitioningToPreciseMode,
            permissionDenied: permissionDenied,
            needsPreciseLocation: needsPreciseLocation,
            localContextBlocksScanning: localContextBlocksScanning,
            isLoadingContent: isLoadingContent,
            hasLockedPlace: lockedRanked != nil
        )
    }

    /// Whether the "Lock on" upgrade is offered: coverage scouted available
    /// (docs/05 §5 tier hook) AND this hardware can run geo tracking AND we
    /// have a fix to rank candidates from. Coarse remains the default.
    var canLockOn: Bool {
        !preciseMode
            && !isTransitioningToPreciseMode
            && scouting.availability == .available
            && GeoARSessionController.isSupported
            && pose.freshLocation() != nil
            && pose.freshHeading() != nil
            && !places.isEmpty
    }

    var isCheckingPreciseCoverage: Bool {
        !preciseMode
            && !isTransitioningToPreciseMode
            && scouting.availability == .checking
            && GeoARSessionController.isSupported
            && pose.freshLocation() != nil
            && pose.freshHeading() != nil
            && !places.isEmpty
    }

    var preciseButtonTitle: String {
        if isTransitioningToPreciseMode { return "Starting" }
        if isCheckingPreciseCoverage { return "Checking" }
        return preciseMode ? "Precise on" : "Lock on"
    }

    /// The precise-mode render set: in-front projections only, joined back
    /// to their `Place`, nearest first, capped for clutter (the anchor cap
    /// already bounds this at 8; the render cap keeps a dense block
    /// readable, same budget thinking as the coarse chip field).
    var geoARPins: [GeoPinDisplay] {
        guard preciseMode, geoAR.state == .locked else { return [] }
        let displays = geoAR.projections.compactMap { anchorID, pin -> GeoPinDisplay? in
            guard pin.isInFront else { return nil }
            guard let place = places.first(where: { $0.id == pin.placeID }) else { return nil }
            return GeoPinDisplay(anchorID: anchorID, place: place, pin: pin)
        }
        return Array(displays.sorted { $0.pin.distanceM < $1.pin.distanceM }.prefix(6))
    }

    /// The city the current places/stories were loaded for, so a city switch
    /// only refetches when it actually changed.
    private var loadedCity: String?

    var needsCameraPermissionRationale: Bool {
        camera.needsPermissionRationale
    }

    /// Adopt the shared curation prefs (persona lens). Cheap and idempotent —
    /// called on appear and whenever the app's prefs change.
    func apply(prefs: UserPrefs?) {
        self.prefs = prefs
    }

    func start(requestCameraPermission: Bool = true) async {
        // Marker rung (docs/05 §5, rung 0): a scanned Lore QR is ground truth
        // at a known point, an instant honest resolve no GPS could earn.
        camera.onMarkerSlug = { [weak self] slug in
            guard let self else { return }
            guard let place = self.places.first(where: { $0.slug == slug }) else { return }
            Haptics.play(.scannerLock)
            self.hydrateInsight(for: place, source: .marker, distanceLabel: "You're here", isAtLocation: true)
            self.selectedPlace = place
        }
        // Surface permission dead-ends. Start optimistic; the callbacks re-raise
        // if still denied, so a grant from Settings clears the overlay.
        cameraDenied = false
        locationDenied = false
        cameraUnavailableMessage = nil
        camera.onPermissionDenied = { [weak self] in self?.cameraDenied = true }
        camera.onUnavailable = { [weak self] message in self?.cameraUnavailableMessage = message }
        pose.onPermissionDenied = { [weak self] in self?.locationDenied = true }
        // Feed live frames to the on-device recognizer. Capture the service (not
        // self) so the closure runs cleanly off the main actor; frames never
        // leave the device — they go straight to Apple Vision on-device.
        let recognizer = vision
        camera.onFrame = { buffer, orientation in
            recognizer.recognize(pixelBuffer: buffer, orientation: orientation)
        }
        camera.start(requestPermissionIfNeeded: requestCameraPermission)
        pose.start()
        // A single "I'm awake and looking" pulse so raising the phone always
        // *feels* like the scan began (the old scanner started dead-silent).
        Haptics.play(.scanAttempt)
        acquiringSince = Date()
        startProjectionLoop()
        resolveLocalContext(location: pose.freshLocation())
        ensureCityRosterLoaded()
    }

    func retryLoadedContent() async {
        guard let city = localContext.lockedCity?.slug ?? loadedCity else { return }
        await loadContent(city: city)
    }

    func retryLocalContext() {
        cityRosterTask?.cancel()
        cityRosterTask = nil
        availableCities = nil
        cityRosterLoadFailed = false
        resolveLocalContext(location: pose.freshLocation())
        ensureCityRosterLoaded(force: true)
    }

    private func loadContent(city: String) async {
        let requestID = UUID()
        contentLoadID = requestID
        loadedCity = city
        loadError = false
        isLoadingContent = true
        places = []
        stories = []
        lockedRanked = nil
        inViewClusters = []
        inViewStories = []
        directionalCandidates = []
        async let placesResult: [Place] = LoreAPI.shared.places(city: city)
        async let storiesResult: [Story] = (try? await LoreAPI.shared.stories(city: city)) ?? []
        do {
            let (newPlaces, newStories) = try await (placesResult, storiesResult)
            guard contentLoadID == requestID else { return }
            places = newPlaces
            stories = newStories
            isLoadingContent = false
            reproject()
        } catch {
            guard contentLoadID == requestID else { return }
            isLoadingContent = false
            loadError = true
            setScanState(.coverageUnavailable)
        }
    }

    func stopSensors() {
        preciseTransitionID = nil
        isTransitioningToPreciseMode = false
        camera.stop()
        camera.onFrame = nil
        vision.reset()
        identifyState = .idle
        pose.stop()
        narration.stop()
        // Leaving the screen always lands back on the coarse default; the
        // next appearance starts clean and re-offers the upgrade.
        if preciseMode {
            preciseMode = false
            geoAR.stop()
        }
        projectionTask?.cancel()
        projectionTask = nil
        cityRosterTask?.cancel()
        cityRosterTask = nil
        preciseNoticeTask?.cancel()
        preciseNoticeTask = nil
        stackConfirmationTask?.cancel()
        stackConfirmationTask = nil
        stackConfirmationFeedback = nil
        clearLockedInsight()
        tierStabilizer.reset()
    }

    /// Restart the coarse sensors after a foreground return (the content is
    /// already loaded, so this only re-wakes the camera, pose, and 5 Hz loop).
    /// Precise mode is torn down on background and re-offered, never auto-resumed.
    func resumeSensors(requestCameraPermission: Bool = true) {
        guard !preciseMode, projectionTask == nil else { return }
        cameraDenied = false
        locationDenied = false
        cameraUnavailableMessage = nil
        let recognizer = vision
        camera.onFrame = { buffer, orientation in
            recognizer.recognize(pixelBuffer: buffer, orientation: orientation)
        }
        camera.start(requestPermissionIfNeeded: requestCameraPermission)
        pose.start()
        Haptics.play(.scanAttempt)
        acquiringSince = Date()
        startProjectionLoop()
    }

    func retryCamera() {
        cameraUnavailableMessage = nil
        camera.start(requestPermissionIfNeeded: true)
    }

    func requestCameraAccess() {
        cameraDenied = false
        cameraUnavailableMessage = nil
        camera.start(requestPermissionIfNeeded: true)
    }

    func requestPreciseLocation() {
        pose.requestPreciseLocation()
    }

    // MARK: Precise mode (docs/05 §5 ladder, rung 1)

    /// Upgrade to the precise pipeline: hand the camera to the ARSession and
    /// anchor the top-ranked candidates as ARGeoAnchors. Coarse remains the
    /// fallback at every step; any hard failure lands in exitPreciseMode().
    func enterPreciseMode() async {
        guard !preciseMode, !isTransitioningToPreciseMode,
              let location = pose.freshLocation(),
              let heading = pose.freshHeading()
        else { return }

        // Rank the whole nearby field, not just the current FOV, so anchors
        // cover what the user will sweep to. Ranked first, nearest breaking
        // ties via the proximity term; the controller caps at its quota.
        let projected = BearingProjector.project(
            places: places,
            from: location,
            heading: heading.degrees,
            fovDegrees: camera.horizontalFOVDegrees
        )
        let quality = ScannerRanking.PoseQuality(
            horizontalAccuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 30,
            headingAccuracyDeg: heading.accuracy,
            hasVPS: false
        )
        let ranked = ScannerRanking.rank(
            projected,
            prefs: prefs,
            quality: quality,
            seenPlaceIDs: seenPlaceIDs,
            visionRead: vision.latest
        )
        guard !ranked.isEmpty else { return }

        let transitionID = UUID()
        preciseTransitionID = transitionID
        isTransitioningToPreciseMode = true
        preciseFallbackNotice = nil
        narration.dismissOffer()
        // One camera owner at a time: the AVCapture preview yields to ARKit.
        await camera.stopAndWait()
        guard preciseTransitionID == transitionID else { return }
        preciseTransitionID = nil
        isTransitioningToPreciseMode = false
        preciseMode = true
        // Clear the coarse frame so nothing stale flashes on the way back.
        lockedRanked = nil
        inViewClusters = []
        inViewStories = []
        directionalCandidates = []
        clearLockedInsight()
        geoAR.start(candidates: ranked.map(\.place))
    }

    /// Fall back down the ladder (docs/05 §5: transitions are silent and
    /// fast, the pins soften into labels). Called on the user toggle and
    /// automatically by the watchdog on a hard tracking failure.
    func exitPreciseMode() {
        guard preciseMode else { return }
        preciseMode = false
        geoAR.stop()
        camera.start(requestPermissionIfNeeded: true)
        reproject()
    }

    private func fallBackFromPreciseMode(_ failure: VPSFailure) {
        let message: String
        switch failure {
        case .unsupported: message = "Precise AR isn't supported here · using compass mode"
        case .trackingLost: message = "Precise lock was lost · using compass mode"
        case .sessionError: message = "AR was interrupted · using compass mode"
        }
        exitPreciseMode()
        preciseFallbackNotice = message
        preciseNoticeTask?.cancel()
        preciseNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.preciseFallbackNotice = nil
        }
    }

    // MARK: Scanner result hydration

    private func hydrateInsight(
        for ranked: ScannerRanking.Ranked,
        source: ScannerMatchSource = .geometryLock
    ) {
        hydrateInsight(
            for: ranked.place,
            source: source,
            distanceLabel: ranked.projected.distanceLabel,
            isAtLocation: ranked.projected.isAtLocation
        )
    }

    private func hydrateInsight(
        for place: Place,
        source: ScannerMatchSource,
        distanceLabel: String? = nil,
        isAtLocation: Bool = false
    ) {
        let key = "\(place.id)|\(source.badge)"
        if lockedInsightKey == key {
            if let current = lockedInsight,
               current.distanceLabel != distanceLabel || current.isAtLocation != isAtLocation {
                lockedInsight = ScannerPlaceInsight(
                    place: current.place,
                    source: current.source,
                    distanceLabel: distanceLabel,
                    isAtLocation: isAtLocation,
                    isLoading: current.isLoading,
                    dive: current.dive,
                    facts: current.facts,
                    dealCount: current.dealCount
                )
            }
            return
        }
        lockedInsightTask?.cancel()
        lockedInsightKey = key
        lockedInsight = ScannerPlaceInsight(
            place: place,
            source: source,
            distanceLabel: distanceLabel,
            isAtLocation: isAtLocation,
            isLoading: true,
            dive: nil,
            facts: [],
            dealCount: nil
        )

        lockedInsightTask = Task { [weak self] in
            async let diveFetch = LoreAPI.shared.dive(placeID: place.id)
            async let factsFetch = LoreAPI.shared.facts(placeID: place.id)
            async let dealsFetch = LoreAPI.shared.deals(placeID: place.id)

            let loadedDive = try? await diveFetch
            let loadedFacts = (try? await factsFetch) ?? []
            let loadedDeals = (try? await dealsFetch) ?? []

            guard !Task.isCancelled else { return }
            let hydrated = ScannerPlaceInsight(
                place: place,
                source: source,
                distanceLabel: distanceLabel,
                isAtLocation: isAtLocation,
                isLoading: false,
                dive: loadedDive,
                facts: loadedFacts,
                dealCount: loadedDeals.count
            )
            guard self?.lockedInsightKey == key else { return }
            self?.lockedInsight = hydrated
        }
    }

    private func clearLockedInsight() {
        lockedInsightTask?.cancel()
        lockedInsightTask = nil
        lockedInsightKey = nil
        lockedInsight = nil
    }

    // MARK: Selection

    func select(_ place: Place) {
        Haptics.play(.dossierOpen)
        seenPlaceIDs.insert(place.id)
        selectedPlace = place
    }

    /// Freeze the viewfinder into a shareable AR postcard, tagged with the
    /// currently-locked place + city (Phase 2 "magic capture"). Coarse mode only
    /// (precise mode's ARSession owns the camera). No-op on failure, never
    /// crashes the scan.
    func captureMoment() async {
        guard !preciseMode,
              let lockedPlace = lockedRanked?.place,
              let data = await camera.capturePhotoData(),
              let image = UIImage(data: data) else { return }
        capturedShot = CapturedShot(
            image: image,
            place: lockedPlace,
            city: loadedCity ?? Config.defaultCity
        )
    }

    /// Fire ONE frame at the cloud landmark identifier (opt-in "what is this?").
    /// Only meaningful in coarse mode (the AVCapture session owns the camera).
    /// Never fabricates: a miss lands in `.none`, any error in `.unavailable`.
    func identifyLandmark(accessToken: String) async -> LandmarkRequestOutcome {
        guard !preciseMode else { return .completed }
        identifyState = .loading
        guard let data = await camera.capturePhotoData() else {
            identifyState = .unavailable(.capture)
            return .completed
        }
        do {
            var request = URLRequest(url: Config.functionsURL.appending(path: "landmark-id"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            let (body, response) = try await URLSession.shared.upload(for: request, from: data)
            guard let http = response as? HTTPURLResponse else {
                identifyState = .unavailable(.service)
                return .completed
            }
            if http.statusCode == 204 {
                identifyState = .none
                return .completed
            }
            if http.statusCode == 401 {
                identifyState = .unavailable(.service)
                return .unauthorized
            }
            if http.statusCode == 403 {
                identifyState = .unavailable(.membership)
                return .plusRequired
            }
            if http.statusCode == 429 {
                identifyState = .quotaReached
                return .completed
            }
            guard http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(LandmarkResponse.self, from: body) else {
                identifyState = .unavailable(.service)
                return .completed
            }
            guard let match = LandmarkID(
                name: decoded.landmark,
                confidence: decoded.confidence,
                slug: decoded.slug,
                placeID: decoded.placeID,
                placeCity: decoded.placeCity
            ) else {
                identifyState = .unavailable(.invalidResponse)
                return .completed
            }
            identifyState = .result(match)
            Haptics.play(match.isAmbiguous ? .scanRecognizing : .scannerLock)
            return .completed
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .timedOut {
            identifyState = .unavailable(.network)
            return .completed
        } catch {
            identifyState = .unavailable(.service)
            return .completed
        }
    }

    func resetIdentification() {
        guard identifyState != .loading else { return }
        identifyState = .idle
    }

    /// Open the story for an identified landmark. Stable id supports matches in
    /// another city; slug remains the local/offline fallback.
    func openIdentified(_ identified: LandmarkID) async {
        if let placeID = identified.placeID,
           let place = places.first(where: { $0.id == placeID }) {
            hydrateInsight(for: place, source: .cloud)
            select(place)
            return
        }
        if let slug = identified.slug,
           let place = places.first(where: { $0.slug == slug }) {
            hydrateInsight(for: place, source: .cloud)
            select(place)
            return
        }
        if let placeID = identified.placeID,
           let place = try? await LoreAPI.shared.place(id: placeID) {
            hydrateInsight(for: place, source: .cloud)
            select(place)
        }
    }

    /// A stack candidate the user confirmed → it becomes the selected place. This
    /// is immediate local scanner feedback; durable crowd verification must go
    /// through a server-owned path so RLS, weighting, and self-vote rules hold.
    func confirmFromStack(_ ranked: ScannerRanking.Ranked) {
        seenPlaceIDs.insert(ranked.place.id)
        let feedback = ScannerConfirmationFeedback(
            placeName: ranked.place.name,
            distanceLabel: ranked.projected.distanceLabel,
            isAtLocation: ranked.projected.isAtLocation
        )
        stackConfirmationFeedback = feedback
        stackConfirmationTask?.cancel()
        stackConfirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if self?.stackConfirmationFeedback == feedback {
                self?.stackConfirmationFeedback = nil
            }
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: feedback.accessibilityAnnouncement
        )
        select(ranked.place)
    }

    func toggleHaunted() {
        hauntedOnly.toggle()
        reproject()
    }

    func playNarration(for place: Place) {
        let register = ScannerRanking.voiceRegister(for: prefs?.persona ?? .traveler)
        narration.speak(place, register: register)
    }

    // MARK: Projection loop

    /// Re-projects at ~5 Hz, well under the 10–15 Hz AR budget, plenty for
    /// compass-grade heading, cheap on battery (docs/05 §7).
    private func startProjectionLoop() {
        projectionTask?.cancel()
        projectionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reproject()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// The last time the "nothing here" thunk fired, so a flickering fix can't
    /// buzz it every 200 ms.
    private var lastNothingHapticAt: Date?

    /// Transition the always-alive state, firing the state's feedback exactly on
    /// entry (never per frame). Only `nothingRecognized` carries a haptic here
    /// (a found lock already thunks via `.scannerLock`); it's debounced so a
    /// flickering fix can't machine-gun it.
    private func setScanState(_ new: ScanState) {
        guard new != scanState else { return }
        // Leaving the empty state clears any stale identify result.
        if case .nothingRecognized = new {} else { identifyState = .idle }
        scanState = new
        // Only run on-device Vision when its read is actually shown (the
        // nothing-recognized readout). In the common "found a place" case the
        // whole recognition pipeline idles — no classification, no OCR, no
        // battery/thermal cost producing a read nothing displays.
        if case .nothingRecognized = new { vision.setEnabled(true) }
        else { vision.setEnabled(false) }
        if case .nothingRecognized = new {
            let now = Date()
            if lastNothingHapticAt == nil || now.timeIntervalSince(lastNothingHapticAt!) > 4 {
                Haptics.play(.scanNothing)
                lastNothingHapticAt = now
            }
        }
    }

    private func reproject() {
        // Precise mode owns the frame: the coarse chips are hidden, so the
        // bearing math is skipped. The one job here is the ladder watchdog,
        // a hard failure drops silently back to coarse (docs/05 §5). A
        // transient relocalize keeps the searching treatment instead.
        if preciseMode {
            if case .failed(let failure) = geoAR.state {
                fallBackFromPreciseMode(failure)
            }
            return
        }

        if needsPreciseLocation {
            clearProjectedContent()
            acquiringSince = nil
            setScanState(.preciseLocationRequired)
            return
        }

        guard let location = pose.freshLocation() else {
            clearProjectedContent()
            resolveLocalContext(location: nil)
            // A missing fix may genuinely improve outdoors. Approximate access
            // is handled above and never receives this copy.
            if acquiringSince == nil { acquiringSince = Date() }
            let waited = Date().timeIntervalSince(acquiringSince ?? Date())
            setScanState(waited > 8 ? .searchingOutside : .acquiringSensors)
            return
        }

        resolveLocalContext(location: location)
        guard case .locked(let localCity) = localContext else {
            clearProjectedContent()
            acquiringSince = nil
            switch localContext {
            case .waitingForLocation:
                setScanState(.acquiringSensors)
            case .loadingCities:
                setScanState(.resolvingCoverage)
            case .unavailable:
                setScanState(.coverageUnavailable)
            case .outsideCoverage:
                setScanState(.outsideCoverage)
            case .locked:
                break
            }
            return
        }

        if loadedCity != localCity.slug {
            clearProjectedContent()
            setScanState(.resolvingCoverage)
            Task { await loadContent(city: localCity.slug) }
            return
        }

        if isLoadingContent {
            clearProjectedContent()
            setScanState(.resolvingCoverage)
            return
        }

        guard let heading = pose.freshHeading() else {
            clearProjectedContent()
            if acquiringSince == nil { acquiringSince = Date() }
            let waited = Date().timeIntervalSince(acquiringSince ?? Date())
            setScanState(waited > 8 ? .headingUnavailable : .acquiringSensors)
            return
        }
        // A fix arrived: stop the acquisition clock.
        acquiringSince = nil

        if lastScoutedLocation == nil
            || location.distance(from: lastScoutedLocation!) > 250 {
            lastScoutedLocation = location
            scouting.scout(coordinate: location.coordinate)
        }

        // 1. Pose math → projected candidates (unchanged bearing geometry).
        let projected = BearingProjector.project(
            places: places,
            from: location,
            heading: heading.degrees,
            fovDegrees: camera.horizontalFOVDegrees
        )

        // 2. Sensor quality gates the tier ceiling (docs/05 §4.2). Compass-grade
        // coarse mode until precise AR is actually localized; the probe below
        // only tells us coverage exists, so `hasVPS` stays false here.
        // Camera pitch (scanner-lab port) blocks ground/sky overclaims.
        var quality = ScannerRanking.PoseQuality(
            horizontalAccuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 30,
            headingAccuracyDeg: heading.accuracy,
            hasVPS: false
        )
        quality.cameraPitchDeg = pose.cameraPitchDeg

        // 3. §3 ranking, persona-weighted.
        let ranked = ScannerRanking.rank(
            projected,
            prefs: prefs,
            quality: quality,
            seenPlaceIDs: seenPlaceIDs
        )

        // 3.5 Temporal hysteresis: raw tiers pass through the stabilizer so a
        // lock is *earned* over ~400ms and survives ~650ms of boundary jitter
        // (scanner-lab port; Tier C is never held, honesty beats stickiness).
        let stabilized = ranked.map { candidate -> ScannerRanking.Ranked in
            let display = tierStabilizer.stabilize(id: candidate.id, raw: candidate.tier)
            guard display != candidate.tier else { return candidate }
            return ScannerRanking.Ranked(
                projected: candidate.projected,
                tier: display,
                score: candidate.score,
                visionTextScore: candidate.visionTextScore,
                matchedInterests: candidate.matchedInterests
            )
        }

        // 4. Tier split. Tier A → the single best-scoring locked pin (there can
        // be only one commitment). Tier B in-view → clustered into stacks.
        // Everything else (Tier C + off-screen) → the directional rail.
        let previousLockID = lockedRanked?.place.id

        let tierA = stabilized.filter { $0.tier == .a && $0.projected.isInView }
        let newLock = tierA.first
        lockedRanked = newLock
        if let newLock {
            hydrateInsight(for: newLock)
        } else {
            clearLockedInsight()
        }

        let tierB = stabilized.filter { $0.tier == .b && $0.projected.isInView }
        inViewClusters = Array(ScannerRanking.cluster(tierB).prefix(5))

        directionalCandidates = Array(
            stabilized
                .filter { $0.tier == .c || !$0.projected.isInView }
                .prefix(10)
        )

        // 5. §3.1 story markers, distance-budgeted, night-toggle aware.
        let projectedStories = ScannerRanking.nearbyStories(
            stories,
            from: location,
            heading: heading.degrees,
            fovDegrees: camera.horizontalFOVDegrees,
            hauntedOnly: hauntedOnly
        )
        inViewStories = projectedStories.filter(\.isInView)

        // 6. Haptics + audio on a *new* lock (brand/ELEVATION §4: `.rigid` on
        // lock; the selection tick as chips pass center is handled below).
        if let newLock, newLock.place.id != previousLockID {
            Haptics.play(.scannerLock)
            narration.offer(newLock.place) // §3.2 auto-offer, not auto-play
        }

        // 6.5 Resolve the always-alive state (never silent). Anything Lore knows
        // around the user — a lock, in-view chips, or off-screen rail hints —
        // is `foundNearby`; a truly empty field is `nothingRecognized`, where
        // the honest on-device read + "point at a real landmark" nudge show and
        // the `.scanNothing` thunk fires once.
        let knownCount = (newLock != nil ? 1 : 0) + inViewClusters.count + directionalCandidates.count
        setScanState(knownCount > 0 ? .foundNearby(knownCount) : .nothingRecognized)
        vision.setEnabled(newLock == nil || (newLock?.visionTextScore ?? 0) >= 0.75)

        // 7. Selection tick as a chip crosses the reticle center (docs/12 §3
        // "gaze"; brand/ELEVATION §4 `.scannerChipPass`). Fire once per chip as
        // it enters the center band, not every frame it's inside.
        updateCenterCrossing(inViewClusters.map(\.lead))
    }

    private func clearProjectedContent() {
        lockedRanked = nil
        inViewClusters = []
        inViewStories = []
        directionalCandidates = []
        clearLockedInsight()
    }

    private func ensureCityRosterLoaded(force: Bool = false) {
        if force {
            cityRosterTask?.cancel()
            cityRosterTask = nil
        }
        guard availableCities == nil, cityRosterTask == nil else { return }
        guard !cityRosterLoadFailed || force else { return }
        cityRosterLoadFailed = false
        cityRosterTask = Task { [weak self] in
            guard let self else { return }
            do {
                let cities = try await LoreAPI.shared.cities()
                guard !Task.isCancelled else { return }
                self.availableCities = cities
                self.cityRosterTask = nil
                self.resolveLocalContext(location: self.pose.freshLocation())
                self.reproject()
            } catch {
                guard !Task.isCancelled else { return }
                self.cityRosterLoadFailed = true
                self.cityRosterTask = nil
                self.localContext = .unavailable
                self.clearProjectedContent()
                self.setScanState(.coverageUnavailable)
            }
        }
    }

    private func resolveLocalContext(location: CLLocation?) {
        ensureCityRosterLoaded()
        let previousCity = localContext.lockedCity?.slug
        let resolved: ScannerLocalContext
        if cityRosterLoadFailed {
            resolved = .unavailable
        } else {
            resolved = ScannerLocalContextResolver.resolve(
                location: location,
                cities: availableCities
            )
        }
        localContext = resolved
        if previousCity != resolved.lockedCity?.slug {
            contentLoadID = UUID()
            loadedCity = nil
            loadError = false
            isLoadingContent = false
            places = []
            stories = []
            clearProjectedContent()
            tierStabilizer.reset()
        }
    }

    /// Track which candidates are within the center band so we can fire a
    /// selection haptic exactly on the frame a chip *enters* it (a tick as it
    /// passes center, brand/ELEVATION §4), never a buzz-storm while it sits.
    private var centeredIDs: Set<String> = []

    private func updateCenterCrossing(_ leads: [ScannerRanking.Ranked]) {
        let band = 0.06 // ±6% of screen width around center counts as "passing"
        let nowCentered = Set(
            leads
                .filter { abs($0.projected.screenFraction - 0.5) <= band }
                .map(\.id)
        )
        // A chip that is centered now but wasn't last frame just crossed.
        let entered = nowCentered.subtracting(centeredIDs)
        if !entered.isEmpty {
            Haptics.play(.scannerChipPass)
        }
        centeredIDs = nowCentered
    }
}
