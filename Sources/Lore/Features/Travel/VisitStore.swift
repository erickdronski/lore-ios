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
/// `SignInView`): with no session the store holds an empty set and write methods
/// return a signed-out result or a useful error so the caller can nudge sign-in.
/// Credentials arrive as a closure, the same decoupling
/// `OnboardingPrefsWriter` uses, so this type never imports the auth layer.
@Observable
@MainActor
final class VisitStore {
    typealias VisitsLoader = (String) async throws -> [Visit]
    typealias VisitHistoryLoader = (String) async throws -> [VisitLogEntry]

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

    /// Changes on reset and account changes, including signing back into the
    /// same account. Views use this identity to discard already-resolved URLs.
    private(set) var photoSessionGeneration = UUID()
    @ObservationIgnored private var photoUserID: String?
    private let photoURLs: PhotoURLLoader
    /// Reading a preview during view rendering updates only ignored LRU state.
    @ObservationIgnored private var photoPreviewCache = PhotoPreviewCache()
    private let visitsLoader: VisitsLoader
    private let visitHistoryLoader: VisitHistoryLoader

    init(
        api: LoreAPI = .shared,
        credentials: @escaping () -> (userID: String, accessToken: String)?,
        visitsLoader: @escaping VisitsLoader = { accessToken in
            try await TravelReads.visits(accessToken: accessToken)
        },
        visitHistoryLoader: @escaping VisitHistoryLoader = { accessToken in
            try await TravelReads.visitHistory(accessToken: accessToken)
        },
        onUnlocks: @escaping ([Achievement]) -> Void = { _ in },
        photoURLSigner: @escaping PhotoURLLoader.Signer = { path, accessToken in
            try await TravelReads.signedJournalPhotoURL(path: path, accessToken: accessToken)
        },
        photoURLClock: @escaping () -> Date = Date.init,
        photoURLLimits: PhotoURLLoader.Limits = .init()
    ) {
        self.api = api
        self.credentials = credentials
        self.visitsLoader = visitsLoader
        self.visitHistoryLoader = visitHistoryLoader
        self.onUnlocks = onUnlocks
        self.photoURLs = PhotoURLLoader(signer: photoURLSigner, now: photoURLClock, limits: photoURLLimits)
        self.photoUserID = credentials()?.userID
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
            let rows = try await visitsLoader(creds.accessToken)
            guard credentials()?.userID == creds.userID else { return }
            visitedPlaceIDs = Set(rows.map(\.placeID))
            loaded = true
            lastError = nil
        } catch {
            guard credentials()?.userID == creds.userID else { return }
            loaded = true
            lastError = "Couldn't load your visits."
        }
    }

    // MARK: - Journal (visit history + the user's own "lore" notes)

    /// The user's full visit history with place details + their notes, newest
    /// first. Loaded on demand when the Journal appears.
    private(set) var visitHistory: [VisitLogEntry] = []
    private(set) var historyLoaded = false
    private var historyLoadGeneration = 0

    func loadHistory(force: Bool = false) async {
        guard force || !historyLoaded else { return }
        historyLoadGeneration &+= 1
        let generation = historyLoadGeneration
        guard let creds = credentials() else {
            visitHistory = []
            historyLoaded = true
            return
        }
        do {
            let rows = try await visitHistoryLoader(creds.accessToken)
            guard generation == historyLoadGeneration,
                  credentials()?.userID == creds.userID else { return }
            // One entry per place (a place visited twice shows once, latest
            // first), which also keeps the ForEach ids unique.
            var seen = Set<String>()
            visitHistory = rows.filter { seen.insert($0.placeID).inserted }
            historyLoaded = true
            lastError = nil
        } catch {
            guard generation == historyLoadGeneration,
                  credentials()?.userID == creds.userID else { return }
            lastError = "Couldn't load your journal."
        }
    }

    /// Save the user's note ("their lore") on a visited place, then refresh.
    @discardableResult
    func saveNote(placeID: String, note: String) async -> Bool {
        guard let creds = synchronizePhotoSession() else {
            lastError = "Sign in to save a journal note."
            return false
        }
        let generation = photoSessionGeneration
        do {
            lastError = nil
            try await TravelReads.updateVisitNote(placeID: placeID, note: note, accessToken: creds.accessToken)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            await settleAchievements(for: creds, photoGeneration: generation)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            await loadHistory(force: true)
            return isCurrentPhotoSession(generation, userID: creds.userID)
        } catch {
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            lastError = "Couldn't save your note."
            return false
        }
    }

    /// Upload a journal photo for a place, append its path, and refresh.
    @discardableResult
    func addPhoto(placeID: String, imageData: Data) async -> String? {
        guard let creds = synchronizePhotoSession() else {
            lastError = "Sign in to add a journal photo."
            return nil
        }
        let generation = photoSessionGeneration
        do {
            lastError = nil
            let path = try await TravelReads.storeJournalPhoto(
                data: imageData, userID: creds.userID, placeID: placeID, accessToken: creds.accessToken
            )
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return nil }
            photoPreviewCache.insert(imageData, for: path)
            await settleAchievements(for: creds, photoGeneration: generation)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return nil }
            await loadHistory(force: true)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return nil }
            return path
        } catch {
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return nil }
            lastError = "Couldn't add that photo."
            return nil
        }
    }

    /// Remove one journal photo (array + storage) and refresh.
    @discardableResult
    func removePhoto(placeID: String, path: String) async -> Bool {
        guard let creds = synchronizePhotoSession() else {
            lastError = "Sign in to manage journal photos."
            return false
        }
        let generation = photoSessionGeneration
        invalidatePhoto(path: path)
        defer {
            // Storage deletion can succeed even if removing its database
            // reference fails. Never retain a capability or preview for it.
            if isCurrentPhotoSession(generation, userID: creds.userID) {
                invalidatePhoto(path: path)
            }
        }
        do {
            lastError = nil
            try await TravelReads.removeVisitPhoto(placeID: placeID, path: path, accessToken: creds.accessToken)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            invalidatePhoto(path: path)
            await loadHistory(force: true)
            return isCurrentPhotoSession(generation, userID: creds.userID)
        } catch {
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            lastError = "Couldn't remove that photo."
            return false
        }
    }

    /// Delete a whole memory — the visit row and its private photos — and
    /// refresh both the visited set and the history.
    @discardableResult
    func deleteVisit(placeID: String, photoPaths: [String]) async -> Bool {
        guard let creds = synchronizePhotoSession() else {
            lastError = "Sign in to manage your memories."
            return false
        }
        let generation = photoSessionGeneration
        for path in photoPaths { invalidatePhoto(path: path) }
        defer {
            // Storage deletion can succeed even if removing its database
            // reference fails. Never retain a capability or preview for it.
            if isCurrentPhotoSession(generation, userID: creds.userID) {
                for path in photoPaths { invalidatePhoto(path: path) }
            }
        }
        do {
            lastError = nil
            try await TravelReads.deleteVisit(placeID: placeID, photoPaths: photoPaths, accessToken: creds.accessToken)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            visitedPlaceIDs.remove(placeID)
            for path in photoPaths {
                invalidatePhoto(path: path)
            }
            await settleAchievements(for: creds, photoGeneration: generation)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            await loadHistory(force: true)
            return isCurrentPhotoSession(generation, userID: creds.userID)
        } catch {
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            lastError = "Couldn't remove that memory."
            return false
        }
    }

    /// A short-lived signed URL to display a private journal photo path.
    func signedPhotoURL(path: String, forceRefresh: Bool = false) async -> URL? {
        guard let creds = synchronizePhotoSession() else { return nil }
        let generation = photoSessionGeneration
        let url = await photoURLs.url(path: path, accessToken: creds.accessToken, forceRefresh: forceRefresh)
        guard !Task.isCancelled,
              isCurrentPhotoSession(generation, userID: creds.userID) else { return nil }
        return url
    }

    /// Local preview bytes for a newly uploaded private photo. The durable
    /// source remains Storage + visit.photos. Never return another owner's data,
    /// including before the app's session-change callback has run.
    func cachedPhotoPreview(path: String) -> Data? {
        guard let userID = credentials()?.userID, userID == photoUserID else { return nil }
        return photoPreviewCache.data(for: path)
    }

    private func invalidatePhoto(path: String) {
        photoURLs.invalidate(path: path)
        photoPreviewCache.remove(path)
    }

    private func synchronizePhotoSession() -> (userID: String, accessToken: String)? {
        let creds = credentials()
        if creds?.userID != photoUserID { resetPhotoSession(userID: creds?.userID) }
        return creds
    }

    private func isCurrentPhotoSession(_ generation: UUID, userID: String) -> Bool {
        let creds = synchronizePhotoSession()
        return photoSessionGeneration == generation && creds?.userID == userID
    }

    private func resetPhotoSession(userID: String?) {
        photoSessionGeneration = UUID()
        photoUserID = userID
        photoURLs.reset()
        photoPreviewCache.removeAll()
    }

    /// Clear a stale public flag from an older client before saving the private
    /// journal entry. There is intentionally no operation that sets it true.
    @discardableResult
    func makePrivateIfNeeded(placeID: String) async -> Bool {
        guard let creds = synchronizePhotoSession() else {
            lastError = "Sign in to update your private journal."
            return false
        }
        let generation = photoSessionGeneration
        do {
            lastError = nil
            try await TravelReads.makeVisitPrivate(
                placeID: placeID, accessToken: creds.accessToken
            )
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            await settleAchievements(for: creds, photoGeneration: generation)
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            await loadHistory(force: true)
            return isCurrentPhotoSession(generation, userID: creds.userID)
        } catch {
            guard isCurrentPhotoSession(generation, userID: creds.userID) else { return false }
            lastError = "Couldn't secure that journal entry."
            return false
        }
    }

    /// Journal actions have their own achievement families. Settle them at the
    /// moment the action lands instead of waiting for the user's next visit.
    private func settleAchievements(
        for creds: (userID: String, accessToken: String), photoGeneration: UUID? = nil
    ) async {
        let unlocked = (try? await api.recomputeAchievements(
            userID: creds.userID,
            accessToken: creds.accessToken
        )) ?? []
        guard credentials()?.userID == creds.userID else { return }
        if let photoGeneration,
           !isCurrentPhotoSession(photoGeneration, userID: creds.userID) { return }
        if !unlocked.isEmpty { onUnlocks(unlocked) }
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
            guard credentials()?.userID == creds.userID else {
                return .logged(unlocked: [])
            }
            lastError = nil
            if !unlocked.isEmpty { onUnlocks(unlocked) }
            return .logged(unlocked: unlocked)
        } catch {
            guard credentials()?.userID == creds.userID else {
                return .failed("The account changed before the visit finished.")
            }
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
        visitHistory = []
        historyLoaded = false
        historyLoadGeneration &+= 1
        resetPhotoSession(userID: credentials()?.userID)
        lastError = nil
    }
}
