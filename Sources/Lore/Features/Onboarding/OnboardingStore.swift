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
    static let draftDefaultsKey = "lore.onboarding.draft.v1"

    /// Whether the first-run flow should be shown at all. `false` once either
    /// the local flag or a server `user_prefs.onboarded` says we're done.
    ///
    /// The integrator calls this after resolving prefs (see `resolveGate`).
    private(set) var shouldPresent: Bool

    /// The persona/interests actually staged by the last `finish()` (skip
    /// defaults folded in). The presenter reads these to adopt a guest lens into
    /// `PrefsCoordinator` the instant the flow ends, so the map/scanner
    /// re-weight in-session rather than waiting for a sign-in (audit docs/30).
    private(set) var resolvedPersona: UserPrefs.Persona?
    private(set) var resolvedInterests: [String] = []

    /// Stable persisted step identifiers. Navigation order is owned by
    /// `activeSteps` so optional release capabilities never depend on raw-value
    /// arithmetic.
    enum Step: Int, CaseIterable {
        case arrival = 0
        case interests = 1
        case location = 2
        case finish = 3
        case notifications = 4

        /// Map a step name (used by the DEBUG screenshot hook) to a case.
        static func named(_ raw: String) -> Step? {
            switch raw {
            case "arrival": return .arrival
            case "interests": return .interests
            case "location": return .location
            case "notifications" where Config.pushNotificationsEnabled:
                return .notifications
            case "finish": return .finish
            default: return nil
            }
        }
    }

    /// The release-visible route. Notification education and authorization are
    /// atomic with the real capability flag: when it is off, this route cannot
    /// display, be debug-forced, or be reached by forward/back navigation.
    static var activeSteps: [Step] {
        var steps: [Step] = [.arrival, .interests, .location]
        if Config.pushNotificationsEnabled {
            steps.append(.notifications)
        }
        steps.append(.finish)
        return steps
    }

    var step: Step {
        didSet { persistDraft() }
    }

    /// 0…1 progress through the flow, for the top progress rail.
    var progress: Double {
        let steps = Self.activeSteps
        let index = steps.firstIndex(of: step) ?? max(0, steps.count - 1)
        return Double(index) / Double(max(1, steps.count - 1))
    }

    // MARK: - Selection

    /// The interest slugs the user has toggled on (from `InterestMap`).
    var selectedInterests: Set<String> {
        didSet { persistDraft() }
    }
    /// The chosen preset persona, if any. `nil` until a preset chip is tapped;
    /// the stored persona defaults to `.traveler` on finish when untouched.
    var selectedPersona: UserPrefs.Persona? {
        didSet { persistDraft() }
    }

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
    private var hasFinished = false

    private let defaults: UserDefaults
    private let locationManager: CLLocationManager

    private struct Draft: Codable {
        let step: Int
        let interests: [String]
        let persona: String?
    }

    // MARK: - Init

    /// - Parameter forcePresent: skip the gate and always show the flow (for a
    ///   "replay onboarding" affordance in Profile / debug). Defaults to the
    ///   real gate: present only when the local flag is unset.
    init(
        forcePresent: Bool = false,
        defaults: UserDefaults = .standard,
        locationManager: CLLocationManager = CLLocationManager()
    ) {
        self.defaults = defaults
        self.locationManager = locationManager
        let done = defaults.bool(forKey: Self.didOnboardDefaultsKey)
        let draft = forcePresent ? nil : Self.loadDraft(from: defaults)
        shouldPresent = forcePresent || !done
        locationStatus = locationManager.authorizationStatus
        let restoredStep = draft.flatMap { Step(rawValue: $0.step) } ?? .arrival
        // A draft created while notifications were enabled must never reopen a
        // now-unavailable permission promise. Keep all choices and continue to
        // the next release-visible step instead.
        step = Self.activeSteps.contains(restoredStep) ? restoredStep : .finish
        selectedInterests = Set(draft?.interests ?? [])
        selectedPersona = draft?.persona.flatMap(UserPrefs.Persona.init(rawValue:))
        super.init()
        locationManager.delegate = self
        #if DEBUG
        // Screenshot/dev hook: LORE_ONBOARD_STEP forces the flow open at a named
        // step so each screen can be captured deterministically. Release-stripped.
        if let name = ProcessInfo.processInfo.environment["LORE_ONBOARD_STEP"],
           let forced = Step.named(name) {
            shouldPresent = true
            step = forced
        }
        #endif
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
        defaults.set(true, forKey: Self.didOnboardDefaultsKey)
        defaults.removeObject(forKey: Self.draftDefaultsKey)
    }

    private static func loadDraft(from defaults: UserDefaults) -> Draft? {
        guard let data = defaults.data(forKey: draftDefaultsKey) else { return nil }
        guard let draft = try? JSONDecoder().decode(Draft.self, from: data),
              Step(rawValue: draft.step) != nil else {
            defaults.removeObject(forKey: draftDefaultsKey)
            return nil
        }
        return draft
    }

    private func persistDraft() {
        guard shouldPresent else { return }
        let draft = Draft(
            step: step.rawValue,
            interests: selectedInterests.sorted(),
            persona: selectedPersona?.rawValue
        )
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: Self.draftDefaultsKey)
        }
    }

    // MARK: - Navigation

    /// Advance to the next step (Reveal-timed by the view). No-op on the last.
    func advance() {
        Haptics.play(.chipTap)
        let steps = Self.activeSteps
        guard let index = steps.firstIndex(of: step),
              steps.indices.contains(index + 1) else { return }
        let next = steps[index + 1]
        withAnimation(LoreMotion.unfurl) { step = next }
    }

    /// Step back (the flow's only back affordance is on the header).
    func back() {
        let steps = Self.activeSteps
        guard let index = steps.firstIndex(of: step), index > steps.startIndex else { return }
        let previous = steps[index - 1]
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
        refreshLocationStatus()
        guard locationStatus == .notDetermined, !isRequestingPermission else { return }
        isRequestingPermission = true
        locationManager.requestWhenInUseAuthorization()
    }

    /// Reconcile authorization after returning from Settings or an interrupted
    /// system prompt. This prevents a stale spinner or stale denial message.
    func refreshLocationStatus() {
        locationStatus = locationManager.authorizationStatus
        if locationStatus != .notDetermined {
            isRequestingPermission = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationStatus = status
            self.isRequestingPermission = false
        }
    }

    // MARK: - Notification permission (13 §4.3)

    /// Refreshes the real system state only when the complete notification
    /// experience is release-enabled. With the flag off this is deliberately a
    /// no-op, including in debug and restored sessions.
    func refreshNotificationStatus() async {
        guard Config.pushNotificationsEnabled else {
            notificationStatus = .notDetermined
            return
        }
        notificationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    /// Requests notification authorization only after the shared release flag
    /// confirms the APNs/local-notification delivery path is available.
    func requestNotifications() async {
        guard Config.pushNotificationsEnabled, !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        notificationStatus = await center.notificationSettings().authorizationStatus
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Finish (the single user_prefs write, 13 §4)

    /// Write `user_prefs` (persona, interests, onboarded=true), set the local
    /// flag, and hand control back. The write is best-effort: a failure records
    /// `finishError` but still completes the flow locally so a flaky network
    /// never traps a first-time user (13 §4.4).
    func finish(onComplete: @escaping () -> Void, prefsWriter: PrefsWriting) {
        guard !isFinishing, !hasFinished else { return }
        isFinishing = true
        finishError = nil

        let persona = selectedPersona ?? OnboardingContent.skipPersona
        let interests = selectedInterests.isEmpty
            ? OnboardingContent.skipInterests
            : Array(selectedInterests)

        // Expose the resolved choices (skip-defaults folded in) so the presenter
        // can adopt them into PrefsCoordinator immediately — without this the
        // signed-out map/scanner ran the neutral lens all session (audit docs/30).
        resolvedPersona = persona
        resolvedInterests = interests

        Haptics.play(.badgeEarned)

        // Durability is synchronous and local; network sync must never hold a
        // first-time traveler behind a spinner on a weak airport connection.
        prefsWriter.stageOnboardingPrefs(persona: persona, interests: interests)
        markDoneLocally()
        shouldPresent = false
        hasFinished = true
        isFinishing = false
        onComplete()

        Task {
            do {
                try await prefsWriter.writeOnboardingPrefs(
                    persona: persona,
                    interests: interests
                )
            } catch {
                finishError = error.localizedDescription
            }
        }
    }

    /// Complete an active Finish selection after authentication succeeds. The
    /// presenter calls this before resolving the signed-in server gate so an
    /// already-onboarded account cannot dismiss and discard the visible choices.
    @discardableResult
    func finishAfterAuthenticationIfReady(
        onComplete: @escaping () -> Void,
        prefsWriter: PrefsWriting
    ) -> Bool {
        guard shouldPresent, step == .finish else { return false }
        finish(onComplete: onComplete, prefsWriter: prefsWriter)
        return hasFinished
    }
}

/// The one dependency the store has on the network, behind a protocol so the
/// flow is trivially testable and the integrator can inject the real
/// `LoreAPI`-backed writer (which needs the user's access token). The default
/// implementation lives in `OnboardingPrefsWriter`.
@MainActor
protocol PrefsWriting {
    /// Persist the choice locally before the flow dismisses. Implementations
    /// without local staging may use the default no-op.
    func stageOnboardingPrefs(persona: UserPrefs.Persona, interests: [String])

    /// Upsert the onboarding-set prefs for the current user, marking
    /// `onboarded = true`. Throws on network/RLS failure.
    func writeOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) async throws
}

extension PrefsWriting {
    func stageOnboardingPrefs(persona: UserPrefs.Persona, interests: [String]) {}
}
