import CoreLocation
import SwiftUI

/// Lore, every place has a story.
///
/// The composed P0 app. A `TabView` root, Map (the living Explorer, with the
/// Travel filter chips + near-me shelf + persona-weighted pins composed in),
/// Scanner (the v2 intelligence viewfinder), Tours, Passport (the reward wall),
/// and Profile, under a first-run Onboarding cover, with a global search entry
/// and city switcher in the map header. The AR pipeline proper (ARKit + ARCore
/// Geospatial + RealityKit) replaces the Scanner tab's internals at P1; the tab
/// structure and everything wired here survives that swap.
///
/// This file is the one composition seam: it owns the shared observables
/// (`AuthService`, `AppRouter`, `EntitlementStore`, `PrefsCoordinator`,
/// `TravelSession`), injects them into the environment, and installs
/// `router.onRoute` so search / city-switcher selections open the right surface.
/// No feature view imports the tab structure, they all take injected closures
/// or read the environment.
@main
struct LoreApp: App {
    /// The UIKit delegate adaptor, its only job is the APNs token callbacks
    /// (docs/16 §5). It owns the shared `PushService`, which we lift into the
    /// SwiftUI environment below.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Single auth instance for the whole app, every signed-in surface reads it
    /// from the environment.
    @State private var auth: AuthService
    /// The shared selection/navigation router search + the switcher route through.
    @State private var router = AppRouter()
    /// The single "is this user Lore+?" source of truth (docs/00 §7).
    @State private var entitlements = EntitlementStore()
    /// The StoreKit 2 client path, the on-device transaction engine and the
    /// offline entitlement read `EntitlementStore` unions in (docs/16 §1).
    @State private var store = StoreKitService()
    /// The one shared `user_prefs` load, persona weighting + hidden kinds.
    @State private var prefs = PrefsCoordinator()
    /// Owns the Travel stores (visits + filters) and the unlock bridge.
    @State private var travel: TravelSession

    init() {
        // Build one `AuthService` and wire the Travel stores' credentials
        // closure to read its *current* session lazily (the user can sign in
        // mid-session). `@State`'s backing is created once, here.
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _travel = State(initialValue: TravelSession(credentials: {
            guard let session = auth.session else { return nil }
            return (userID: session.user.id, accessToken: session.accessToken)
        }))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(auth)
                .environment(router)
                .environment(entitlements)
                .environment(store)
                .environment(appDelegate.push)
                .environment(prefs)
                .environment(travel)
                .environment(travel.visits)
                .environment(travel.filters)
                // Wire the StoreKit client path into the entitlement store and
                // start the Transaction.updates listener once, at launch. Both
                // are @MainActor app-lifetime singletons (docs/16 §1).
                .task {
                    entitlements.storeKit = store
                    store.start()
                }
                // App chrome is the app's words, Ink/Brass, never Amber
                // (Amber is reserved for the world: pins, outlines, beacon —
                // brand/DESIGN.md §4). brass700 is the AA-safe brass on Bone.
                .tint(LoreColor.brass700)
                // Lore's palette is a FIXED brand system (Ink/Bone/Brass/Amber),
                // not an adaptive light/dark theme: light surfaces (map, tours,
                // profile, cards) use dark text on Bone, dark surfaces (scanner,
                // dossier, paywall) set Ink explicitly. Pin the scheme to .light
                // so the device's Dark Mode never turns system chrome (nav-bar
                // titles, grouped-list cells) dark and makes the dark brand text
                // unreadable on the Bone surfaces (TestFlight feedback 2026-07-06:
                // "can't read Profile / the tiles"). A true adaptive dark theme
                // is a separate, larger design-system pass.
                .preferredColorScheme(.light)
                .loreOnboarding(auth: auth)
        }
    }
}

/// The tab root: the five surfaces, the router hookup, and the global sheets
/// (search / city switcher / Meet-the-City / paywall / place card) the router
/// raises. Reads the shared stores from the environment `LoreApp` injected.
struct RootTabView: View {
    enum Tab: Hashable {
        case map, scanner, tours, passport, profile
    }

    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PrefsCoordinator.self) private var prefs
    @Environment(TravelSession.self) private var travel

    @State private var selection: Tab = .map

    /// One-shot location source used only to snap the active city to the user's
    /// nearest city on launch (TestFlight feedback: "it says Chicago but I'm in
    /// Mount Laurel"). Shares CoreLocation permission with the near-me shelf.
    @State private var locator = NearMeLocationProvider()
    @State private var autoCityDone = false

    // Router-raised presentations.
    @State private var showSearch = false
    @State private var showCitySwitcher = false
    /// A place opened from search (the map's own pin taps present their own sheet).
    @State private var routedPlace: RoutedPlace?
    /// A city whose "Meet {City}" culture surface is presented.
    @State private var meetCity: String?
    /// Whether the sign-in nudge is up (raised by a signed-out visit toggle).
    @State private var showSignIn = false

    var body: some View {
        TabView(selection: $selection) {
            MapScreen(
                city: router.selectedCity,
                prefs: prefs.prefs,
                onOpenSearch: { showSearch = true },
                onOpenCitySwitcher: { showCitySwitcher = true },
                onMeetCity: { meetCity = $0 },
                onNeedsSignIn: { showSignIn = true }
            )
            .tabItem { Label(L10n.t("tab.map"), systemImage: "map") }
            .tag(Tab.map)

            ScannerScreen(city: router.selectedCity, prefs: prefs.prefs)
                .tabItem { Label(L10n.t("tab.scanner"), systemImage: "camera.viewfinder") }
                .tag(Tab.scanner)

            ToursScreen()
                .tabItem { Label(L10n.t("tab.tours"), systemImage: "figure.walk") }
                .tag(Tab.tours)

            PassportView()
                .tabItem { Label(L10n.t("tab.passport"), systemImage: "seal") }
                .tag(Tab.passport)

            ProfileScreen()
                .tabItem { Label(L10n.t("tab.profile"), systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        // Global search, resolves a `LoreRoute` and hands it to the router.
        .sheet(isPresented: $showSearch) {
            SearchView(router: router)
                .presentationDetents([.large])
        }
        // City switcher, writes `router.selectedCity`, which re-scopes the map.
        .sheet(isPresented: $showCitySwitcher) {
            CitySwitcherView(router: router)
                .presentationDetents([.medium, .large])
        }
        // A place opened from a search hit (map pin taps are self-contained).
        .sheet(item: $routedPlace) { routed in
            PlaceCardView(place: routed.place, onMeetCity: { meetCity = $0 })
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
        }
        // Meet-the-City, the culture surface, raised from the map header, the
        // PlaceCard, or a culture search hit.
        .sheet(item: meetCityBinding) { route in
            NavigationStack { CultureView(city: route.slug) }
                .presentationDetents([.large])
        }
        // The sign-in nudge (a signed-out visit toggle, per `VisitToggle`).
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.large])
        }
        .onAppear {
            installRouter()
            locator.start()
        }
        // Follow the user's location to the nearest city on launch, unless they
        // have chosen one. Resolves once, then leaves the city under user control.
        .onChange(of: locator.location) { _, newLocation in
            resolveNearestCity(newLocation)
        }
        // Widget taps + Live Activity taps arrive as `lore://` deep links.
        .onOpenURL { url in router.handleDeepLink(url) }
        // Restore a persisted sign-in on launch (Keychain + token refresh) so
        // returning users are not asked to sign in again.
        .task { await auth.restore() }
        // Session changes ripple to every dependent store.
        .task(id: auth.session?.accessToken) { await syncSession() }
    }

    /// Resolve the nearest live city to a fresh location fix and hand it to the
    /// router (which ignores it if the user already picked a city). Runs at most
    /// once per launch.
    private func resolveNearestCity(_ location: CLLocation?) {
        guard let location, !autoCityDone, !router.userDidChooseCity else { return }
        autoCityDone = true
        Task {
            guard let cities = try? await LoreAPI.shared.cities(), !cities.isEmpty else {
                autoCityDone = false
                return
            }
            let nearest = cities.min {
                location.distance(from: $0.location) < location.distance(from: $1.location)
            }
            if let nearest {
                router.autoSelectCity(nearest.slug)
            }
        }
    }

    /// Present "Meet {City}" as a sheet keyed by slug.
    private var meetCityBinding: Binding<MeetCityRoute?> {
        Binding(
            get: { meetCity.map(MeetCityRoute.init) },
            set: { meetCity = $0?.slug }
        )
    }

    // MARK: - Router

    /// Wire the shared router once: every route search / the switcher emit lands
    /// here, and we open the matching surface. This is the single switch the
    /// AppRouter doc calls for, no feature view navigates on its own.
    private func installRouter() {
        router.onRoute = { route in
            switch route {
            case .city:
                // `AppRouter` already updated `selectedCity`; jump to the map so
                // the switch is visible.
                selection = .map
            case .place(let id, _):
                Task { await openPlace(id: id) }
            case .story:
                // No standalone story screen at P0, route to the map, where the
                // meanwhile-nearby markers live (scanner) / pins do. `AppRouter`
                // already followed the hit's city into `selectedCity`.
                selection = .map
            case .culture(_, let cityScoped):
                meetCity = cityScoped ?? router.selectedCity
            case .tour:
                // Tours key on slug; the Tours tab lists them. Deep-linking to a
                // specific tour detail is a P1 nicety.
                selection = .tours
            }
        }
    }

    /// Resolve a place id to a full `Place` (search hits carry only the id) and
    /// present its card. Best-effort: a miss just no-ops.
    private func openPlace(id: String) async {
        selection = .map
        // Try the city the router is scoped to first (the common case), then a
        // broad fetch is unnecessary, `place_explore` is city-filtered, and the
        // router already followed a cross-city hit's `city` into `selectedCity`.
        let places = (try? await LoreAPI.shared.places(city: router.selectedCity)) ?? []
        if let match = places.first(where: { $0.id == id }) {
            routedPlace = RoutedPlace(place: match)
        }
    }

    // MARK: - Session sync

    /// Fan a session change out to the dependent stores: entitlements (Lore+),
    /// prefs (persona lens), and the Travel visit set. Also folds a signed-out
    /// user's stashed filter changes back once they sign in.
    private func syncSession() async {
        let token = auth.session?.accessToken
        if token == nil {
            entitlements.clear()
            prefs.reset()
            travel.visits.reset()
        }
        await entitlements.refresh(accessToken: token)
        await prefs.load(accessToken: token, force: true)
        await travel.bootstrap(prefs: prefs.prefs)

        // Flush a signed-out user's pending hidden-kinds once we have creds.
        if let session = auth.session {
            try? await MapFilterStore.flushPending(
                userID: session.user.id,
                accessToken: session.accessToken
            )
        }
    }
}

// MARK: - Sheet item wrappers

/// `Identifiable` wrapper so a routed place can drive `.sheet(item:)`.
private struct RoutedPlace: Identifiable {
    let place: Place
    var id: String { place.id }
}

/// `Identifiable` wrapper so a city slug can drive the Meet-the-City sheet.
private struct MeetCityRoute: Identifiable {
    let slug: String
    var id: String { slug }
}
