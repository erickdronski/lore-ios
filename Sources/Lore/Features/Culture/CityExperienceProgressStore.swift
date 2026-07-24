import Foundation

/// Device-local completion for lightweight city prompts. It is scoped to the
/// signed-in traveler, while signed-out exploration lives in a separate guest
/// lane and never leaks into another account on the same device.
enum CityExperienceProgressStore {
    private static let prefix = "lore.city-experience"

    static func isCompleted(
        entryID: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: key(entryID: entryID, userID: userID))
    }

    static func complete(
        entryID: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: key(entryID: entryID, userID: userID))
    }

    static func reset(
        entryID: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(entryID: entryID, userID: userID))
    }

    private static func key(entryID: String, userID: String?) -> String {
        "\(prefix).\(userID ?? "guest").\(entryID)"
    }
}
