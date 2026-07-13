import Foundation

/// The small, Codable snapshot the **app writes** to a shared App Group
/// container after each near-me refresh and the **widget reads** on its timeline
/// (docs/16-APPLE-TOOLKITS.md §7). The widget can't hit the network freely, so
/// this cached hand-off is the contract between the two targets.
///
/// Kept intentionally lean, a handful of nearby places, each just enough to
/// render a "daily lore" (small) or "around you" (medium) card and deep-link
/// back into the app.
public struct LoreWidgetSnapshot: Codable, Equatable {
    /// When the app wrote this snapshot (for a discreet "updated 2h ago" note
    /// and staleness decisions).
    public var updatedAt: Date
    /// The city these places belong to (widget subtitle + deep-link scope).
    public var city: String
    /// Nearest un-visited places, already ranked by the app's near-me logic.
    public var places: [Place]

    public init(updatedAt: Date, city: String, places: [Place]) {
        self.updatedAt = updatedAt
        self.city = city
        self.places = places
    }

    /// One place, projected to only what a widget cell needs.
    public struct Place: Codable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// Emoji badge (mirrors `Place.displayEmoji` in the app).
        public var emoji: String
        /// The Layer-1 hook line, the one-sentence "why you'd care."
        public var hook: String?
        /// Build year, when known ("1973").
        public var year: Int?

        public init(id: String, name: String, emoji: String, hook: String?, year: Int?) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.hook = hook
            self.year = year
        }
    }

    /// The first place, the "daily lore" hero for the small widget.
    public var featured: Place? { places.first }

    /// An honest empty snapshot (no city, no places). Used as the widget's
    /// live-timeline fallback so a missing App Group / cold app renders the
    /// "Open Lore to load stories near you" empty state, never sample landmarks
    /// presented as the user's real surroundings.
    public static let empty = LoreWidgetSnapshot(updatedAt: .distantPast, city: "", places: [])
}

/// Reads/writes `LoreWidgetSnapshot` through the shared App Group `UserDefaults`.
///
/// **App Group is a portal-gated capability** (docs/16 §7): the group
/// `group.com.erickdronski.lore` must be created in the Apple Developer portal and added
/// to *both* the app and the widget extension entitlements before this resolves
/// at runtime. The `project.yml` notes this; until it's provisioned,
/// `sharedDefaults` is `nil` and every call no-ops gracefully (the widget shows
/// its honest empty state, the app's write is a silent miss), nothing crashes.
public enum LoreWidgetStore {
    /// The App Group identifier. Must match the entitlement on both targets.
    public static let appGroupID = "group.com.erickdronski.lore"

    /// The single key the snapshot lives under.
    private static let snapshotKey = "widget.snapshot.v1"

    /// The App Group defaults, or `nil` if the group isn't provisioned yet.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Persist the latest near-me snapshot for the widget. Called by the app
    /// after a near-me refresh (best-effort; a nil group is a silent no-op).
    public static func write(_ snapshot: LoreWidgetSnapshot) {
        guard let defaults = sharedDefaults else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    /// Read the last snapshot the app wrote, or `nil` if none / group missing.
    public static func read() -> LoreWidgetSnapshot? {
        guard
            let defaults = sharedDefaults,
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(LoreWidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
