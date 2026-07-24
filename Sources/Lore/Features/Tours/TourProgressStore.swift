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

    static func save(
        stopIndex: Int,
        for tourSlug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        let key = "\(keyBase(tourSlug: tourSlug, userID: userID)).stop"
        if stopIndex > 0 {
            defaults.set(stopIndex, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
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
