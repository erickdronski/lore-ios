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

    /// An optional positive "collection" filter (Family, Music, Museums, Food,
    /// Free, Art, Nature, Nightlife). When set, only places matching the
    /// collection show, on top of the hard kind filter. Single-select and NOT
    /// persisted, a transient "show me the X" lens, tap the active chip to clear.
    private(set) var activeCollection: PlaceCollection?

    /// Set (or, if already active, clear) the collection lens. Never persisted.
    func setCollection(_ collection: PlaceCollection?) {
        activeCollection = (activeCollection == collection) ? nil : collection
        Haptics.play(.chipTap)
    }

    /// UserDefaults key for a signed-out user's hidden-kinds, flushed post-login.
    static let pendingHiddenKindsKey = "lore.map.pendingHiddenKinds.v1"

    /// `(userID, accessToken)` or `nil` when signed out, a closure to stay
    /// decoupled from the auth type, like the other Travel stores.
    private let credentials: () -> (userID: String, accessToken: String)?
    private let writeHiddenKinds: ([String], String, String) async throws -> Void

    init(
        credentials: @escaping () -> (userID: String, accessToken: String)?,
        writeHiddenKinds: @escaping ([String], String, String) async throws -> Void = { kinds, userID, token in
            try await TravelReads.updateHiddenKinds(
                kinds,
                userID: userID,
                accessToken: token
            )
        }
    ) {
        self.credentials = credentials
        self.writeHiddenKinds = writeHiddenKinds
    }

    // MARK: - Seeding

    /// Adopt the persisted `hidden_kinds` from a loaded `UserPrefs` (or the
    /// signed-out stash). Call once when prefs arrive.
    func adopt(prefs: UserPrefs?) {
        if let prefs {
            hiddenKinds = prefs.hiddenKindSet
        } else {
            // Session changes must not leak the previous account's filters into
            // signed-out browsing. Only an explicit guest stash survives.
            hiddenKinds = Set(
                UserDefaults.standard.stringArray(forKey: Self.pendingHiddenKindsKey) ?? []
            )
        }
        lastError = nil
        rebuildCategories()
    }

    /// Learn which kind categories exist in the current city from its places,
    /// so chips are data-driven (never a dead category). Preserves any hidden
    /// state and keeps a stable, human order.
    func syncCategories(from places: [Place]) {
        // Replace rather than union: chips describe the current city, not every
        // category encountered during the entire session.
        availableKinds = Set(places.map(\.kind))
        rebuildCategories()
    }

    // MARK: - Queries

    /// Whether a category chip is currently "on" (its kind not hidden).
    func isOn(_ category: KindCategory) -> Bool {
        !hiddenKinds.contains(category.kind)
    }

    /// Any kind hidden OR a collection lens active ⇒ the map is filtered. Drives
    /// whether `MapRelevance` dims (a fresh, unfiltered map never dims).
    var hasActiveFilter: Bool { !hiddenKinds.isEmpty || activeCollection != nil }

    /// Whether a place survives the hard kind filter AND the collection lens.
    func allows(_ place: Place) -> Bool {
        if hiddenKinds.contains(place.kind) { return false }
        if let collection = activeCollection, !collection.matches(place) { return false }
        return true
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
        guard !hiddenKinds.isEmpty || activeCollection != nil else { return }
        hiddenKinds.removeAll()
        activeCollection = nil
        Haptics.play(.chipTap)
        persist()
    }

    /// Retry a failed server write without changing the current filter state.
    func retryPersistence() {
        lastError = nil
        persist()
    }

    // MARK: - Persistence

    private var persistenceRevision = 0
    private var persistenceTask: Task<Void, Never>?

    private func persist() {
        persistenceRevision += 1
        guard persistenceTask == nil else { return }
        persistenceTask = Task { [weak self] in
            // Coalesce a quick run across the horizontal chip row, then serialize
            // writes. If the traveler changes another chip while one PATCH is in
            // flight, the final state is sent immediately after it.
            try? await Task.sleep(for: .milliseconds(180))
            await self?.persistenceLoop()
        }
    }

    private func persistenceLoop() async {
        while true {
            let revision = persistenceRevision
            let kinds = Array(hiddenKinds).sorted()

            if let creds = credentials() {
                do {
                    try await writeHiddenKinds(
                        kinds,
                        creds.userID,
                        creds.accessToken
                    )
                    UserDefaults.standard.removeObject(forKey: Self.pendingHiddenKindsKey)
                    if revision == persistenceRevision { lastError = nil }
                } catch {
                    if revision == persistenceRevision {
                        lastError = "Couldn't save your filters."
                    }
                }
            } else {
                // Signed out: stash for a post-sign-in flush.
                UserDefaults.standard.set(kinds, forKey: Self.pendingHiddenKindsKey)
                if revision == persistenceRevision { lastError = nil }
            }

            guard revision != persistenceRevision else {
                persistenceTask = nil
                return
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

    /// Kinds present in the currently loaded city.
    private var availableKinds: Set<String> = []

    private func rebuildCategories() {
        let cats = availableKinds.map { KindCategory(kind: $0) }
        categories = cats.sorted { lhs, rhs in
            let lo = KindCategory.order.firstIndex(of: lhs.kind) ?? Int.max
            let ro = KindCategory.order.firstIndex(of: rhs.kind) ?? Int.max
            if lo != ro { return lo < ro }
            return lhs.label < rhs.label
        }
    }
}

/// A positive "collection" lens over the map: tap "Family" and only family
/// places show. Matched from `place.tags` + `place.kind` (the app has no price
/// data, so "Free" is a heuristic over free-to-see public/outdoor kinds). These
/// answer the family / music / museum / foodie personas without new content.
enum PlaceCollection: String, CaseIterable, Identifiable {
    case family, music, museums, food, free, art, nature, nightlife

    var id: String { rawValue }

    var label: String {
        switch self {
        case .family: return "Family"
        case .music: return "Live Music"
        case .museums: return "Museums"
        case .food: return "Food"
        case .free: return "Free"
        case .art: return "Art"
        // "Outdoors", not "Nature": the kind-category row below already has a
        // literal "Nature" chip (place_kind == nature), and two identically
        // labelled chips one row apart read as a duplicate-rendering bug. This
        // lens is deliberately broader — parks, gardens, springs and trails too.
        case .nature: return "Outdoors"
        case .nightlife: return "Nightlife"
        }
    }

    var emoji: String {
        switch self {
        case .family: return "👨‍👩‍👧"
        case .music: return "🎸"
        case .museums: return "🏛️"
        case .food: return "🍽️"
        case .free: return "🆓"
        case .art: return "🎨"
        case .nature: return "🌳"
        case .nightlife: return "🍸"
        }
    }

    func matches(_ place: Place) -> Bool {
        let tags = Set(place.tags.map { $0.lowercased() })
        let hasTag: (String) -> Bool = { needle in tags.contains { $0.contains(needle) } }
        switch self {
        case .family:    return hasTag("family") || hasTag("kid") || tags.contains("wildlife") || tags.contains("playground")
        case .music:     return hasTag("music") || tags.contains("live-music")
        case .museums:   return tags.contains("museum") || hasTag("museum")
        case .food:      return hasTag("food") || hasTag("bbq") || hasTag("restaurant") || hasTag("taco") || hasTag("dining")
        case .free:      return ["park", "nature", "plaza", "monument", "mural", "district", "bridge", "statue"].contains(place.kind)
        case .art:       return place.kind == "mural" || hasTag("public-art") || hasTag("art")
        case .nature:    return place.kind == "nature" || place.kind == "park" || hasTag("garden") || hasTag("spring") || tags.contains("trail")
        case .nightlife: return tags.contains("nightlife") || hasTag("night") || hasTag("bar") || hasTag("club")
        }
    }

    /// The collections that actually have >=2 matching places in the current set,
    /// so the chip row never offers an empty lens.
    static func available(in places: [Place]) -> [PlaceCollection] {
        allCases.filter { c in places.filter(c.matches).count >= 2 }
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
