import Foundation
import Observation

/// The "Been here" state store, the source of truth for which places the
/// signed-in user has logged an "I was here" visit at, plus the write path that
/// records a new visit and settles any freshly-unlocked achievements.
///
/// Travel tracking is the map's half of the Passport loop (docs/02 §7, the
/// visit → `recompute_achievements` → celebration chain also wired from the
/// Scanner). This store is **additive**: it does not touch `MapScreen`. An
/// integrator hands it to `VisitToggle` and `NearMeShelf`, and forwards the
/// unlock stream to `PassportModel.recomputeAndCelebrate` (or drops it into an
/// `UnlockCelebration` overlay) via `onUnlocks`.
///
/// Signed-out is a first-class state (browsing never requires an account, see
/// `SignInView`): with no session the store simply holds an empty set and every
/// write is a silent no-op that reports `.signedOut` so the caller can nudge
/// sign-in. Credentials arrive as a closure, the same decoupling
/// `OnboardingPrefsWriter` uses, so this type never imports the auth layer.
@Observable
@MainActor
final class VisitStore {

    /// Place ids the user has visited at least once. Membership is what the
    /// toggle and shelf read; the map integrator dims/marks visited pins from it.
    private(set) var visitedPlaceIDs: Set<String> = []

    /// Place ids with a visit write currently in flight, lets the toggle show a
    /// spinner and guards against double-taps hammering `POST /visit`.
    private(set) var inFlightPlaceIDs: Set<String> = []

    /// True once `load()` has populated the set (so a shelf can distinguish
    /// "no visits yet" from "not loaded").
    private(set) var loaded = false

    /// Last write/load error surfaced for optional UI (never blocks the app).
    var lastError: String?

    /// The signed-in user's `(userID, accessToken)`, or `nil` when signed out.
    /// A closure (not a stored `AuthService`) keeps this decoupled from the auth
    /// type, the integrator wires it to `auth.session`.
    private let credentials: () -> (userID: String, accessToken: String)?

    /// Called with the achievements a visit newly unlocked, on the main actor.
    /// The integrator forwards these to the Passport celebration (a shared
    /// closure, per the task's "hand to the Passport celebration" contract).
    /// Settable so an owner (e.g. `TravelSession`) can wire it after `self` is
    /// fully initialized, avoiding init-ordering gymnastics.
    var onUnlocks: ([Achievement]) -> Void

    private let api: LoreAPI

    init(
        api: LoreAPI = .shared,
        credentials: @escaping () -> (userID: String, accessToken: String)?,
        onUnlocks: @escaping ([Achievement]) -> Void = { _ in }
    ) {
        self.api = api
        self.credentials = credentials
        self.onUnlocks = onUnlocks
    }

    // MARK: - Queries

    /// Whether the user has logged a visit at this place.
    func hasVisited(_ placeID: String) -> Bool {
        visitedPlaceIDs.contains(placeID)
    }

    /// Whether a visit write is currently in flight for this place.
    func isInFlight(_ placeID: String) -> Bool {
        inFlightPlaceIDs.contains(placeID)
    }

    /// The user is signed in and can log visits.
    var canLogVisits: Bool { credentials() != nil }

    // MARK: - Loading

    /// Hydrate `visitedPlaceIDs` from the server. Idempotent-ish: safe to call
    /// on appear; pass `force` to bypass the once-guard after a sign-in change.
    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        guard let creds = credentials() else {
            // Signed out: nothing to hydrate, but mark loaded so shelves render.
            visitedPlaceIDs = []
            loaded = true
            return
        }
        do {
            let rows = try await TravelReads.visits(accessToken: creds.accessToken)
            visitedPlaceIDs = Set(rows.map(\.placeID))
            loaded = true
            lastError = nil
        } catch {
            lastError = "Couldn't load your visits."
        }
    }

    // MARK: - Journal (visit history + the user's own "lore" notes)

    /// The user's full visit history with place details + their notes, newest
    /// first. Loaded on demand when the Journal appears.
    private(set) var visitHistory: [VisitLogEntry] = []
    private(set) var historyLoaded = false

    func loadHistory() async {
        guard let creds = credentials() else { visitHistory = []; historyLoaded = true; return }
        do {
            visitHistory = try await TravelReads.visitHistory(accessToken: creds.accessToken)
            historyLoaded = true
            lastError = nil
        } catch {
            lastError = "Couldn't load your journal."
        }
    }

    /// Save the user's note ("their lore") on a visited place, then refresh.
    func saveNote(placeID: String, note: String) async {
        guard let creds = credentials() else { return }
        do {
            try await TravelReads.updateVisitNote(placeID: placeID, note: note, accessToken: creds.accessToken)
            await loadHistory()
        } catch {
            lastError = "Couldn't save your note."
        }
    }

    // MARK: - Writes

    /// Outcome of a visit-log attempt, so the toggle can react (haptic, copy).
    enum LogResult {
        /// The place is now marked visited (either freshly logged, with any
        /// newly-unlocked badges, or it was already visited).
        case logged(unlocked: [Achievement])
        /// Already recorded, no write was made.
        case alreadyVisited
        /// No signed-in user; the caller should nudge sign-in.
        case signedOut
        /// The write failed; the optimistic mark was rolled back.
        case failed(String)
    }

    /// Log an "I was here" visit for a place, then settle achievements.
    ///
    /// Flow (task requirement 1): optimistically mark visited → `POST /visit`
    /// → `recompute_achievements` → surface returned unlocks through `onUnlocks`
    /// and return them. Idempotent per session: a place already in the set is a
    /// no-op `.alreadyVisited`. On failure the optimistic mark is rolled back.
    @discardableResult
    func logVisit(placeID: String, source: Visit.Source = .map) async -> LogResult {
        guard !visitedPlaceIDs.contains(placeID) else { return .alreadyVisited }
        guard let creds = credentials() else { return .signedOut }
        guard !inFlightPlaceIDs.contains(placeID) else { return .alreadyVisited }

        // Optimistic: mark visited immediately so the pin/toggle flips at once.
        visitedPlaceIDs.insert(placeID)
        inFlightPlaceIDs.insert(placeID)
        defer { inFlightPlaceIDs.remove(placeID) }

        do {
            try await api.logVisit(
                placeID: placeID,
                source: source,
                accessToken: creds.accessToken
            )
            // Settle badges; a recompute failure must not undo a real visit.
            let unlocked = (try? await api.recomputeAchievements(
                userID: creds.userID,
                accessToken: creds.accessToken
            )) ?? []
            lastError = nil
            if !unlocked.isEmpty { onUnlocks(unlocked) }
            return .logged(unlocked: unlocked)
        } catch {
            // Roll back the optimistic mark, the visit didn't land.
            visitedPlaceIDs.remove(placeID)
            let message = (error as? LoreAPI.APIError)?.errorDescription
                ?? "Couldn't log that visit."
            lastError = message
            return .failed(message)
        }
    }

    /// Locally drop a visit mark (e.g. an "undo" affordance). The `visit` table
    /// is append-only server-side at P0 (no client DELETE policy), so this only
    /// updates local state; a future unvisit endpoint would replace this body.
    func forgetLocally(placeID: String) {
        visitedPlaceIDs.remove(placeID)
    }

    /// Reset for a session change (sign-out/sign-in). Clears state so the next
    /// `load()` re-hydrates for the new identity.
    func reset() {
        visitedPlaceIDs = []
        inFlightPlaceIDs = []
        loaded = false
        lastError = nil
    }
}
