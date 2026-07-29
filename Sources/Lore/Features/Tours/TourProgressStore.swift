import Foundation

/// Device-local tour resume state, scoped to the signed-in account so two
/// travelers sharing an iPhone never inherit one another's place in a walk.
enum TourProgressStore {
    struct Progress: Equatable {
        let stopIndex: Int?
        let isCompleted: Bool

        static let empty = Progress(stopIndex: nil, isCompleted: false)
    }

    private static let prefix = "lore.tour-progress"

    static func progress(
        for tourSlug: String,
        userID: String?,
        stopCount: Int,
        defaults: UserDefaults = .standard
    ) -> Progress {
        let base = keyBase(tourSlug: tourSlug, userID: userID)
        let completed = defaults.bool(forKey: "\(base).completed")
        guard !completed,
              stopCount > 1,
              let stored = defaults.object(forKey: "\(base).stop") as? Int,
              stored > 0
        else {
            return Progress(stopIndex: nil, isCompleted: completed)
        }
        return Progress(stopIndex: min(stored, stopCount - 1), isCompleted: false)
    }

    /// Records only forward progress. Browsing backward or reopening an earlier
    /// checkpoint cannot move the resume point; `restart` is the explicit reset.
    static func advance(
        to stopIndex: Int,
        for tourSlug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        guard stopIndex > 0 else { return }
        let base = keyBase(tourSlug: tourSlug, userID: userID)
        guard !defaults.bool(forKey: "\(base).completed") else { return }
        let key = "\(base).stop"
        let previous = defaults.object(forKey: key) as? Int ?? 0
        defaults.set(max(previous, stopIndex), forKey: key)
    }

    static func complete(
        tourSlug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        let base = keyBase(tourSlug: tourSlug, userID: userID)
        defaults.removeObject(forKey: "\(base).stop")
        defaults.set(true, forKey: "\(base).completed")
    }

    static func restart(
        tourSlug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        let base = keyBase(tourSlug: tourSlug, userID: userID)
        defaults.removeObject(forKey: "\(base).stop")
        defaults.removeObject(forKey: "\(base).completed")
    }

    private static func keyBase(tourSlug: String, userID: String?) -> String {
        let traveler = userID ?? "guest"
        return "\(prefix).\(traveler).\(tourSlug)"
    }
}
