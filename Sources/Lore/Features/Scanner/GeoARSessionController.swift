import ARKit
import CoreLocation
import Foundation
import Observation
import simd
import UIKit

// MARK: - The VPS seam (docs/05 §2.1 dual-VPS doctrine)

/// One geo anchor projected into the AR view's pixel space, the docs/05 §2.2
/// step-8 output shape: where on screen the world-locked card renders, how far
/// away the place is, and whether the anchor is actually ahead of the camera.
struct ProjectedPin: Equatable {
    /// The `Place.id` this anchor was created for, so a tap resolves straight
    /// back into the existing card/sheet flow without the UI holding any
    /// anchor state of its own.
    let placeID: String
    /// Where the anchor lands in the AR view's coordinate space, points.
    let screenPoint: CGPoint
    /// Live camera-to-anchor distance, meters (ARKit world units are meters).
    let distanceM: Double
    /// False when the anchor sits behind the camera plane. `projectPoint`
    /// happily projects points behind the camera too, so the UI must gate on
    /// this or a behind-you pin would mirror onto the screen.
    let isInFront: Bool
}

/// How far the precise pipeline has gotten, the docs/05 §5 ladder rendered as
/// a state the UI can switch on. `locked` is the Tier-A gate: on-building
/// claims render only while the tracker reports localized (docs/05 §4.2, a
/// confident wrong pin is the one product-killing failure).
enum VPSState: Equatable {
    /// Not running; coarse mode owns the viewfinder.
    case idle
    /// Session starting; world tracking is warming up (docs/05 §2.2 step 2).
    case initializing
    /// VPS is matching camera imagery; keep the scanning treatment up
    /// (docs/05 §2.2 step 4, target TTL p50 < 3 s / p90 < 10 s).
    case localizing
    /// Localized within gates; exact pins have earned their render.
    case locked
    /// Hard failure; the caller drops back down the ladder to coarse.
    case failed(VPSFailure)
}

/// Why the precise pipeline gave up. Coarse mode is the answer to all of
/// them (docs/05 §5, transitions silent and fast); the reason only shades
/// the status line.
enum VPSFailure: Equatable {
    /// Device cannot run geo tracking at all (docs/05 §5 rung 4).
    case unsupported
    /// Geo tracking reported no coverage at this spot after starting.
    case trackingLost
    /// The ARSession itself errored (camera interruption, sensor failure).
    case sessionError
}

/// The seam every VPS backend hides behind. Today the only implementation is
/// `GeoARSessionController` below (Apple ARGeoTracking, zero external SDKs,
/// zero API keys). The ARCore Geospatial implementation (`GARSession`, VPS
/// pose ~1 m / 1-2° plus Streetscape Geometry, docs/05 §2.1) lands at P1.5
/// behind this exact protocol once the founder creates the ARCore API key;
/// until then no package dependency is added. The scanner talks only to this
/// protocol, so the Google swap is a construction-site change, not a UI one.
@MainActor
protocol VPSProvider: AnyObject {
    /// The ladder state the UI renders (reticle treatment plus status line).
    var state: VPSState { get }
    /// Latest throttled snapshot of projections, keyed by anchor identifier.
    var projections: [UUID: ProjectedPin] { get }
    /// Start tracking and anchor the given candidates. Callers pass them
    /// ranked/nearest first; the provider caps how many it anchors.
    func start(candidates: [Place])
    /// Tear down tracking and clear all published state.
    func stop()
}

// MARK: - Apple ARGeoTracking controller (docs/05 §5 rung 1, pure Apple)

/// Owns the single `ARSession` running `ARGeoTrackingConfiguration`, Apple's
/// own VPS: camera imagery matched against Apple Maps street-level data for a
/// meter-class geodetic pose, no external SDK and no entitlement. This is the
/// Tier-A path of the degraded-modes ladder on pure Apple frameworks; the
/// downstream pin math mirrors docs/05 §2.2 step 8 (project candidates into
/// screen space, render, tap resolves to the card).
///
/// Threading per docs/03 §2 (the three-lane model): session delegate
/// callbacks arrive on a dedicated serial queue (`frameQueue`, the AR lane,
/// never main), the per-frame projection math runs there inside
/// `GeoAnchorProjector`, and only the ~10 Hz throttled snapshot hops to the
/// main actor for SwiftUI to observe. The UI never touches frames; the AR
/// lane never blocks on the UI.
@Observable
@MainActor
final class GeoARSessionController: NSObject, VPSProvider {
    /// Geo anchors per session, ranked/nearest first. Small on purpose:
    /// anchor resolution quotas are finite (docs/05 open Q5) and the scanner
    /// caps rendered pins below this anyway.
    static let anchorCap = 8

    /// True when this device can run ARGeoTracking at all. Pairs with the
    /// `GeoScoutingService` coverage probe: coverage says the area works,
    /// this says the hardware does.
    static var isSupported: Bool { ARGeoTrackingConfiguration.isSupported }

    /// The session `GeoARView` shares for camera-background rendering. One
    /// session, one owner: this controller runs it, the view only renders it.
    let session = ARSession()

    private(set) var state: VPSState = .idle
    private(set) var projections: [UUID: ProjectedPin] = [:]

    /// The AR lane (docs/03 §2): delegate callbacks and projection math live
    /// here so the main thread only ever sees throttled value snapshots.
    private let frameQueue = DispatchQueue(label: "com.erickdronski.lore.geo-ar-frames")
    /// Thread-confined to `frameQueue`; holds the per-frame working state.
    /// The serial queue is the synchronization, no locks.
    private let projector = GeoAnchorProjector()
    /// Fails the pipeline down to coarse if localization never completes, so an
    /// opt-in that can't localize doesn't sit on "Locking on" forever.
    private var localizeTimeout: Task<Void, Never>?

    // MARK: VPSProvider

    /// Run geo tracking and drop an `ARGeoAnchor` for each of the top
    /// candidates. ARKit resolves each anchor's altitude to ground level,
    /// which matches where the coarse scanner's chips claim places sit.
    func start(candidates: [Place]) {
        guard Self.isSupported else {
            state = .failed(.unsupported)
            return
        }
        state = .initializing
        projections = [:]

        session.delegateQueue = frameQueue
        session.delegate = self

        // Lean configuration per the docs/05 §7 power budget: geo tracking
        // manages its own world alignment; no scene reconstruction, no
        // person segmentation, nothing beyond the localization we need.
        let configuration = ARGeoTrackingConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        var placeIDsByAnchor: [UUID: String] = [:]
        for place in candidates.prefix(Self.anchorCap) {
            let anchor = ARGeoAnchor(coordinate: place.coordinate)
            placeIDsByAnchor[anchor.identifier] = place.id
            session.add(anchor: anchor)
        }
        frameQueue.async { [projector] in
            projector.begin(placeIDsByAnchor: placeIDsByAnchor)
        }

        // Give-up timer: if we never reach localized, drop honestly to coarse
        // rather than leave the user staring at "Locking on".
        localizeTimeout?.cancel()
        localizeTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            if case .locked = self.state { return }
            if self.state != .idle { self.state = .failed(.trackingLost) }
        }
    }

    func stop() {
        localizeTimeout?.cancel()
        localizeTimeout = nil
        session.pause()
        state = .idle
        projections = [:]
        frameQueue.async { [projector] in
            projector.reset()
        }
    }

    /// The AR view reports its live bounds here so projections land in the
    /// same pixel space the SwiftUI overlay positions cards in. Nonisolated
    /// on purpose: it only forwards onto the frame queue, so any layout pass
    /// can call it without hopping actors.
    nonisolated func setViewport(_ size: CGSize) {
        frameQueue.async { [projector] in
            projector.viewportSize = size
        }
    }
}

// MARK: ARSessionDelegate (runs on frameQueue, the AR lane)

extension GeoARSessionController: ARSessionDelegate {
    /// Per-frame projection stays on `frameQueue`; the projector throttles to
    /// ~10 Hz and only that snapshot crosses to the main actor (docs/03 §2).
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let snapshot = projector.project(frame: frame) else { return }
        Task { @MainActor in
            // A snapshot can be in flight while stop() lands; idle wins.
            guard self.state != .idle else { return }
            self.projections = snapshot
        }
    }

    /// The geo tracking state machine (docs/05 §2.2 step 4: localizing then
    /// localized; the UI gates exact pins on `locked`).
    nonisolated func session(
        _ session: ARSession,
        didChange geoTrackingStatus: ARGeoTrackingStatus
    ) {
        let mapped: VPSState
        switch geoTrackingStatus.state {
        case .initializing:
            mapped = .initializing
        case .localizing:
            mapped = .localizing
        case .localized:
            mapped = .locked
        case .notAvailable:
            // Transient not-available reasons (waiting for a location fix,
            // geo data still loading, device pointed at the ground) are
            // still the searching phase. Only a hard "no coverage at this
            // location" verdict fails down the ladder (docs/05 §5).
            mapped = geoTrackingStatus.stateReason == .notAvailableAtLocation
                ? .failed(.trackingLost)
                : .localizing
        @unknown default:
            mapped = .failed(.trackingLost)
        }
        Task { @MainActor in
            guard self.state != .idle else { return }
            self.state = mapped
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.state != .idle else { return }
            self.state = .failed(.sessionError)
        }
    }

    /// A phone call / Control Center / backgrounding interrupts the session.
    /// Drop any localized claim back to the searching state so no stale,
    /// confident world-locked pin lingers on a frozen frame (docs/05 §4.2).
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            guard self.state != .idle else { return }
            if self.state == .locked { self.state = .localizing }
        }
    }

    /// Re-establish tracking once the interruption ends; the geo anchors persist
    /// and re-resolve, driving the status back to locked.
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            guard self.state != .idle else { return }
            self.session.run(ARGeoTrackingConfiguration(), options: [.resetTracking])
            self.state = .initializing
        }
    }
}

// MARK: - Per-frame projection math (thread-confined to frameQueue)

/// The step-8 screen-space math (docs/05 §2.2), kept off the main thread per
/// docs/03 §2. Plain class, no locks: the controller's serial frame queue is
/// the synchronization boundary, exactly like the ResolverActor doctrine of
/// an immutable snapshot in, value types out.
private final class GeoAnchorProjector: @unchecked Sendable {
    /// AR view bounds in points; zero until the view first lays out, and
    /// projection is skipped until it does.
    var viewportSize: CGSize = .zero

    private var placeIDsByAnchor: [UUID: String] = [:]
    private var lastSnapshotAt: TimeInterval = 0

    /// UI publish cadence, seconds. Frames arrive at 60 Hz; the overlay only
    /// needs ~10 Hz (docs/05 §2.2 step 8 throttle, and §7: the throttle is a
    /// power budget as much as a CPU one).
    private let snapshotInterval: TimeInterval = 0.1

    func begin(placeIDsByAnchor: [UUID: String]) {
        self.placeIDsByAnchor = placeIDsByAnchor
        lastSnapshotAt = 0
    }

    func reset() {
        placeIDsByAnchor = [:]
        lastSnapshotAt = 0
    }

    /// Projects every geo anchor we own into screen space. Returns nil when
    /// throttled or not yet ready; the caller publishes non-nil snapshots.
    func project(frame: ARFrame) -> [UUID: ProjectedPin]? {
        guard !placeIDsByAnchor.isEmpty,
              viewportSize.width > 0, viewportSize.height > 0,
              frame.timestamp - lastSnapshotAt >= snapshotInterval
        else { return nil }
        lastSnapshotAt = frame.timestamp

        let camera = frame.camera
        let cameraPosition = simd_make_float3(camera.transform.columns.3)
        let worldToCamera = simd_inverse(camera.transform)

        var pins: [UUID: ProjectedPin] = [:]
        pins.reserveCapacity(placeIDsByAnchor.count)

        for anchor in frame.anchors {
            guard let placeID = placeIDsByAnchor[anchor.identifier] else { continue }
            let worldPosition = simd_make_float3(anchor.transform.columns.3)

            // Camera space: ARKit cameras look down negative z, so ahead of
            // the lens means z < 0. This feeds `isInFront`.
            let inCameraSpace = worldToCamera * simd_float4(worldPosition, 1)

            // iPhone-only and the scanner is a portrait surface, so the
            // orientation is fixed (no rotation plumbing to get wrong).
            let screenPoint = camera.projectPoint(
                worldPosition,
                orientation: .portrait,
                viewportSize: viewportSize
            )

            pins[anchor.identifier] = ProjectedPin(
                placeID: placeID,
                screenPoint: screenPoint,
                distanceM: Double(simd_distance(cameraPosition, worldPosition)),
                isInFront: inCameraSpace.z < 0
            )
        }
        return pins
    }
}
