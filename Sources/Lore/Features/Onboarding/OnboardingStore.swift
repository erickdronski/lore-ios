import CoreLocation
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// The first-run flow's brain: which step we're on, the interest/persona
/// selection, the permission prompts, and the single `user_prefs` write on
/// finish. One `@Observable @MainActor` object so the view stays declarative.
///
/// Doctrine: `lore/docs/13-CURATION-PERSONAS.md` §4 (steps + skip default) and
/// `brand/ELEVATION.md` §5 ("first night" arrival, "skippable instantly, never
/// shown again, UserDefaults flag"). Gating is deliberately two-key: a local
/// UserDefaults flag (so a returning signed-out user isn't re-onboarded) *and*
/// the server's `user_prefs.onboarded` (so a fresh install of an existing
/// account skips it). Either being true means "done".
@Observable
@MainActor
final class OnboardingStore: NSObject, CLLocationManagerDelegate {

    // MARK: - Gate

    /// UserDefaults key for the local "has finished onboarding" flag.
    static let didOnboardDefaultsKey = "lore.onboarding.completed.v1"

    /// Whether the first-run flow should be shown at all. `false` once either
    /// the local flag or a server `user_prefs.onboarded` says we're done.
    ///
    /// The integrator calls this after resolving prefs (see `resolveGate`).
    private(set) var shouldPresent: Bool

    /// The steps of the flow, in order.
    enum Step: Int, CaseIterable {
        case arrival
        case interests
        case location
        case notifications
        case finish

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    var step: Step = .arrival

    /// 0…1 progress through the flow, for the top progress rail.
    var progress: Double {
        Double(step.rawValue) / Double(max(1, Step.allCases.count - 1))
    }

    // MARK: - Selection

    /// The interest slugs the user has toggled on (from `InterestMap`).
    var selectedInterests: Set<String> = []
    /// The chosen preset persona, if any. `nil` until a preset chip is tapped;
    /// the stored persona defaults to `.traveler` on finish when untouched.
    var selectedPersona: UserPrefs.Persona?

    /// True once the interest step's "2+ to continue" rule is satisfied.
    var canAdvanceInterests: Bool {
        selectedInterests.count >= OnboardingContent.minInterests
    }

    // MARK: - Permission state (for the UI's reactive copy)

    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    /// True while a permission dialog is in flight, so buttons can show a spinner
    /// and not double-fire.
    private(set) var isRequestingPermission = false

    /// True after the finish write kicks off, so the finish button can spin and
    /// the flow can't be double-submitted.
    private(set) var isFinishing = false
    /// Surfaced if the prefs upsert fails. The flow still completes locally —
    /// onboarding never blocks on the network (13 §4.4 broad default).
    private(set) var finishError: String?

    private let locationManager = CLLocationManager()

    // MARK: - Init

    /// - Parameter forcePresent: skip the gate and always show the flow (for a
    ///   "replay onboarding" affordance in Profile / debug). Defaults to the
    ///   real gate: present only when the local flag is unset.
    init(forcePresent: Bool = false) {
        let done = UserDefaults.standard.bool(forKey: Self.didOnboardDefaultsKey)
        shouldPresent = forcePresent || !done
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Gate resolution

    /// Fold a resolved server pref into the gate. The integrator calls this once
    /// it has loaded `user_prefs` (or knows there's no signed-in user). If the
    /// server already says `onboarded`, we mirror that locally and never present.
    func resolveGate(serverPrefs: UserPrefs?) {
        if serverPrefs?.onboarded == true {
            markDoneLocally()
            shouldPresent = false
        }
    }

    /// Persist the local "done" flag. Idempotent.
    func markDoneLocally() {
        UserDefaults.standard.set(true, forKey: Self.didOnboardDefaultsKey)
    }

    // MARK: - Navigation

    /// Advance to the next step (Reveal-timed by the view). No-op on the last.
    /// Jump straight to the finish step (the honest "Skip" affordance), keeping
    /// any choices the user already made rather than wiping them with a default.
    func jumpToFinish() {
        withAnimation(LoreMotion.unfurl) { step = .finish }
    }

    func advance() {
        Haptics.play(.chipTap)
        guard let next = step.next else { return }
        withAnimation(LoreMotion.unfurl) { step = next }
    }

    /// Step back (the flow's only back affordance is on the header).
    func back() {
        guard let previous = step.previous else { return }
        withAnimation(LoreMotion.unfurl) { step = previous }
    }

    /// Jump straight to the finish write with the broad traveler default
    /// (13 §4.4). Used by the "Skip" affordance available on every step.
    func skip(onComplete: @escaping () -> Void, prefsWriter: PrefsWriting) {
        selectedPersona = OnboardingContent.skipPersona
        selectedInterests = Set(OnboardingContent.skipInterests)
        finish(onComplete: onComplete, prefsWriter: prefsWriter)
    }

    // MARK: - Interests / persona

    /// Toggle one interest chip.
    func toggleInterest(_ slug: String) {
        Haptics.play(.chipTap)
        withAnimation(LoreMotion.tap) {
            if selectedInterests.contains(slug) {
                selectedInterests.remove(slug)
            } else {
                selectedInterests.insert(slug)
            }
        }
    }

    /// Apply a preset: set the lens and *merge in* its seed interests (never
    /// clobbering interests the user already picked, the preset is additive so
    /// tapping it after hand-picking feels like a helper, not a reset).
    func applyPreset(_ preset: OnboardingContent.Preset) {
        Haptics.play(.chipTap)
        withAnimation(LoreMotion.bloom) {
            selectedPersona = preset.persona
            selectedInterests.formUnion(preset.interests)
        }
    }

    // MARK: - Location permission (13 §4.2)

    /// Request when-in-use location. The result arrives on the delegate; the
    /// view advances regardless (permission is never a wall, the map degrades
    /// honestly without it, docs/05 §5).
    func requestLocation() {
        guard locationStatus == .notDetermined else { return }
        isRequestingPermission = true
        locationManager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
            self.isRequestingPermission = false
        }
    }

    // MARK: - Notification permission (13 §4.3)

    /// Ask for notification authorization. Optional and off-by-default in spirit
    ///, we only request when the user taps "Turn on nudges".
    ///
    /// On grant, also **register for remote notifications** so APNs issues a
    /// device token (docs/16 §5). The token arrives asynchronously in
    /// `AppDelegate` → `PushService`; the server sender (a TODO, docs/16 §5)
    /// targets it. Local proximity notifications (`CLMonitor`) don't need this
    /// registration, but the remote "new-city" path does.
    func requestNotifications() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus
        if granted {
            // Triggers the AppDelegate APNs token callbacks → PushService.
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Finish (the single user_prefs write, 13 §4)

    /// Write `user_prefs` (persona, interests, onboarded=true), set the local
    /// flag, and hand control back. The write is best-effort: a failure records
    /// `finishError` but still completes the flow locally so a flaky network
    /// never traps a first-time user (13 §4.4).
    func finish(onComplete: @escaping () -> Void, prefsWriter: PrefsWriting) {
        guard !isFinishing else { return }
        isFinishing = true
        finishError = nil

        let persona = selectedPersona ?? OnboardingContent.skipPersona
        let interests = selectedInterests.isEmpty
            ? OnboardingContent.skipInterests
            : Array(selectedInterests)

        Haptics.play(.badgeEarned)

        Task {
            do {
                try await prefsWriter.writeOnboardingPrefs(
                    persona: persona,
                    interests: interests
                )
            } catch {
                finishError = error.localizedDescription
            }
            markDoneLocally()
            shouldPresent = false
            isFinishing = false
            onComplete()
        }
    }
}

/// The one dependency the store has on the network, behind a protocol so the
/// flow is trivially testable and the integrator can inject the real
/// `LoreAPI`-backed writer (which needs the user's access token). The default
/// implementation lives in `OnboardingPrefsWriter`.
@MainActor
protocol PrefsWriting {
    /// Upsert the onboarding-set prefs for the current user, marking
    /// `onboarded = true`. Throws on network/RLS failure.
    func writeOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) async throws
}
