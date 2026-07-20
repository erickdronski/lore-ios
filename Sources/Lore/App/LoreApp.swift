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
    /// The free-tier deep-dive allowance (3/day, docs/00 §7). Consulted only
    /// for non-members; Lore+ bypasses it. One instance for the whole app.
    @State private var diveMeter = DiveMeter()
    /// Owns the Travel stores (visits + filters) and the unlock bridge.
    @State private var travel: TravelSession
    /// Offline city packs: "Download this city" state + orchestration (Lore+).
    @State private var packs = CityPackStore()

    init() {
        // Screenshot pipeline only (DEBUG builds): fast-forward past first-run
        // onboarding before the gate reads its flag. Compiled out of Release.
        #if DEBUG
        ScreenshotSupport.applyIfNeeded()
        #endif

        // Build one `AuthService` and wire the Travel stores' credentials
        // closure to read its *current* session lazily (the user can sign in
        // mid-session). `@State`'s backing is created once, here.
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _travel = State(initialValue: TravelSession(credentials: {
            guard let session = auth.session, !session.isExpired else { return nil }
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
                .environment(diveMeter)
                .environment(travel)
                .environment(travel.visits)
                .environment(travel.filters)
                .environment(packs)
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
    #if DEBUG
    // Read only by the DEBUG-only paywall screenshot stage (LORE_SHOW=paywall).
    @Environment(StoreKitService.self) private var store
    #endif
    @Environment(PrefsCoordinator.self) private var prefs
    /// Day/night state (solar auto + manual pin) — owned here so the color
    /// scheme, the map, and any future night surface read one truth.
    @State private var dayNight = DayNightStore()
    @Environment(TravelSession.self) private var travel
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .map

    /// One-shot location source used only to snap the active city to the user's
    /// nearest city on launch (TestFlight feedback: "it says Chicago but I'm in
    /// Mount Laurel"). Shares CoreLocation permission with the near-me shelf.
    @State private var locator = NearMeLocationProvider()
    @State private var autoCityDone = false
    /// Identity whose user-scoped stores are currently hydrated.
    @State private var syncedUserID: String?

    // Router-raised presentations.
    @State private var showSearch = false
    @State private var showCitySwitcher = false
    /// A place opened from search (the map's own pin taps present their own sheet).
    @State private var routedPlace: RoutedPlace?
    /// Story/tour opened directly from global search.
    @State private var routedStory: Story?
    @State private var routedTour: Tour?
    @State private var routeError: String?
    /// A city whose "Meet {City}" culture surface is presented.
    @State private var meetCity: String?
    /// Whether the sign-in nudge is up (raised by a signed-out visit toggle).
    @State private var showSignIn = false
    #if DEBUG
    /// Presents the paywall for the App Store IAP review screenshot (LORE_SHOW=paywall).
    @State private var showScreenshotPaywall = false
    #endif

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

            ScannerScreen(city: router.selectedCity, prefs: prefs.prefs, onMeetCity: { meetCity = $0 })
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
        // The badge-earned reward moment, app-wide: a visit logged on ANY tab
        // feeds VisitStore.onUnlocks -> TravelSession.pendingUnlocks; this raises
        // the same UnlockCelebration the Passport uses, over everything, so a
        // freshly-earned badge actually celebrates instead of landing silently.
        .overlay {
            if !travel.pendingUnlocks.isEmpty {
                UnlockCelebration(unlocked: travel.pendingUnlocks) {
                    withAnimation(LoreMotion.tap) { travel.clearUnlocks() }
                }
                .zIndex(50)
                .transition(.opacity)
            }
        }
        .animation(LoreMotion.unfurl, value: travel.pendingUnlocks.count)
        // The day/night truth, readable by every tab below this point.
        .environment(dayNight)
        // Lore's palette is fixed rather than a device-driven adaptive theme.
        // Keep Bone tabs in light system chrome, while the full-screen Scanner
        // and Passport need light status-bar glyphs over camera/Ink surfaces —
        // and the Map goes dark after sundown (or a pinned night), the night
        // layer's visual register.
        .preferredColorScheme(
            selection == .scanner || selection == .passport
                || (selection == .map && dayNight.isNight)
                ? .dark : .light
        )
        // Feed location fixes into the solar calculation so "night" means the
        // sun is actually down where the user is standing.
        .onChange(of: locator.location) { _, newValue in
            dayNight.updateLocation(newValue)
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
            PlaceCardView(place: routed.place, onMeetCity: { routedPlace = nil; meetCity = $0 }, autoDive: routed.autoDive)
                // The screenshot "dive" stage wants the full dossier, so pin the
                // sheet to `.large`; normal presentations keep the medium grip.
                .presentationDetents(routed.autoDive ? [.large] : [.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
        }
        .sheet(item: $routedStory) { story in
            StorySheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $routedTour) { tour in
            NavigationStack { TourDetailView(tour: tour) }
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
        #if DEBUG
        // App Store IAP review-screenshot capture only (LORE_SHOW=paywall).
        .sheet(isPresented: $showScreenshotPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth)
                .presentationDetents([.large])
        }
        #endif
        .alert("Couldn't open that result", isPresented: routeErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(routeError ?? "Try again in a moment.")
        }
        .onAppear {
            installRouter()
            // This view exists beneath onboarding. Observe an existing grant,
            // but let onboarding explain location before any system prompt.
            locator.start(requestPermission: false)
            #if DEBUG
            presentScreenshotStageIfNeeded()
            #endif
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
        // iOS suspends timers in the background. Refresh an expired/near-expiry
        // Supabase token as soon as the app is usable again.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await auth.refreshIfNeeded() }
        }
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
            case .story(let id, _):
                Task { await openStory(id: id) }
            case .culture(_, let cityScoped):
                meetCity = cityScoped ?? router.selectedCity
            case .tour(let slug, _):
                selection = .tours
                Task { await openTour(slug: slug) }
            }
        }
    }

    private var routeErrorBinding: Binding<Bool> {
        Binding(
            get: { routeError != nil },
            set: { if !$0 { routeError = nil } }
        )
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
        } else {
            routeError = "That place isn't available right now."
        }
    }

    private func openStory(id: String) async {
        let stories = (try? await LoreAPI.shared.stories(city: router.selectedCity)) ?? []
        if let match = stories.first(where: { $0.id == id }) {
            routedStory = match
        } else {
            routeError = "That story isn't available right now."
        }
    }

    private func openTour(slug: String) async {
        let tours = (try? await LoreAPI.shared.tours(city: router.selectedCity)) ?? []
        if let match = tours.first(where: { $0.slug == slug }) {
            routedTour = match
        } else {
            routeError = "That tour isn't available right now."
        }
    }

    #if DEBUG
    // MARK: - Screenshot staging (DEBUG only, compiled out of Release)

    /// Present a "deep" surface for the App Store screenshot capturer when it
    /// launches with a `LORE_SHOW` stage. Tab surfaces the capturer reaches on
    /// its own; the dossier and Meet-the-City are presented state, so we open
    /// them here deterministically rather than tapping a map pin. Fetches the
    /// pilot city directly (independent of the map's resolved city) and polls
    /// until the network returns, so a cold launch still lands the shot.
    private func presentScreenshotStageIfNeeded() {
        guard ScreenshotSupport.isActive, let stage = ScreenshotSupport.stage else { return }
        switch stage {
        case "dive":
            selection = .map
            Task {
                for _ in 0..<24 {
                    let places = (try? await LoreAPI.shared.places(city: "chicago")) ?? []
                    if let match = places.first(where: { $0.slug == ScreenshotSupport.diveSlug })
                        ?? places.first(where: { $0.layer1?.hook != nil }) {
                        routedPlace = RoutedPlace(place: match, autoDive: true)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        case "culture":
            // City comes from LORE_CARD_CITY so captures can stage any city's
            // themed Meet-the-City surface (default: the Chicago pilot).
            selection = .map
            meetCity = ScreenshotSupport.cardCity
        case "paywall":
            showScreenshotPaywall = true
        case "card":
            // The layer-1 place card (no auto-dive): used to verify/capture the
            // card surface itself — visit toggle, your-lore, traveler lore,
            // teaser, actions. City/slug come from LORE_CARD_CITY/LORE_CARD_SLUG
            // (default: the Chicago dive landmark).
            selection = .map
            Task {
                for _ in 0..<24 {
                    let places = (try? await LoreAPI.shared.places(city: ScreenshotSupport.cardCity)) ?? []
                    if let match = places.first(where: { $0.slug == ScreenshotSupport.cardSlug })
                        ?? places.first(where: { $0.layer1?.hook != nil }) {
                        routedPlace = RoutedPlace(place: match, autoDive: false)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        default:
            break
        }
    }
    #endif

    // MARK: - Session sync

    /// Fan a session change out to the dependent stores: entitlements (Lore+),
    /// prefs (persona lens), and the Travel visit set. Also folds a signed-out
    /// user's stashed filter changes back once they sign in.
    private func syncSession() async {
        let token = await auth.validAccessToken()
        let userID = auth.session?.user.id

        if userID != syncedUserID {
            travel.visits.reset()
            travel.clearUnlocks()
            syncedUserID = userID
        }

        if token == nil {
            entitlements.clear()
            prefs.reset()
        }

        // Replay choices made before account creation before hydrating the
        // session stores, so the first signed-in render reflects those choices.
        if let userID, let token {
            try? await OnboardingPrefsWriter.flushPending(
                userID: userID,
                accessToken: token
            )
            try? await MapFilterStore.flushPending(
                userID: userID,
                accessToken: token
            )
        }

        await entitlements.refresh(accessToken: token)
        await prefs.load(accessToken: token, force: true)
        await travel.bootstrap(prefs: prefs.prefs)
    }
}

// MARK: - Sheet item wrappers

/// `Identifiable` wrapper so a routed place can drive `.sheet(item:)`.
private struct RoutedPlace: Identifiable {
    let place: Place
    /// Open straight to the dossier (screenshot pipeline only).
    var autoDive: Bool = false
    var id: String { place.id }
}

/// `Identifiable` wrapper so a city slug can drive the Meet-the-City sheet.
private struct MeetCityRoute: Identifiable {
    let slug: String
    var id: String { slug }
}
