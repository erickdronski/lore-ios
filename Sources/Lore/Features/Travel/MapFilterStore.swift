import Foundation
import Observation

/// Backs the map filter chips (task requirement 3): the set of `place.kind`
/// categories the user has toggled **off**, persisted to `user_prefs.hidden_kinds`
///, the one hard filter in the persona system (13-CURATION-PERSONAS.md §3).
///
/// The chips are kind categories (Buildings, Parks, Statues, …) derived from the
/// city's own places so the row never shows an empty category. A chip is "on" by
/// default; toggling it off adds its kind to `hidden_kinds` (a wall, those pins
/// leave the map), and the change is written back with a targeted `PATCH` that
/// leaves persona/interests untouched.
///
/// Relevance *weighting* (the persona lens dimming non-matching pins) is a
/// separate, softer axis handled by `MapRelevance` off `user_prefs.interests`;
/// these chips are only the hard on/off filter, matching the task's mapping of
/// "category toggles → `hidden_kinds`".
///
/// Signed-out: toggles still work locally (the map filters immediately) and are
/// stashed for a later sign-in flush, mirroring `OnboardingPrefsWriter`.
@Observable
@MainActor
final class MapFilterStore {

    /// `place.kind`s the user hid, the live filter the map reads. Mirrors
    /// `user_prefs.hidden_kinds`.
    private(set) var hiddenKinds: Set<String> = []

    /// The kind categories to show as chips, in a stable display order. Seeded
    /// from prefs' known-hidden kinds, then expanded by `syncCategories(from:)`
    /// as places load so we only show categories the city actually has.
    private(set) var categories: [KindCategory] = []

    var lastError: String?

    /// UserDefaults key for a signed-out user's hidden-kinds, flushed post-login.
    static let pendingHiddenKindsKey = "lore.map.pendingHiddenKinds.v1"

    /// `(userID, accessToken)` or `nil` when signed out, a closure to stay
    /// decoupled from the auth type, like the other Travel stores.
    private let credentials: () -> (userID: String, accessToken: String)?

    init(credentials: @escaping () -> (userID: String, accessToken: String)?) {
        self.credentials = credentials
    }

    // MARK: - Seeding

    /// Adopt the persisted `hidden_kinds` from a loaded `UserPrefs` (or the
    /// signed-out stash). Call once when prefs arrive.
    func adopt(prefs: UserPrefs?) {
        if let prefs {
            hiddenKinds = prefs.hiddenKindSet
        } else if let pending = UserDefaults.standard.stringArray(forKey: Self.pendingHiddenKindsKey) {
            hiddenKinds = Set(pending)
        }
        rebuildCategories()
    }

    /// Learn which kind categories exist in the current city from its places,
    /// so chips are data-driven (never a dead category). Preserves any hidden
    /// state and keeps a stable, human order.
    func syncCategories(from places: [Place]) {
        let kinds = Set(places.map(\.kind))
        knownKinds.formUnion(kinds)
        rebuildCategories()
    }

    // MARK: - Queries

    /// Whether a category chip is currently "on" (its kind not hidden).
    func isOn(_ category: KindCategory) -> Bool {
        !hiddenKinds.contains(category.kind)
    }

    /// Any chip toggled off ⇒ the map is actively filtered. Drives whether
    /// `MapRelevance` dims (a fresh, unfiltered map never dims).
    var hasActiveFilter: Bool { !hiddenKinds.isEmpty }

    /// Whether a place survives the hard filter.
    func allows(_ place: Place) -> Bool {
        !hiddenKinds.contains(place.kind)
    }

    // MARK: - Mutation

    /// Toggle a category on/off. Updates local state immediately (the map
    /// re-filters at once), then persists in the background.
    func toggle(_ category: KindCategory) {
        if hiddenKinds.contains(category.kind) {
            hiddenKinds.remove(category.kind)
        } else {
            hiddenKinds.insert(category.kind)
        }
        Haptics.play(.chipTap)
        persist()
    }

    /// "Show everything", clear the hard filter (§3: always one tap back to
    /// the full map). No-op when nothing is hidden.
    func clear() {
        guard !hiddenKinds.isEmpty else { return }
        hiddenKinds.removeAll()
        Haptics.play(.chipTap)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let kinds = Array(hiddenKinds).sorted()
        guard let creds = credentials() else {
            // Signed out: stash for a post-sign-in flush.
            UserDefaults.standard.set(kinds, forKey: Self.pendingHiddenKindsKey)
            return
        }
        Task {
            do {
                try await TravelReads.updateHiddenKinds(
                    kinds,
                    userID: creds.userID,
                    accessToken: creds.accessToken
                )
                lastError = nil
                UserDefaults.standard.removeObject(forKey: Self.pendingHiddenKindsKey)
            } catch {
                lastError = "Couldn't save your filters."
            }
        }
    }

    /// Flush a signed-out user's stashed hidden-kinds after they sign in.
    static func flushPending(
        userID: String,
        accessToken: String
    ) async throws {
        let defaults = UserDefaults.standard
        guard let pending = defaults.stringArray(forKey: pendingHiddenKindsKey) else { return }
        try await TravelReads.updateHiddenKinds(pending, userID: userID, accessToken: accessToken)
        defaults.removeObject(forKey: pendingHiddenKindsKey)
    }

    // MARK: - Category catalog

    /// Every kind seen so far (from prefs + loaded places).
    private var knownKinds: Set<String> = []

    private func rebuildCategories() {
        // Ensure any already-hidden kind still shows as a (toggled-off) chip
        // even if no place of that kind is currently loaded.
        knownKinds.formUnion(hiddenKinds)
        let cats = knownKinds.map { KindCategory(kind: $0) }
        categories = cats.sorted { lhs, rhs in
            let lo = KindCategory.order.firstIndex(of: lhs.kind) ?? Int.max
            let ro = KindCategory.order.firstIndex(of: rhs.kind) ?? Int.max
            if lo != ro { return lo < ro }
            return lhs.label < rhs.label
        }
    }
}

/// One filter chip: a `place.kind` with a human label + emoji. Grouping is by
/// the raw kind so a toggle maps 1:1 onto `hidden_kinds`.
struct KindCategory: Identifiable, Hashable {
    let kind: String

    var id: String { kind }

    /// Preferred display order for the common kinds; unknowns sort after,
    /// alphabetically, so a new kind is never dropped.
    static let order = [
        "building", "monument", "memorial", "statue", "sculpture", "mural",
        "bridge", "park", "nature", "venue", "stadium", "church", "temple",
    ]

    /// The full standard catalog offered in the Profile preferences editor, so a
    /// user can tune what they see even before any city's places have loaded.
    /// Covers every `place_kind` the schema defines.
    static let catalog: [KindCategory] = [
        "building", "monument", "statue", "mural", "bridge", "park", "plaza",
        "infrastructure", "district", "stadium", "venue", "nature", "market", "other",
    ].map { KindCategory(kind: $0) }

    /// Human, pluralized chip label.
    var label: String {
        switch kind {
        case "building": return "Buildings"
        case "monument": return "Monuments"
        case "memorial": return "Memorials"
        case "statue": return "Statues"
        case "sculpture": return "Sculptures"
        case "mural": return "Murals"
        case "bridge": return "Bridges"
        case "park": return "Parks"
        case "nature": return "Nature"
        case "venue": return "Venues"
        case "stadium": return "Stadiums"
        case "church": return "Churches"
        case "temple": return "Temples"
        default:
            let base = kind.split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            return base.isEmpty ? "Places" : base + "s"
        }
    }

    /// A representative emoji, reusing `Place.displayEmoji`'s per-kind defaults.
    var emoji: String {
        switch kind {
        case "statue", "sculpture": return "🗿"
        case "monument", "memorial": return "🏛️"
        case "bridge": return "🌉"
        case "park", "nature": return "🌳"
        case "church", "temple": return "⛪️"
        case "venue": return "🎭"
        case "stadium": return "🏟️"
        case "mural": return "🎨"
        default: return "🏙️"
        }
    }
}
