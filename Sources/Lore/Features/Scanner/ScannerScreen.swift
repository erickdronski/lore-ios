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
/// the default and the fallback (the ladder, docs/05 §5). ARCore Geospatial
/// (Streetscape occlusion, dual VPS) lands at P1.5 behind the same
/// `VPSProvider` seam.
struct ScannerScreen: View {
    /// The active city the scanner scopes its place/story load to. Defaults to
    /// the pilot so the scanner works before the city switcher is ever opened.
    let city: String
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

    /// Raised so a scanner-opened place card can hand off to the city's culture
    /// surface (wired by the tab shell); the no-op default keeps previews working.
    var onMeetCity: (String) -> Void = { _ in }

    init(
        city: String = Config.defaultCity,
        prefs: UserPrefs? = nil,
        onMeetCity: @escaping (String) -> Void = { _ in }
    ) {
        self.city = city
        self.prefs = prefs
        self.onMeetCity = onMeetCity
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The camera layer: AVCapture preview in coarse mode, the
                // shared ARSession's feed in precise mode. One owner at a
                // time; the model handles the handoff (docs/05 §5 ladder).
                if model.preciseMode {
                    GeoARView(controller: model.geoAR)
                        .ignoresSafeArea()
                } else {
                    CameraPreviewView(session: model.camera.session)
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
                    Spacer()
                    if let offered = model.narration.offered {
                        audioOffer(for: offered)
                            .padding(.bottom, 8)
                    }
                    if !model.preciseMode {
                        recognitionReadout
                            .animation(
                                LoreSpring.smooth(reduceMotion: reduceMotion),
                                value: model.scanState
                            )
                    }
                    if !model.preciseMode {
                        directionalRail
                    }
                    bottomBar
                }

                // Camera/location denied: a first-class Settings path, never a
                // black viewfinder with pins floating on nothing.
                if model.permissionDenied {
                    permissionOverlay
                }
            }
        }
        .background(LoreColor.ink950)
        .sheet(item: $model.selectedPlace) { place in
            PlaceCardView(place: place, onMeetCity: { model.selectedPlace = nil; onMeetCity($0) })
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
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
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .audio)
        }
        .task {
            model.apply(prefs: prefs)
            await model.start(city: city)
        }
        .onChange(of: prefs) { _, newValue in model.apply(prefs: newValue) }
        .onChange(of: city) { _, newValue in
            Task { await model.reload(city: newValue) }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; model.stopSensors() }
        // Pause camera/location/loop when the app leaves the foreground (privacy
        // + battery); resume when it returns while the scanner is the live tab.
        // Tab switches are covered by onAppear/onDisappear.
        .onChange(of: scenePhase) { _, phase in
            guard isVisible else { return }
            if phase == .active { model.resumeSensors() } else { model.stopSensors() }
        }
        // A fresh on-device read while nothing is locked — a gentle tick so the
        // user feels the scanner respond to what they aim at (never a buzz: the
        // recognizer is throttled to ~2 Hz and reads are mostly stable).
        .onChange(of: model.vision.latest.phrase) { old, new in
            guard case .nothingRecognized = model.scanState, let new, new != old else { return }
            Haptics.play(.scanRecognizing)
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

    // MARK: Recognition readout (the honest "what did I see" response)

    /// The always-visible response when Lore has nothing to point you at: the
    /// on-device Vision read (honest category / signage it can literally see),
    /// then a truthful nudge that the scanner reads real places around you, not
    /// photos. This turns "it did nothing" into "it saw a skyscraper and was
    /// honest about what it can and can't name."
    @ViewBuilder
    private var recognitionReadout: some View {
        if case .nothingRecognized = model.scanState {
            VStack(spacing: 6) {
                if let phrase = model.vision.latest.phrase {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LoreColor.amber)
                        Text(phrase)
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.bone)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                Text(L10n.t("scan.pointAtLandmark"))
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 320)
            .background(LoreColor.scrimSky, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(LoreColor.amber.opacity(0.35), lineWidth: 1)
            )
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .combine)
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
            // The shutter sits dead-center of the bar (coarse mode only; the
            // precise-mode ARSession owns the frame). Centered via a ZStack so
            // the flanking controls can never shift it off-center.
            if !model.preciseMode {
                shutterButton
            }
            HStack {
                CompassRing(headingDegrees: model.pose.headingDegrees)
                Spacer()
                if model.canLockOn || model.preciseMode {
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

    /// The camera shutter (Phase 2 "magic capture"): freeze the real facade +
    /// the Lore pin into a shareable AR postcard. Coarse mode only for now, the
    /// precise-mode ARSession owns the frame.
    private var shutterButton: some View {
        Button {
            Haptics.play(.scannerLock)
            Task { await model.captureMoment() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(LoreColor.bone.opacity(0.9), lineWidth: 3)
                    .frame(width: 58, height: 58)
                Circle()
                    .fill(LoreColor.bone)
                    .frame(width: 46, height: 46)
                Image(systemName: "camera.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(LoreColor.ink)
            }
            .shadow(color: LoreColor.ink.opacity(0.4), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Capture this view"))
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
            } else {
                model.enterPreciseMode()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.preciseMode ? "scope" : "dot.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.preciseMode ? "Precise on" : "Lock on")
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
        .accessibilityLabel(Text(
            model.preciseMode
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
                Text("Lore uses the camera to place stories on the buildings around you, and your location to know which block you are on. Nothing leaves your device.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink600)
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
        .accessibilityLabel(Text(
            "\(ranked.place.name), locked, \(ranked.projected.distanceLabel) ahead"
        ))
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
        .accessibilityLabel(Text(
            "\(place.name), pinned, \(distanceLabel) ahead"
        ))
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
        .accessibilityLabel(Text("\(projected.place.name), \(projected.distanceLabel) away"))
        .accessibilityAddTraits(.isButton)
    }

    private var caption: String {
        showArrow ? "\(projected.arrow) \(projected.distanceLabel)" : projected.distanceLabel
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

/// The one always-alive scanner state. Every reproject resolves to exactly one
/// of these — there is no silent path. Drives the status line, the on-frame
/// readout, and the feedback haptics.
enum ScanState: Equatable {
    /// No usable GPS/heading yet — the scanner is warming up.
    case acquiringSensors
    /// Warming up has dragged on (often indoors) — nudge to step outside.
    case searchingOutside
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

    private(set) var places: [Place] = []
    private(set) var stories: [Story] = []
    private(set) var prefs: UserPrefs?

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
    var permissionDenied: Bool { cameraDenied || locationDenied }

    private var loadError = false
    private var scoutedOnce = false
    private var projectionTask: Task<Void, Never>?
    /// Temporal lock hysteresis (scanner-lab port): confirms a Tier A over
    /// ~400ms and holds it ~650ms across gate jitter so pins never flicker.
    private let tierStabilizer = ScannerRanking.TierStabilizer()

    /// The place currently locked (Tier A), for the reticle "firm up" state.
    var lockedPlace: Place? { lockedRanked?.place }

    /// True when any nearby story is haunted, gates the "Spooky nearby" toggle.
    var hasHauntedNearby: Bool { inViewStories.contains { $0.story.isHaunted } || stories.contains(where: \.isHaunted) }

    var statusLine: String {
        if loadError { return "Offline, cached places only" }
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
        case .foundNearby(let n):
            return String(format: L10n.t("scan.foundNearby"), n)
        case .nothingRecognized:
            return L10n.t("scan.nothingHere")
        }
    }

    /// The reticle firms up on a Tier-A commitment in either mode: a coarse
    /// lock, or the precise tracker reaching localized.
    var reticleLocked: Bool {
        preciseMode ? geoAR.state == .locked : lockedPlace != nil
    }

    /// Whether the "Lock on" upgrade is offered: coverage scouted available
    /// (docs/05 §5 tier hook) AND this hardware can run geo tracking AND we
    /// have a fix to rank candidates from. Coarse remains the default.
    var canLockOn: Bool {
        !preciseMode
            && scouting.availability == .available
            && GeoARSessionController.isSupported
            && pose.location != nil
            && !places.isEmpty
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

    /// Adopt the shared curation prefs (persona lens). Cheap and idempotent —
    /// called on appear and whenever the app's prefs change.
    func apply(prefs: UserPrefs?) {
        self.prefs = prefs
    }

    func start(city: String = Config.defaultCity) async {
        // Marker rung (docs/05 §5, rung 0): a scanned Lore QR is ground truth
        // at a known point, an instant honest resolve no GPS could earn.
        camera.onMarkerSlug = { [weak self] slug in
            guard let self else { return }
            guard let place = self.places.first(where: { $0.slug == slug }) else { return }
            Haptics.play(.scannerLock)
            self.selectedPlace = place
        }
        // Surface permission dead-ends. Start optimistic; the callbacks re-raise
        // if still denied, so a grant from Settings clears the overlay.
        cameraDenied = false
        locationDenied = false
        camera.onPermissionDenied = { [weak self] in self?.cameraDenied = true }
        pose.onPermissionDenied = { [weak self] in self?.locationDenied = true }
        // Feed live frames to the on-device recognizer. Capture the service (not
        // self) so the closure runs cleanly off the main actor; frames never
        // leave the device — they go straight to Apple Vision on-device.
        let recognizer = vision
        camera.onFrame = { buffer, orientation in
            recognizer.recognize(pixelBuffer: buffer, orientation: orientation)
        }
        camera.start()
        pose.start()
        // A single "I'm awake and looking" pulse so raising the phone always
        // *feels* like the scan began (the old scanner started dead-silent).
        Haptics.play(.scanAttempt)
        acquiringSince = Date()
        startProjectionLoop()
        await loadContent(city: city)
    }

    /// Refetch places/stories for a newly-selected city, keeping sensors live.
    func reload(city: String) async {
        guard city != loadedCity else { return }
        await loadContent(city: city)
    }

    private func loadContent(city: String) async {
        loadedCity = city
        loadError = false
        async let placesResult = LoreAPI.shared.places(city: city)
        async let storiesResult = LoreAPI.shared.stories(city: city)
        do {
            places = try await placesResult
        } catch {
            loadError = true
        }
        // Stories are enrichment, not the primary resolve: a failure here never
        // degrades the scan, it just means no meanwhile-nearby markers.
        stories = (try? await storiesResult) ?? []
    }

    func stopSensors() {
        camera.stop()
        camera.onFrame = nil
        vision.reset()
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
        tierStabilizer.reset()
    }

    /// Restart the coarse sensors after a foreground return (the content is
    /// already loaded, so this only re-wakes the camera, pose, and 5 Hz loop).
    /// Precise mode is torn down on background and re-offered, never auto-resumed.
    func resumeSensors() {
        guard !preciseMode, projectionTask == nil else { return }
        cameraDenied = false
        locationDenied = false
        let recognizer = vision
        camera.onFrame = { buffer, orientation in
            recognizer.recognize(pixelBuffer: buffer, orientation: orientation)
        }
        camera.start()
        pose.start()
        Haptics.play(.scanAttempt)
        acquiringSince = Date()
        startProjectionLoop()
    }

    // MARK: Precise mode (docs/05 §5 ladder, rung 1)

    /// Upgrade to the precise pipeline: hand the camera to the ARSession and
    /// anchor the top-ranked candidates as ARGeoAnchors. Coarse remains the
    /// fallback at every step; any hard failure lands in exitPreciseMode().
    func enterPreciseMode() {
        guard !preciseMode, let location = pose.location else { return }

        // Rank the whole nearby field, not just the current FOV, so anchors
        // cover what the user will sweep to. Ranked first, nearest breaking
        // ties via the proximity term; the controller caps at its quota.
        let projected = BearingProjector.project(
            places: places,
            from: location,
            heading: max(pose.headingDegrees, 0),
            fovDegrees: camera.horizontalFOVDegrees
        )
        let quality = ScannerRanking.PoseQuality(
            horizontalAccuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 30,
            headingAccuracyDeg: pose.headingAccuracy,
            hasVPS: false
        )
        let ranked = ScannerRanking.rank(
            projected,
            prefs: prefs,
            quality: quality,
            seenPlaceIDs: seenPlaceIDs
        )
        guard !ranked.isEmpty else { return }

        preciseMode = true
        narration.dismissOffer()
        // One camera owner at a time: the AVCapture preview yields to ARKit.
        camera.stop()
        // Clear the coarse frame so nothing stale flashes on the way back.
        lockedRanked = nil
        inViewClusters = []
        inViewStories = []
        directionalCandidates = []
        geoAR.start(candidates: ranked.map(\.place))
    }

    /// Fall back down the ladder (docs/05 §5: transitions are silent and
    /// fast, the pins soften into labels). Called on the user toggle and
    /// automatically by the watchdog on a hard tracking failure.
    func exitPreciseMode() {
        guard preciseMode else { return }
        preciseMode = false
        geoAR.stop()
        camera.start()
        reproject()
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
              let data = await camera.capturePhotoData(),
              let image = UIImage(data: data) else { return }
        capturedShot = CapturedShot(
            image: image,
            place: lockedRanked?.place,
            city: loadedCity ?? Config.defaultCity
        )
    }

    /// A stack candidate the user confirmed → it becomes the locked pin and
    /// (P1) would feed a `verification` (docs/12 §2.1 confirm-a-look).
    func confirmFromStack(_ ranked: ScannerRanking.Ranked) {
        seenPlaceIDs.insert(ranked.place.id)
        select(ranked.place)
        // TODO(P1): POST a `verification` for the confirmed look so the crowd
        // sharpens the ODbL-tainted geometry (docs/06 crowdsourcing, docs/09
        // clean-room path). RLS-scoped write via LoreAPI once auth is wired in.
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
        scanState = new
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
            if case .failed = geoAR.state {
                exitPreciseMode()
            }
            return
        }

        guard let location = pose.location, pose.headingDegrees >= 0 else {
            lockedRanked = nil
            inViewClusters = []
            inViewStories = []
            directionalCandidates = []
            // Never silent: acknowledge we're acquiring, and escalate the copy
            // to a "step outside" nudge if the wait drags on (usually indoors).
            if acquiringSince == nil { acquiringSince = Date() }
            let waited = Date().timeIntervalSince(acquiringSince ?? Date())
            setScanState(waited > 8 ? .searchingOutside : .acquiringSensors)
            return
        }
        // A fix arrived: stop the acquisition clock.
        acquiringSince = nil

        if !scoutedOnce {
            scoutedOnce = true
            scouting.scout(coordinate: location.coordinate)
        }

        // 1. Pose math → projected candidates (unchanged bearing geometry).
        let projected = BearingProjector.project(
            places: places,
            from: location,
            heading: pose.headingDegrees,
            fovDegrees: camera.horizontalFOVDegrees
        )

        // 2. Sensor quality gates the tier ceiling (docs/05 §4.2). Compass-grade
        // coarse mode until the ARCore VPS lands; the probe below only tells us
        // coverage exists, not that we're localized, so `hasVPS` stays false.
        // Camera pitch (scanner-lab port) blocks ground/sky overclaims.
        var quality = ScannerRanking.PoseQuality(
            horizontalAccuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 30,
            headingAccuracyDeg: pose.headingAccuracy,
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
            heading: pose.headingDegrees,
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

        // 7. Selection tick as a chip crosses the reticle center (docs/12 §3
        // "gaze"; brand/ELEVATION §4 `.scannerChipPass`). Fire once per chip as
        // it enters the center band, not every frame it's inside.
        updateCenterCrossing(inViewClusters.map(\.lead))
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
