import Foundation
import Observation

/// A resolved destination the search / city-switcher surfaces route to. Every
/// `SearchResult.Kind` and every city tap maps to exactly one of these, so the
/// integrator wires *one* switch (in `RootTabView` / `LoreApp`) instead of
/// threading a callback per surface.
///
/// The router deliberately carries the *whole* `SearchResult` (or `City`) for
/// each case, not just an id, the destination screens (`PlaceCardView`,
/// `CityCulture` shelf, nearby-story list) need the label/emoji/city to render
/// a header before their own fetch resolves, and a search hit already has them.
enum LoreRoute: Hashable {
    /// Switch the whole app to this city (fly-to on the map, refilter reads).
    /// `City.slug` is the join key every read surface filters by.
    case city(slug: String)
    /// Open the Layer-1 place card for this place. `ref` is the `place.id`.
    case place(id: String, city: String?)
    /// A "meanwhile-nearby" story, route to the story's city, scroll to it in
    /// the nearby list. `ref` is the `story.id`.
    case story(id: String, city: String?)
    /// A culture note (slang / saying / quote / person), route to that city's
    /// culture shelf. `ref` is the `city_culture.id`.
    case culture(id: String, city: String?)
    /// A curated tour. `ref` is the `tour.slug` (tours key on slug, not id).
    case tour(slug: String, city: String?)

    /// Build the route a search hit resolves to. One place, so the mapping from
    /// `SearchResult.Kind` → screen lives in exactly one spot.
    init(result: SearchResult) {
        switch result.kind {
        case .city:
            // Cities route by slug; the RPC puts the slug in `slug` when it has
            // one, else falls back to `ref` (which is the slug for city rows).
            self = .city(slug: result.slug ?? result.ref)
        case .place:
            self = .place(id: result.ref, city: result.city)
        case .story:
            self = .story(id: result.ref, city: result.city)
        case .culture, .person:
            self = .culture(id: result.ref, city: result.city)
        case .tour:
            self = .tour(slug: result.slug ?? result.ref, city: result.city)
        }
    }
}

/// The shared selection/navigation observable the integrator hooks once at the
/// app root. Search and the city switcher *never* navigate directly, they call
/// `route(_:)`, and whatever the host installed as `onRoute` does the actual
/// tab-switch / sheet-present / map-fly-to.
///
/// This keeps both new surfaces free of any dependency on `LoreApp.swift`
/// (which we must not edit): the host passes an `AppRouter` down through the
/// environment and sets `onRoute` + `selectedCity`; if nobody hooks it, the
/// surfaces still function (they just record the last route/city, harmlessly).
///
/// ```swift
/// // Host side (RootTabView), not edited by this change:
/// @State private var router = AppRouter()
/// …
/// .environment(router)
/// .onAppear {
///     router.onRoute = { route in /* switch tab, present sheet, fly map */ }
/// }
/// ```
@Observable
@MainActor
final class AppRouter {
    /// The city the app is currently scoped to. The city switcher writes this;
    /// the map / reads observe it. Defaults to the pilot city so the app is
    /// never in a city-less state before the switcher is ever opened.
    var selectedCity: String = Config.defaultCity

    /// True once the user has explicitly chosen a city (switcher, a search hit,
    /// or a deep link). Location-based auto-selection never overrides an
    /// explicit choice (TestFlight feedback: "it says Chicago but I'm in Mount
    /// Laurel, it should follow my location").
    private(set) var userDidChooseCity = false

    /// The last route requested, exposed so a host that prefers to *observe*
    /// rather than take a callback can `.onChange(of: router.lastRoute)`.
    private(set) var lastRoute: LoreRoute?

    /// Injected by the host. Receives every route the search / switcher emit.
    /// Left `nil`-safe: an un-hooked router still updates `lastRoute` and
    /// `selectedCity`, so previews and tests work with no wiring.
    var onRoute: ((LoreRoute) -> Void)?

    init(selectedCity: String = Config.defaultCity) {
        self.selectedCity = selectedCity
    }

    /// Route to a resolved destination. Updates `selectedCity` for city routes
    /// (and for any route that names a city, so the app follows the user into
    /// another city when they tap a cross-city hit), records `lastRoute`, then
    /// hands off to the host's `onRoute`.
    func route(_ route: LoreRoute) {
        let resolvedRoute: LoreRoute
        switch route {
        case .city(let slug):
            guard let slug = Self.normalizedSlug(slug) else { return }
            selectedCity = slug
            userDidChooseCity = true
            resolvedRoute = .city(slug: slug)
        case .place(let id, let city):
            if let city = city.flatMap(Self.normalizedSlug) {
                selectedCity = city
                // A cross-city search result or deep link is an explicit choice,
                // just like tapping the city switcher. Never let a later GPS fix
                // silently pull the traveler back to another city.
                userDidChooseCity = true
            }
            resolvedRoute = .place(id: id, city: city.flatMap(Self.normalizedSlug))
        case .story(let id, let city):
            if let city = city.flatMap(Self.normalizedSlug) {
                selectedCity = city
                userDidChooseCity = true
            }
            resolvedRoute = .story(id: id, city: city.flatMap(Self.normalizedSlug))
        case .culture(let id, let city):
            if let city = city.flatMap(Self.normalizedSlug) {
                selectedCity = city
                userDidChooseCity = true
            }
            resolvedRoute = .culture(id: id, city: city.flatMap(Self.normalizedSlug))
        case .tour(let slug, let city):
            if let city = city.flatMap(Self.normalizedSlug) {
                selectedCity = city
                userDidChooseCity = true
            }
            resolvedRoute = .tour(slug: slug, city: city.flatMap(Self.normalizedSlug))
        }
        lastRoute = resolvedRoute
        onRoute?(resolvedRoute)
    }

    /// Convenience: route straight from a search hit.
    func route(_ result: SearchResult) {
        route(LoreRoute(result: result))
    }

    /// Switch the active city by slug (the city switcher's primary action).
    func switchCity(to slug: String) {
        route(.city(slug: slug))
    }

    /// Snap the active city to the user's nearest city (location-based), unless
    /// they've already chosen one. Sets `selectedCity` directly (no route emit)
    /// so it silently re-scopes the map without a jump; a later explicit choice
    /// still wins because this checks `userDidChooseCity`.
    func autoSelectCity(_ slug: String) {
        guard let slug = Self.normalizedSlug(slug),
              !userDidChooseCity,
              slug != selectedCity else { return }
        selectedCity = slug
    }

    /// Handle a `lore://` deep link from a **widget tap** or a **Live Activity**
    /// (docs/16 §7/§8). Supported forms:
    /// - `lore://place/{id}` → open that place's card
    /// - `lore://tour/{slug}` → the Tours surface (deep tour detail is a P1 nicety)
    /// - `lore://map` → just bring the map forward (no-op route beyond that)
    ///
    /// Returns `true` when the URL was understood. Unknown URLs are ignored.
    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == "lore" else { return false }
        // `host` is the verb ("place"/"tour"/"map"); the first path component is
        // the identifier.
        let verb = url.host?.lowercased()
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let ident = components.count == 1
            ? components[0].removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let queryCity = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "city" })?
            .value
            .flatMap(Self.normalizedSlug)
        switch verb {
        case "place":
            guard let ident, !ident.isEmpty else { return false }
            // Current widget builds predate city-bearing URLs. Their place-to-
            // city context is recorded when the snapshot is published, while
            // newer callers can provide `?city=paris` directly.
            let city = queryCity ?? DeepLinkContextStore.city(forPlaceID: ident)
            route(.place(id: ident, city: city))
            return true
        case "tour":
            guard let ident, !ident.isEmpty else { return false }
            route(.tour(slug: ident, city: queryCity))
            return true
        case "map":
            guard components.isEmpty else { return false }
            // Nothing to resolve, the host's onRoute for a city no-op keeps the
            // map foremost. Emit a city route to the current city to surface it.
            route(.city(slug: selectedCity))
            return true
        default:
            return false
        }
    }

    private static func normalizedSlug(_ raw: String) -> String? {
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty,
              slug.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-"
              }) else { return nil }
        return slug
    }
}

/// Small device-local bridge for city-less widget links. The widget snapshot
/// already knows its city; retaining that context means `lore://place/{id}` can
/// switch to the right city before the root resolves the place.
enum DeepLinkContextStore {
    private static let placeCitiesKey = "lore.deep-links.place-cities.v1"

    static func remember(
        city: String,
        forPlaceIDs placeIDs: [String],
        defaults: UserDefaults = .standard
    ) {
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !city.isEmpty else { return }
        let entries = Dictionary(
            uniqueKeysWithValues: placeIDs
                .filter { !$0.isEmpty }
                .map { ($0, city) }
        )
        defaults.set(entries, forKey: placeCitiesKey)
    }

    static func city(
        forPlaceID placeID: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard !placeID.isEmpty,
              let entries = defaults.dictionary(forKey: placeCitiesKey) as? [String: String]
        else { return nil }
        return entries[placeID]
    }
}
