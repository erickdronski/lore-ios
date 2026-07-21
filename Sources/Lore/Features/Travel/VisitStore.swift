import Foundation
import Observation

/// Caps private-photo signing traffic while visible thumbnails share in-flight
/// work through `VisitStore`. This protects a fast journal scroll from opening
/// dozens of storage requests at once.
private actor JournalRequestGate {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        permits = max(1, limit)
    }

    func run<T>(_ operation: () async -> T) async -> T {
        await acquire()
        let result = await operation()
        release()
        return result
    }

    private func acquire() async {
        guard permits == 0 else {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            permits += 1
            return
        }
        waiters.removeFirst().resume()
    }
}

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

    enum JournalWriteResult: Equatable {
        case saved
        case failed(String)
    }

    /// Injectable journal boundary. Production uses `TravelReads`; focused
    /// tests replace individual operations without changing the shared API.
    struct JournalClient {
        var historyPage: (_ accessToken: String, _ limit: Int, _ offset: Int) async throws -> [VisitLogEntry]
        var historyEntry: (_ placeID: String, _ accessToken: String) async throws -> VisitLogEntry?
        var updateNote: (_ placeID: String, _ note: String, _ accessToken: String) async throws -> Void
        var uploadPhoto: (_ data: Data, _ userID: String, _ placeID: String, _ accessToken: String) async throws -> String
        var updatePhotos: (_ placeID: String, _ paths: [String], _ accessToken: String) async throws -> Void
        var setShared: (_ placeID: String, _ isPublic: Bool, _ accessToken: String) async throws -> Void
        var signedPhotoURL: (_ path: String, _ accessToken: String) async throws -> URL

        static let live = JournalClient(
            historyPage: { token, limit, offset in
                try await TravelReads.visitHistory(accessToken: token, limit: limit, offset: offset)
            },
            historyEntry: { placeID, token in
                try await TravelReads.visitHistoryEntry(placeID: placeID, accessToken: token)
            },
            updateNote: { placeID, note, token in
                try await TravelReads.updateVisitNote(placeID: placeID, note: note, accessToken: token)
            },
            uploadPhoto: { data, userID, placeID, token in
                try await TravelReads.uploadJournalPhoto(
                    data: data,
                    userID: userID,
                    placeID: placeID,
                    accessToken: token
                )
            },
            updatePhotos: { placeID, paths, token in
                try await TravelReads.updateVisitPhotos(placeID: placeID, photos: paths, accessToken: token)
            },
            setShared: { placeID, isPublic, token in
                try await TravelReads.setVisitPublic(placeID: placeID, isPublic: isPublic, accessToken: token)
            },
            signedPhotoURL: { path, token in
                try await TravelReads.signedJournalPhotoURL(path: path, accessToken: token)
            }
        )
    }

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
    private let journal: JournalClient
    private let photoRequestGate = JournalRequestGate(limit: 4)
    private var signedPhotoURLCache: [String: URL] = [:]
    private var signedPhotoURLTasks: [String: Task<URL?, Never>] = [:]
    private var pendingPhotoPaths: [String: String] = [:]
    private var shareWriteTasks: [String: Task<JournalWriteResult, Never>] = [:]
    private var shareWriteGenerations: [String: Int] = [:]

    init(
        api: LoreAPI = .shared,
        credentials: @escaping () -> (userID: String, accessToken: String)?,
        onUnlocks: @escaping ([Achievement]) -> Void = { _ in },
        journal: JournalClient = .live
    ) {
        self.api = api
        self.credentials = credentials
        self.onUnlocks = onUnlocks
        self.journal = journal
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
            guard credentials()?.userID == creds.userID else { return }
            visitedPlaceIDs = Set(rows.map(\.placeID))
            loaded = true
            lastError = nil
        } catch {
            guard credentials()?.userID == creds.userID else { return }
            lastError = "Couldn't load your visits."
        }
    }

    // MARK: - Journal (visit history + the user's own "lore" notes)

    /// The user's visit history with place details + their notes, newest first.
    /// Pages are loaded on demand so opening Journal never hydrates an
    /// unbounded lifetime history.
    static let journalPageSize = 24
    private(set) var visitHistory: [VisitLogEntry] = []
    private(set) var historyLoaded = false
    private(set) var historyLoading = false
    private(set) var historyLoadingMore = false
    private(set) var historyHasMore = false
    private(set) var historyError: String?
    private var historyNextOffset = 0

    func loadHistory(force: Bool = false) async {
        guard force || !historyLoaded else { return }
        guard !historyLoading else { return }
        guard let creds = credentials() else {
            visitHistory = []
            historyLoaded = true
            historyHasMore = false
            historyNextOffset = 0
            return
        }
        historyLoading = true
        defer { historyLoading = false }
        do {
            let rows = try await journal.historyPage(
                creds.accessToken,
                Self.journalPageSize,
                0
            )
            guard credentials()?.userID == creds.userID else { return }
            // One entry per place (a place visited twice shows once, latest
            // first), which also keeps the ForEach ids unique.
            var seen = Set<String>()
            visitHistory = rows.filter { seen.insert($0.placeID).inserted }
            historyNextOffset = rows.count
            historyHasMore = rows.count == Self.journalPageSize
            historyLoaded = true
            historyError = nil
            lastError = nil
        } catch {
            guard credentials()?.userID == creds.userID else { return }
            let message = "Couldn't load your journal. Check your connection and try again."
            historyLoaded = true
            historyError = message
            lastError = message
        }
    }

    /// Fetch one bounded page after the currently loaded raw offset. Duplicate
    /// place rows are skipped without changing the server offset.
    func loadMoreHistory() async {
        guard historyLoaded, historyHasMore, !historyLoadingMore else { return }
        guard let creds = credentials() else { return }
        let offset = historyNextOffset
        historyLoadingMore = true
        defer { historyLoadingMore = false }
        do {
            let rows = try await journal.historyPage(
                creds.accessToken,
                Self.journalPageSize,
                offset
            )
            guard credentials()?.userID == creds.userID else { return }
            var seen = Set(visitHistory.map(\.placeID))
            visitHistory.append(contentsOf: rows.filter { seen.insert($0.placeID).inserted })
            historyNextOffset += rows.count
            historyHasMore = rows.count == Self.journalPageSize
            historyError = nil
            lastError = nil
        } catch {
            guard credentials()?.userID == creds.userID else { return }
            let message = "Couldn't load more journal entries. Try again."
            historyError = message
            lastError = message
        }
    }

    /// Hydrate one place on demand when a card opens an older journal entry
    /// that is outside the currently loaded page. This preserves note, photo,
    /// and sharing truth without returning to an unbounded history request.
    func loadHistoryEntry(placeID: String) async -> VisitLogEntry? {
        if let loaded = visitHistory.first(where: { $0.placeID == placeID }) {
            return loaded
        }
        guard let creds = credentials() else { return nil }
        do {
            guard let entry = try await journal.historyEntry(placeID, creds.accessToken) else { return nil }
            guard credentials()?.userID == creds.userID else { return nil }
            if !visitHistory.contains(where: { $0.placeID == placeID }) {
                visitHistory.append(entry)
            }
            return entry
        } catch {
            guard credentials()?.userID == creds.userID else { return nil }
            lastError = "Couldn't load this journal entry. Check your connection and try again."
            return nil
        }
    }

    /// Save the user's note ("their lore") and report completion to the editor.
    @discardableResult
    func saveNote(placeID: String, note: String) async -> JournalWriteResult {
        guard let creds = credentials() else {
            return journalFailure("Sign in again to save this note.")
        }
        do {
            try await journal.updateNote(placeID, note, creds.accessToken)
            guard credentials()?.userID == creds.userID else {
                return .failed("The account changed before the note finished saving.")
            }
            updateHistoryEntry(placeID: placeID) { $0.withNote(note) }
            lastError = nil
            return .saved
        } catch {
            return journalFailure("Your note wasn't saved. Check your connection and try again.")
        }
    }

    /// Upload a journal photo, then append its private object path to the visit.
    /// If the metadata PATCH fails, the uploaded path is retained for a retry so
    /// the same image is not uploaded repeatedly.
    @discardableResult
    func addPhoto(placeID: String, imageData: Data) async -> JournalWriteResult {
        guard let creds = credentials() else {
            return journalFailure("Sign in again to add this photo.")
        }
        do {
            let path: String
            if let pending = pendingPhotoPaths[placeID] {
                path = pending
            } else {
                path = try await journal.uploadPhoto(
                    imageData,
                    creds.userID,
                    placeID,
                    creds.accessToken
                )
                pendingPhotoPaths[placeID] = path
            }

            let loadedEntry = visitHistory.first { $0.placeID == placeID }
            let serverEntry = loadedEntry == nil
                ? try await journal.historyEntry(placeID, creds.accessToken)
                : nil
            guard let currentEntry = loadedEntry ?? serverEntry else {
                return journalFailure("Log this place before adding a photo.")
            }
            if loadedEntry == nil { visitHistory.append(currentEntry) }
            var paths = currentEntry.photoPaths
            if !paths.contains(path) { paths.append(path) }

            try await journal.updatePhotos(placeID, paths, creds.accessToken)
            guard credentials()?.userID == creds.userID else {
                return .failed("The account changed before the photo finished saving.")
            }
            pendingPhotoPaths[placeID] = nil
            updateHistoryEntry(placeID: placeID) { $0.withPhotos(paths) }
            lastError = nil
            return .saved
        } catch {
            return journalFailure("That photo wasn't saved. Check your connection and try again.")
        }
    }

    /// A short-lived signed URL to display a private journal photo path.
    func signedPhotoURL(path: String) async -> URL? {
        guard let creds = credentials() else { return nil }
        let cacheKey = "\(creds.userID)|\(path)"
        if let cached = signedPhotoURLCache[cacheKey] { return cached }
        if let inFlight = signedPhotoURLTasks[cacheKey] {
            let url = await inFlight.value
            guard credentials()?.userID == creds.userID else { return nil }
            return url
        }

        let journal = journal
        let gate = photoRequestGate
        let task = Task<URL?, Never> {
            await gate.run {
                try? await journal.signedPhotoURL(path, creds.accessToken)
            }
        }
        signedPhotoURLTasks[cacheKey] = task
        let url = await task.value
        signedPhotoURLTasks[cacheKey] = nil
        guard credentials()?.userID == creds.userID else { return nil }
        if let url { signedPhotoURLCache[cacheKey] = url }
        return url
    }

    /// Opt this place's lore in or out of the public traveler layer, then
    /// update local truth. Writes for one place are chained in request order so
    /// a slower earlier PATCH cannot overwrite the user's newest toggle.
    @discardableResult
    func setShared(placeID: String, isPublic: Bool) async -> JournalWriteResult {
        guard let creds = credentials() else {
            return journalFailure("Sign in again to change sharing.")
        }

        let previous = shareWriteTasks[placeID]
        let generation = (shareWriteGenerations[placeID] ?? 0) + 1
        shareWriteGenerations[placeID] = generation
        let journal = journal
        let operation = Task<JournalWriteResult, Never> { @MainActor [weak self] in
            if let previous { _ = await previous.value }
            do {
                try await journal.setShared(placeID, isPublic, creds.accessToken)
                guard let self else { return .saved }
                if self.credentials()?.userID == creds.userID {
                    self.updateHistoryEntry(placeID: placeID) { $0.withSharing(isPublic) }
                    self.lastError = nil
                }
                return .saved
            } catch {
                guard let self else {
                    return .failed("Sharing wasn't changed. Try again.")
                }
                if self.credentials()?.userID == creds.userID {
                    return self.journalFailure("Sharing wasn't changed. Check your connection and try again.")
                }
                return .failed("The account changed before sharing finished updating.")
            }
        }
        shareWriteTasks[placeID] = operation
        let result = await operation.value
        if shareWriteGenerations[placeID] == generation {
            shareWriteTasks[placeID] = nil
        }
        return result
    }

    private func updateHistoryEntry(
        placeID: String,
        transform: (VisitLogEntry) -> VisitLogEntry
    ) {
        guard let index = visitHistory.firstIndex(where: { $0.placeID == placeID }) else { return }
        visitHistory[index] = transform(visitHistory[index])
    }

    private func journalFailure(_ message: String) -> JournalWriteResult {
        lastError = message
        return .failed(message)
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
        historyLoading = false
        historyLoadingMore = false
        historyHasMore = false
        historyError = nil
        historyNextOffset = 0
        signedPhotoURLTasks.values.forEach { $0.cancel() }
        signedPhotoURLTasks = [:]
        signedPhotoURLCache = [:]
        pendingPhotoPaths = [:]
        lastError = nil
    }
}
