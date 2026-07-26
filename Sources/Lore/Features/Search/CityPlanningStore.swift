import Foundation

/// Device-local trip planning, scoped to the signed-in traveler. City pins are
/// intentionally private and available offline; they never leave the device.
enum CityPlanningStore {
    private static let prefix = "lore.city-planning"

    static func cities(
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var saved = normalized(defaults.stringArray(forKey: key(userID: userID)) ?? [])

        // Planning is useful before account creation. Claim those private guest
        // plans on the first signed-in read rather than making a new member pin
        // the same trip twice, then clear the unowned guest bucket.
        if userID != nil {
            let guestKey = key(userID: nil)
            let guest = normalized(defaults.stringArray(forKey: guestKey) ?? [])
            if !guest.isEmpty {
                saved.formUnion(guest)
                defaults.set(saved.sorted(), forKey: key(userID: userID))
                defaults.removeObject(forKey: guestKey)
            }
        }
        return saved
    }

    @discardableResult
    static func toggle(
        city slug: String,
        userID: String?,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var saved = cities(userID: userID, defaults: defaults)
        guard let slug = normalized([slug]).first else { return saved }
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

    private static func normalized(_ slugs: [String]) -> Set<String> {
        Set(slugs.compactMap { raw in
            let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return slug.isEmpty ? nil : slug
        })
    }
}
