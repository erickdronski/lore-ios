import CoreLocation
import Foundation
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
                    // Record verified purchases server-side. StoreKit already
                    // opens the gate on-device; this is what makes the purchase
                    // durable, visible on the web, and reconcilable. Failures
                    // are deliberately silent: access is never blocked on it,
                    // and the next refresh re-posts.
                    store.onVerifiedTransaction = { [weak auth] signedJWS in
                        guard let auth else { return false }
                        guard let token = await auth.validAccessToken() else { return false }
                        // A false result covers expected non-production writes
                        // such as TestFlight Sandbox. Transport failures retry
                        // naturally on the next entitlement refresh.
                        return (try? await LoreAPI.shared.syncApplePurchase(
                            signedTransaction: signedJWS,
                            accessToken: token
                        )) ?? false
                    }
                    store.start()
                }
                // Bind purchases to the signed-in account. StoreKit needs this
                // BEFORE the purchase sheet opens, so it tracks the session.
                .task(id: auth.session?.user.id) {
                    // Unwrapped explicitly: `id.flatMap(UUID.init)` resolves to
                    // String's Sequence flatMap (over Characters), not
                    // Optional's, and does not compile.
                    guard let userID = auth.session?.user.id else {
                        store.accountUUID = nil
                        await store.refreshEntitlements()
                        return
                    }
                    store.accountUUID = UUID(uuidString: userID)
                    await store.refreshEntitlements()
                }
                // App chrome is the app's words, Ink/Brass, never Amber
                // (Amber is reserved for the world: pins, outlines, beacon —
                // brand/DESIGN.md §4). brass700 is the AA-safe brass on Bone.
                .tint(LoreColor.brass700)
                .loreOnboarding(auth: auth, prefs: prefs)
        }
    }
}

/// The tab root: the five surfaces, the router hookup, and the global sheets
/// (search / city switcher / Meet-the-City / paywall / place card) the router
/// raises. Reads the shared stores from the environment `LoreApp` injected.
struct RootTabView: View {
    enum Tab: String, CaseIterable, Hashable, Identifiable {
        case map, scanner, tours, passport, profile

        var id: Self { self }

        var title: String {
            switch self {
            case .map: L10n.t("tab.map")
            case .scanner: L10n.t("tab.scanner")
            case .tours: L10n.t("tab.tours")
            case .passport: L10n.t("tab.passport")
            case .profile: L10n.t("tab.profile")
            }
        }

        var systemImage: String {
            switch self {
            case .map: "map"
            case .scanner: "camera.viewfinder"
            case .tours: "figure.walk"
            case .passport: "seal"
            case .profile: "person.crop.circle"
            }
        }

        var subtitle: String {
            switch self {
            case .map: "Discover what is around you"
            case .scanner: "Reveal stories in the world"
            case .tours: "Walk a city with purpose"
            case .passport: "Badges, visits, and journals"
            case .profile: "Membership and preferences"
            }
        }
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: Tab = .map
    /// iPad users can reclaim the full map/content canvas and restore the
    /// editorial rail from a small edge handle without rebuilding any tab.
    @State private var tabletColumnVisibility: NavigationSplitViewVisibility = .all

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
    /// Search and deep-link resolution is latest-wins. Without cancellation, a
    /// slow result from the previous city can arrive after a newer tap and open
    /// the wrong sheet over the traveler's current context.
    @State private var routeTask: Task<Void, Never>?
    /// A city whose "Meet {City}" culture surface is presented.
    @State private var meetCity: String?
    /// Whether the sign-in nudge is up (raised by a signed-out visit toggle).
    @State private var showSignIn = false
    #if DEBUG
    /// Presents the paywall for the App Store IAP review screenshot (LORE_SHOW=paywall).
    @State private var showScreenshotPaywall = false
    #endif

    var body: some View {
        appShell
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
        .loreDossierPresentation(item: $routedPlace) { routed in
            // Detents are owned by PlaceCardView: it rests at `.medium` and
            // promotes to `.large` when the dossier opens (including the
            // screenshot pipeline's autoDive stage).
            PlaceCardView(place: routed.place, onMeetCity: { routedPlace = nil; meetCity = $0 }, autoDive: routed.autoDive)
        }
        .sheet(item: $routedStory) { story in
            StorySheet(story: story)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $routedTour) { tour in
            TourSheet(tour: tour)
        }
        // Meet-the-City, the culture surface, raised from the map header, the
        // PlaceCard, or a culture search hit.
        .sheet(item: meetCityBinding) { route in
            CultureSheet(city: route.slug)
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
        .onDisappear {
            routeTask?.cancel()
            routeTask = nil
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

    /// Compact windows retain Lore's familiar bottom tabs. Regular-width iPad
    /// windows use an editorial sidebar, freeing the full height for maps,
    /// culture, tours, and the Passport wall. Stage Manager can move between
    /// the two naturally as a window crosses the system size-class boundary.
    @ViewBuilder
    private var appShell: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView(columnVisibility: $tabletColumnVisibility) {
                tabletSidebar
                    .navigationSplitViewColumnWidth(min: 236, ideal: 268, max: 310)
            } detail: {
                tabletTabView
                    .overlay(alignment: .leading) {
                        if tabletColumnVisibility == .detailOnly {
                            tabletSidebarRestoreButton
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .animation(LoreMotion.tap, value: tabletColumnVisibility)
        } else {
            compactTabView
        }
    }

    private var compactTabView: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                surface(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }

    /// Keep every visited surface's navigation and scroll state alive while
    /// the custom sidebar owns selection. The system tab bar is deliberately
    /// hidden in regular width so tablet users get one clear navigation model.
    private var tabletTabView: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                surface(for: tab)
                    .tag(tab)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var tabletSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LORE")
                        .font(LoreType.display(size: 30, weight: .bold))
                        .tracking(2.5)
                        .foregroundStyle(LoreColor.ink)
                    Text("Every place has a story.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.play(.chipTap)
                    withAnimation(LoreMotion.tap) { tabletColumnVisibility = .detailOnly }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LoreColor.ink600)
                        .frame(width: 34, height: 34)
                        .background(LoreColor.bone200, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide sidebar")
                .help("Hide sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            .padding(.horizontal, 22)
            .padding(.top, 30)
            .padding(.bottom, 22)

            Text("EXPLORE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(LoreColor.brass700)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(Tab.allCases) { tab in
                    tabletSidebarButton(tab)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 20)

            Button {
                showCitySwitcher = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LoreColor.brass700)
                        .frame(width: 34, height: 34)
                        .background(LoreColor.bone200, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXPLORING")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(LoreColor.ink600)
                        Text(cityLabel(router.selectedCity))
                            .font(LoreType.display(size: 16, weight: .semibold))
                            .foregroundStyle(LoreColor.ink)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LoreColor.ink600)
                }
                .padding(12)
                .background(LoreColor.bone, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(LoreColor.ink.opacity(0.08))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current city, \(cityLabel(router.selectedCity))")
            .accessibilityHint("Switch cities and manage places you are planning to visit.")
            .padding(12)
        }
        .background(LoreColor.bone100.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    /// A quiet edge tab, not a top-left floating button: it stays clear of the
    /// map's city picker and the navigation titles on content-heavy surfaces.
    private var tabletSidebarRestoreButton: some View {
        Button {
            Haptics.play(.chipTap)
            withAnimation(LoreMotion.tap) { tabletColumnVisibility = .all }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LoreColor.ink)
                .frame(width: 34, height: 52)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(LoreColor.brass700.opacity(0.3)))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 2, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
        .accessibilityLabel("Show sidebar")
        .help("Show sidebar")
        .keyboardShortcut("s", modifiers: [.command, .control])
        .zIndex(20)
    }

    private func tabletSidebarButton(_ tab: Tab) -> some View {
        Button {
            Haptics.play(.chipTap)
            withAnimation(LoreMotion.tap) { selection = tab }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(LoreType.display(size: 17, weight: .semibold))
                    Text(tab.subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .lineLimit(1)
                        .opacity(selection == tab ? 0.72 : 0.62)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selection == tab ? LoreColor.bone : LoreColor.ink)
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selection == tab ? LoreColor.ink : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    @ViewBuilder
    private func surface(for tab: Tab) -> some View {
        switch tab {
        case .map:
            MapScreen(
                city: router.selectedCity,
                prefs: prefs.prefs,
                onOpenSearch: { showSearch = true },
                onOpenCitySwitcher: { showCitySwitcher = true },
                onMeetCity: { meetCity = $0 },
                onNeedsSignIn: { showSignIn = true }
            )
        case .scanner:
            ScannerScreen(city: router.selectedCity, prefs: prefs.prefs, onMeetCity: { meetCity = $0 })
        case .tours:
            ToursScreen()
        case .passport:
            PassportView()
        case .profile:
            ProfileScreen()
        }
    }

    private func cityLabel(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
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
            routeTask?.cancel()
            routeTask = nil
            routeError = nil
            switch route {
            case .city:
                // `AppRouter` already updated `selectedCity`; jump to the map so
                // the switch is visible.
                selection = .map
            case .place(let id, _):
                routeTask = Task { await openPlace(id: id) }
            case .story(let id, _):
                routeTask = Task { await openStory(id: id) }
            case .culture(_, let cityScoped):
                meetCity = cityScoped ?? router.selectedCity
            case .tour(let slug, _):
                selection = .tours
                routeTask = Task { await openTour(slug: slug) }
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
        do {
            let places = try await LoreAPI.shared.places(city: router.selectedCity)
            try Task.checkCancellation()
            if let match = places.first(where: { $0.id == id }) {
                routedPlace = RoutedPlace(place: match)
            } else {
                routeError = "That place is no longer available in this city."
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            routeError = error.localizedDescription
        }
    }

    private func openStory(id: String) async {
        do {
            let stories = try await LoreAPI.shared.stories(city: router.selectedCity)
            try Task.checkCancellation()
            if let match = stories.first(where: { $0.id == id }) {
                routedStory = match
            } else {
                routeError = "That story is no longer available in this city."
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            routeError = error.localizedDescription
        }
    }

    private func openTour(slug: String) async {
        do {
            let tours = try await LoreAPI.shared.tours(city: router.selectedCity)
            try Task.checkCancellation()
            if let match = tours.first(where: { $0.slug == slug }) {
                routedTour = match
            } else {
                routeError = "That tour is no longer available in this city."
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            routeError = error.localizedDescription
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
