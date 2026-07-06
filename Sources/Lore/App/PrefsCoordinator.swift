import Observation
import SwiftUI

/// The one place the app loads and holds `user_prefs`, so every surface that
/// needs the curation profile (persona weighting on the map, the scanner's
/// ranking lens, `hidden_kinds` for the filter chips, the onboarding gate) reads
/// a single shared source instead of each re-fetching it.
///
/// It is deliberately thin: it owns the fetched `UserPrefs?`, a `load(auth:)`
/// that resolves against the current session, and it forwards the loaded prefs
/// into the Travel layer (`TravelSession.bootstrap`) so the filter chips and
/// pin weighting hydrate in one hop. Signed-out is first-class, no session
/// means `prefs == nil`, which every consumer already treats as "no lens, show
/// everything" (`MapRelevance`, `InterestMap`).
///
/// Lifecycle mirrors the other shared stores: `@Observable @MainActor`, one
/// instance created in `LoreApp`, handed down the environment and to
/// `TravelSession`.
@Observable
@MainActor
final class PrefsCoordinator {
    /// The signed-in user's curation prefs, once loaded. `nil` before the first
    /// load or when signed out, consumers read this as the un-personalized map.
    private(set) var prefs: UserPrefs?

    /// True while a load is in flight (a surface can show a quiet spinner).
    private(set) var isLoading = false

    /// The last load's error, if any. Non-fatal, the app runs un-personalized.
    private(set) var lastError: String?

    /// Whether we've completed at least one load for the current identity, so a
    /// caller can distinguish "not loaded yet" from "loaded, no prefs row".
    private(set) var loaded = false

    init(prefs: UserPrefs? = nil) {
        self.prefs = prefs
    }

    /// Load `user_prefs` for the current session. A `nil` token (signed out)
    /// clears to the un-personalized state without hitting the network. Pass
    /// `force` after a sign-in change to bypass the once-guard.
    func load(accessToken: String?, force: Bool = false) async {
        guard force || !loaded else { return }
        guard let accessToken else {
            prefs = nil
            loaded = true
            lastError = nil
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            prefs = try await LoreAPI.shared.userPrefs(accessToken: accessToken)
            loaded = true
        } catch {
            // Non-fatal: leave the app un-personalized rather than blocking it.
            lastError = "Couldn't load your preferences."
            loaded = true
        }
    }

    /// Reset on a session change (sign-out / sign-in) so the next `load` picks up
    /// the new identity's prefs.
    func reset() {
        prefs = nil
        loaded = false
        lastError = nil
    }

    /// Adopt a freshly-written prefs row (e.g. the onboarding finish-write, or a
    /// Profile edit) without a round-trip, so the map/scanner re-weight at once.
    func adopt(_ newPrefs: UserPrefs?) {
        prefs = newPrefs
        loaded = true
    }
}
