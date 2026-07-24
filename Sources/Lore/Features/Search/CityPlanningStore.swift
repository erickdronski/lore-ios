import Foundation

/// Device-local trip planning, scoped to the signed-in traveler. City pins are
/// intentionally private and available offline; they never leave the device.
enum CityPlanningStore {
    private static let prefix = "lore.city-planning"

    static func cities(
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        Set(defaults.stringArray(forKey: key(userID: userID)) ?? [])
    }

    @discardableResult
    static func toggle(
        city slug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var saved = cities(userID: userID, defaults: defaults)
        if saved.contains(slug) {
            saved.remove(slug)
        } else {
            saved.insert(slug)
        }
        defaults.set(saved.sorted(), forKey: key(userID: userID))
        return saved
    }

    private static func key(userID: String?) -> String {
        "\(prefix).\(userID ?? "guest")"
    }
}
