import Foundation
import Observation

/// A resolved destination the search / city-switcher surfaces route to. Every
/// `SearchResult.Kind` and every city tap maps to exactly one of these, so the
/// integrator wires *one* switch (in `RootTabView` / `LoreApp`) instead of
/// threading a callback per surface.
///
/// The router deliberately carries the *whole* `SearchResult` (or `City`) for
/// each case, not just an id — the destination screens (`PlaceCardView`,
/// `CityCulture` shelf, nearby-story list) need the label/emoji/city to render
/// a header before their own fetch resolves, and a search hit already has them.
enum LoreRoute: Hashable {
    /// Switch the whole app to this city (fly-to on the map, refilter reads).
    /// `City.slug` is the join key every read surface filters by.
    case city(slug: String)
    /// Open the Layer-1 place card for this place. `ref` is the `place.id`.
    case place(id: String, city: String?)
    /// A "meanwhile-nearby" story — route to the story's city, scroll to it in
    /// the nearby list. `ref` is the `story.id`.
    case story(id: String, city: String?)
    /// A culture note (slang / saying / quote / person) — route to that city's
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
        case .culture:
            self = .culture(id: result.ref, city: result.city)
        case .tour:
            self = .tour(slug: result.slug ?? result.ref, city: result.city)
        }
    }
}

/// The shared selection/navigation observable the integrator hooks once at the
/// app root. Search and the city switcher *never* navigate directly — they call
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

    /// The last route requested — exposed so a host that prefers to *observe*
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
        switch route {
        case .city(let slug):
            selectedCity = slug
        case .place(_, let city),
             .story(_, let city),
             .culture(_, let city),
             .tour(_, let city):
            if let city, !city.isEmpty { selectedCity = city }
        }
        lastRoute = route
        onRoute?(route)
    }

    /// Convenience: route straight from a search hit.
    func route(_ result: SearchResult) {
        route(LoreRoute(result: result))
    }

    /// Switch the active city by slug (the city switcher's primary action).
    func switchCity(to slug: String) {
        route(.city(slug: slug))
    }
}
