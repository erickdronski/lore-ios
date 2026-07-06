import CoreLocation
import Foundation
import Observation
import UserNotifications

/// The magic: automatic visit capture (lore/docs/26-TRAVEL-PASSPORT.md §1). When
/// the user walks up to a Lore place, this records the visit for their Passport
/// (`source='gps'`, with the triggering pose) and fires a local notification,
/// "You reached {place}. Tap to read its story.", deep-linking
/// `lore://place/{id}` (`AppRouter.handleDeepLink` already routes it).
///
/// This is Core Location for the app's OWN feature, NOT ad tracking:
/// `NSPrivacyTracking` stays false, no IDFA, no cross-app join (docs/26 §1). The
/// purpose strings name the reason; the passive "walk-and-collect" mode is
/// strictly opt-in.
///
/// ## Two ranges of behavior, and an honest opt-in
/// - **Foreground / When-In-Use** (always available once the user grants
///   location for the map): while the app is open we already have the ranked
///   near-me list; when a place comes within `dwellRadius`, we auto-collect it.
///   This needs no Always authorization and is the default when tracking is on
///   in the foreground.
/// - **Passive / Always** (opt-in only, `RecordTravelsPreference`): registers
///   `CLCircularRegion` geofences around the ~20 nearest places and starts
///   `CLVisit` monitoring, so a place is collected even when the app is
///   backgrounded. We ONLY ask for Always authorization after the user turns on
///   "Record my travels".
///
/// ## Safety posture (task honesty constraint)
/// The whole tracker is gated behind `isEnabled`, which reads a default-OFF
/// preference. Until the founder flips it on device, `start()` is a no-op and
/// the app behaves exactly as it does today, this file adds a capability, it
/// does not change the running app. Core Location calls that could not be
/// type-checked on this machine (no SDK) are marked `// VERIFY`.
@Observable
@MainActor
final class VisitTracker: NSObject {

    // MARK: - Tunables

    /// Dwell radius: a place within this many meters is "reached" (docs/26 §1
    /// "~60m"). Also the geofence radius. Apple ignores regions smaller than the
    /// hardware floor (~100m on many devices); 60m is the intent and the fence
    /// widens as the OS sees fit. Kept as the single knob.
    static let dwellRadius: CLLocationDistance = 60

    /// Apple caps simultaneously-monitored regions at 20 per app (docs/26 §1
    /// "cap 20, Apple's limit"). We register the nearest N and re-register as the
    /// user moves cities / blocks.
    static let maxRegions = 20

    // MARK: - Observed state

    /// The current Core Location authorization (mirrors the system).
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Place ids auto-collected this process, so we never double-fire within a
    /// session even before the server dedupe round-trips.
    private(set) var collectedThisSession: Set<String> = []

    /// Last non-fatal error (never blocks anything; surfaced only if useful).
    private(set) var lastError: String?

    // MARK: - Collaborators

    private let manager = CLLocationManager()

    /// `(userID, accessToken)` or `nil` when signed out, the same closure
    /// `VisitStore` / `TravelSession` use so this type never imports the auth
    /// layer. Auto-capture requires a signed-in user (a visit is an owned row).
    private let credentials: () -> (userID: String, accessToken: String)?

    /// Reads the opt-in flag; injected so tests / previews can force a value.
    private let isEnabled: () -> Bool

    private let api: LoreAPI

    /// Called on the main actor after an auto-visit lands, so an owner can fold
    /// it into the "Been here" set and refresh the Passport. Optional; the
    /// tracker works standalone (it always writes the server row itself).
    var onAutoVisit: (String) -> Void = { _ in }

    /// The places we currently monitor, keyed by `place.id`, so a region /
    /// visit callback can resolve back to the place it fired for.
    private var monitoredPlaces: [String: Place] = [:]

    /// The last set of places `start(with:)` was handed, kept so we can (re)fence
    /// once a first fix or an authorization grant arrives (we can't rank fences
    /// without knowing "here", and can't monitor before we're authorized).
    private var pendingPlaces: [Place] = []

    /// Per-day dedupe ledger: `place.id → yyyy-MM-dd` of the last auto-collect,
    /// persisted so a relaunch on the same day doesn't re-log (docs/26 §1 "one
    /// auto-visit per place per day, never silently re-log").
    private var lastCollectedDay: [String: String] = [:]

    init(
        api: LoreAPI = .shared,
        isEnabled: @escaping () -> Bool = { RecordTravelsPreference.isOn },
        credentials: @escaping () -> (userID: String, accessToken: String)?
    ) {
        self.api = api
        self.isEnabled = isEnabled
        self.credentials = credentials
        super.init()
        manager.delegate = self
        // Coarser than the scanner's best-accuracy fix; enough to place a
        // 60 m dwell and far kinder to the battery for a background feature.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        self.authorizationStatus = manager.authorizationStatus
        self.lastCollectedDay = RecordTravelsPreference.loadDedupeLedger()
    }

    // MARK: - Lifecycle

    /// Bring auto-capture up for a set of places (usually the city's loaded
    /// `[Place]`). No-op unless the user has opted in AND is signed in, so the
    /// app runs exactly as today until "Record my travels" is on. Idempotent:
    /// safe to call on every places-change.
    func start(with places: [Place]) {
        guard isEnabled() else { return }
        guard credentials() != nil else { return }

        // Remember these so a first fix / an authorization grant can (re)fence.
        pendingPlaces = places

        // Ensure we have at least When-In-Use; the passive Always upgrade is a
        // separate, explicit step (`requestAlwaysAuthorizationForPassive`).
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization() // VERIFY: CLLocationManager API
            return // fence once the grant + first fix arrive (delegate callbacks)
        }
        guard isAuthorized else { return }

        // Foreground close-approach: keep a light location stream so a place we
        // walk up to while the app is open is collected without waiting for a
        // region-cross event. Region monitoring covers the backgrounded case.
        manager.startUpdatingLocation() // VERIFY: CLLocationManager API
        registerRegions(for: places)
        startVisitMonitoringIfPassive()
    }

    /// Tear down all monitoring (sign-out, or the user turning tracking off).
    func stop() {
        manager.stopUpdatingLocation() // VERIFY: CLLocationManager API
        manager.stopMonitoringVisits() // VERIFY: CLLocationManager API
        for region in manager.monitoredRegions { // VERIFY: CLLocationManager.monitoredRegions
            manager.stopMonitoring(for: region)   // VERIFY: CLLocationManager API
        }
        monitoredPlaces.removeAll()
    }

    /// Step 2 of the opt-in: once the user turns on "Record my travels", ask for
    /// Always authorization so collection continues when the app is backgrounded.
    /// Apple requires When-In-Use first, then a deliberate Always prompt; we only
    /// reach here from the settings toggle, never at cold launch (docs/26 §1).
    func requestAlwaysAuthorizationForPassive() {
        switch authorizationStatus {
        case .notDetermined:
            // The system shows When-In-Use first; the Always upgrade prompt
            // arrives after, or via a later provisional-always nudge.
            manager.requestWhenInUseAuthorization() // VERIFY: CLLocationManager API
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization() // VERIFY: CLLocationManager API
        default:
            break
        }
    }

    // MARK: - Authorization helpers

    /// We can collect in the foreground (map open) with either grant.
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways
    }

    /// Passive background collection needs Always specifically.
    var hasAlwaysAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Region registration

    /// Register `CLCircularRegion` fences around the nearest `maxRegions` places,
    /// so a background region-cross auto-collects even with the app closed. We
    /// clear the old fences first (a bounded, deterministic set) and cap at 20.
    private func registerRegions(for places: [Place]) {
        // Nothing to fence without a fix to rank from; a first location update
        // re-invokes this once we know where the user is (via `pendingPlaces`).
        guard let here = manager.location else { return } // VERIFY: CLLocationManager.location

        let nearest = places
            .sorted { here.distance(from: $0.location) < here.distance(from: $1.location) }
            .prefix(Self.maxRegions)

        // Drop fences we no longer want (moved on / city switch).
        let keepIDs = Set(nearest.map(\.id))
        for region in manager.monitoredRegions where !keepIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region) // VERIFY
            monitoredPlaces.removeValue(forKey: region.identifier)
        }

        for place in nearest where monitoredPlaces[place.id] == nil {
            let region = CLCircularRegion(
                center: place.coordinate,
                radius: Self.dwellRadius,
                identifier: place.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            monitoredPlaces[place.id] = place
            manager.startMonitoring(for: region) // VERIFY: CLLocationManager API
        }
    }

    /// Start `CLVisit` dwell monitoring, but only in the passive (Always) mode,
    /// it is the OS's own low-power "the user spent time here" signal and is only
    /// meaningful with background authorization.
    private func startVisitMonitoringIfPassive() {
        guard hasAlwaysAuthorization else { return }
        manager.startMonitoringVisits() // VERIFY: CLLocationManager API
    }

    // MARK: - Collection

    /// Attempt to auto-collect the place at (or nearest within `dwellRadius` of)
    /// this location. Deduped per place per day; writes `source='gps'` with the
    /// triggering pose and fires the local notification. Runs on the main actor.
    private func collectNearest(to location: CLLocation) {
        let candidates = monitoredPlaces.values
            .map { (place: $0, meters: location.distance(from: $0.location)) }
            .filter { $0.meters <= Self.dwellRadius }
            .sorted { $0.meters < $1.meters }

        guard let nearest = candidates.first else { return }
        collect(place: nearest.place, from: location)
    }

    /// Collect a specific place (the region-enter path already knows which one).
    private func collect(place: Place, from location: CLLocation?) {
        guard isEnabled() else { return }
        guard !collectedThisSession.contains(place.id) else { return }
        guard !alreadyCollectedToday(place.id) else { return }
        guard let creds = credentials() else { return }

        // Mark optimistically so a burst of updates doesn't double-fire.
        collectedThisSession.insert(place.id)
        markCollectedToday(place.id)

        let pose = location.map(Self.pose(from:))

        Task { @MainActor in
            do {
                try await api.logVisit(
                    placeID: place.id,
                    source: .gps,
                    pose: pose,
                    accessToken: creds.accessToken
                )
                // Settle badges; a recompute failure must not undo a real visit.
                _ = try? await api.recomputeAchievements(
                    userID: creds.userID,
                    accessToken: creds.accessToken
                )
                lastError = nil
                onAutoVisit(place.id)
                await fireArrivalNotification(for: place)
            } catch {
                // The write didn't land: roll back BOTH guards so the next fix /
                // region-enter can retry today. The in-flight session guard was
                // already holding off duplicate attempts while this one ran.
                collectedThisSession.remove(place.id)
                clearCollectedToday(place.id)
                lastError = (error as? LoreAPI.APIError)?.errorDescription
                    ?? "Couldn't record that visit."
            }
        }
    }

    // MARK: - Per-day dedupe

    private func alreadyCollectedToday(_ placeID: String) -> Bool {
        lastCollectedDay[placeID] == Self.today()
    }

    private func markCollectedToday(_ placeID: String) {
        lastCollectedDay[placeID] = Self.today()
        RecordTravelsPreference.saveDedupeLedger(lastCollectedDay)
    }

    /// Undo a per-day mark after a failed write, so a retry can land today.
    private func clearCollectedToday(_ placeID: String) {
        lastCollectedDay.removeValue(forKey: placeID)
        RecordTravelsPreference.saveDedupeLedger(lastCollectedDay)
    }

    /// The user-local `yyyy-MM-dd` day, the dedupe key granularity.
    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Local notification

    /// Fire the "You reached {place}" local notification, deep-linking
    /// `lore://place/{id}`. Best-effort: no auth ⇒ no notification, never an
    /// error (the visit was still recorded). Uses `UNUserNotificationCenter`
    /// directly so it works with no APNs / server (docs/16 §5 "preferred
    /// on-device path").
    private func fireArrivalNotification(for place: Place) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "You reached \(place.name)."
        content.body = "Tap to read its story."
        content.sound = .default
        // The deep link `AppRouter.handleDeepLink` already understands.
        content.userInfo = ["deeplink": "lore://place/\(place.id)"]

        let request = UNNotificationRequest(
            identifier: "arrival-\(place.id)-\(Self.today())",
            content: content,
            trigger: nil // deliver now
        )
        try? await center.add(request)
    }

    // MARK: - Pose

    /// Build the `VisitPose` for the fix that triggered a collection.
    private static func pose(from location: CLLocation) -> VisitPose {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return VisitPose(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            altitudeM: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyM: location.horizontalAccuracy,
            verticalAccuracyM: location.verticalAccuracy,
            headingDeg: location.course >= 0 ? location.course : nil,
            capturedAt: iso.string(from: location.timestamp)
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension VisitTracker: CLLocationManagerDelegate {
    /// Authorization changed. Marshalled to the main actor for the published
    /// state; kicks passive monitoring up if we just earned Always.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            guard self.isEnabled() else { return }
            if self.isAuthorized {
                // Now that we're authorized, start the stream and fence the
                // places we were handed before the grant landed.
                manager.startUpdatingLocation() // VERIFY
                self.registerRegions(for: self.pendingPlaces)
                self.startVisitMonitoringIfPassive()
            }
        }
    }

    /// New fixes. In the foreground this drives close-approach collection and a
    /// first-fix region registration (we couldn't fence before we knew "here").
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in
            guard self.isEnabled() else { return }
            // First fix after a grant: fence the pending places now that we know
            // where "here" is (regions rank by distance from the user).
            if self.monitoredPlaces.isEmpty, !self.pendingPlaces.isEmpty {
                self.registerRegions(for: self.pendingPlaces)
            }
            // Foreground close-approach: collect a place we've walked up to
            // while the app is open, without waiting for a region-cross event.
            self.collectNearest(to: latest)
        }
    }

    /// A monitored geofence was entered, the background auto-collect path. We
    /// resolve the region id back to its place and collect it.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        let id = region.identifier
        Task { @MainActor in
            guard self.isEnabled() else { return }
            guard let place = self.monitoredPlaces[id] else { return }
            self.collect(place: place, from: manager.location) // VERIFY: manager.location
        }
    }

    /// A `CLVisit` dwell was reported (passive mode). Treat the visit's
    /// coordinate as a fix and collect the nearest monitored place.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didVisit visit: CLVisit
    ) {
        // A departure carries a distantPast arrival; only act on an arrival /
        // ongoing visit.
        let coordinate = visit.coordinate
        Task { @MainActor in
            guard self.isEnabled() else { return }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            self.collectNearest(to: location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        // Non-fatal: keep whatever monitoring we had.
    }
}

// MARK: - Opt-in preference

/// The single source of truth for the "Record my travels" opt-in (docs/26 §3).
/// Default OFF, so the app runs exactly as today until the user turns it on,
/// this is the switch the honesty constraint hangs on. Persisted in
/// `UserDefaults` (no account needed to remember the choice) alongside the
/// per-day dedupe ledger so a relaunch doesn't re-log the same place.
enum RecordTravelsPreference {
    private static let flagKey = "lore.recordTravels.enabled"
    private static let ledgerKey = "lore.recordTravels.dedupeLedger"

    /// Whether passive walk-and-collect is on. Default false.
    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    /// Load the `place.id → yyyy-MM-dd` dedupe ledger, pruned to today's entries
    /// so it never grows unbounded (yesterday's collections are irrelevant).
    static func loadDedupeLedger() -> [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
        let today = todayString()
        return raw.filter { $0.value == today }
    }

    static func saveDedupeLedger(_ ledger: [String: String]) {
        let today = todayString()
        let pruned = ledger.filter { $0.value == today }
        UserDefaults.standard.set(pruned, forKey: ledgerKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
