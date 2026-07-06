# lore-ios

The native Swift app for **Lore** — point at a building, learn its story.
SwiftUI, iOS 17+, zero **third-party** dependencies at P0: pure Apple frameworks
(now including StoreKit 2, AuthenticationServices, WidgetKit, ActivityKit, and
UserNotifications) + `URLSession` against the Lore Supabase project's PostgREST
surface. The first third-party SDK (RevenueCat) lands deliberately at P3.

This repo is built on a machine with **Command Line Tools only** (no Xcode, no
iOS SDK). Every Swift file is syntax-validated (`swiftc -parse` — parse-only;
the whole `Sources` tree is clean). Imports and full types (`SwiftUI`,
`MapKit`, `UIKit`) only resolve with the iOS SDK, so the first real type-check
+ build happens on a machine with Xcode via the bootstrap below. There is no
checked-in `.xcodeproj` — the project is generated from `project.yml` by
XcodeGen, so the project file never causes a merge conflict and never drifts
from the source tree.

**Composition seam:** `Sources/Lore/App/LoreApp.swift` is the single wiring
point. It owns the shared observables (`AuthService`, `AppRouter`,
`EntitlementStore`, `StoreKitService`, `PrefsCoordinator`, `TravelSession`,
plus the `PushService` behind the `AppDelegate` adaptor), injects them into the
environment, presents the first-run Onboarding cover, installs
`AppRouter.onRoute` so global search + the city switcher open the right surface,
and handles `lore://` deep links (widget / Live Activity taps) via `.onOpenURL`.
Every feature view takes injected closures or reads the environment — none
import the tab structure.

**Apple toolkits (docs/16-APPLE-TOOLKITS.md):** the client paths for StoreKit 2,
native Sign in with Apple, WidgetKit, ActivityKit (tour Live Activity), and push
registration are wired here — real code, with the portal-gated bits (entitlements,
App Group, APNs key) commented in `project.yml` and the server-side bits (RevenueCat
reconcile, Apple provider config, push sender) left as documented TODOs. See
"[Apple toolkits — real vs. Xcode-gated](#apple-toolkits--real-vs-xcode-gated)".

**Targets:** the app (`Lore`) plus a **`LoreWidget`** app-extension that ships the
home-screen widget and the tour Live Activity. Cross-target types live in
`Sources/Shared` (compiled into both): the App-Group snapshot model and the
`TourActivityAttributes`.

## Bootstrap (first machine with Xcode)

1. **Install Xcode** from the Mac App Store (≥ 15.x for the iOS 17 SDK).
   Launch it once so it installs its components.
2. **Point the toolchain at Xcode** (the machine that generated this repo has
   `xcode-select` aimed at Command Line Tools):

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

3. **Install XcodeGen and generate the project:**

   ```sh
   brew install xcodegen
   cd lore-ios
   xcodegen generate
   open Lore.xcodeproj
   ```

   Re-run `xcodegen generate` any time `project.yml` changes or files are
   added/removed — never edit the `.xcodeproj` by hand.
4. **Signing:** Xcode → target `Lore` → Signing & Capabilities. Team
   **J9DMDH4S58** and bundle id **`com.erickdronski.lore`** are pre-set in
   `project.yml` (constants locked in `lore/docs/10-APPSTORE.md`); with the
   App ID registered per that doc, "Automatically manage signing" just works.
   The **`LoreWidget`** extension (`com.erickdronski.lore.LoreWidget`) signs the same
   way. Before the StoreKit / Sign-in-with-Apple / Push / App-Group paths run on
   a signed build, enable those **portal-gated capabilities** — see
   "[Apple toolkits — Portal-gated](#portal-gated-needs-the-apple-developer-portal--entitlements)"
   and the commented block in `project.yml`.
5. **Run.**
   - **Simulator:** Onboarding, Map (pins + filter chips + near-me shelf +
     city switcher + search), Tours, Passport, place cards, dives, Meet-the-City,
     and sign-in all work (they're plain network + SwiftUI). The near-me shelf
     needs a simulated location (Features → Location).
   - **Scanner needs a real iPhone** — camera, compass heading, and the
     ARKit geo-tracking availability probe don't exist in the simulator.
     Plug in a device, trust it, select it as the run destination.

## Feature map — what's real vs. stubbed (P0)

The app is a five-tab root (Map · Scanner · Tours · Passport · Profile) under a
first-run Onboarding cover, with a global search entry and city switcher in the
map header.

| Area | Status |
|---|---|
| **Onboarding** | **Real** — first-run full-screen cover (arrival → interests/persona → location → notifications → finish). Two-key gate (`UserDefaults` flag + `user_prefs.onboarded`); the finish-write upserts `user_prefs`, best-effort (never blocks a first-timer), stashed for a post-sign-in flush when signed out. Skippable from any step → broad traveler default. |
| **Map tab** | **Real, composed** — MapKit map of `place_explore` rows, emoji-badged Amber pins (compound render per brand rules), tap → Layer-1 card sheet. Now composes: the **Travel filter chips** (`place.kind` toggles → `hidden_kinds`), the **near-me shelf** ("Around you right now", live distance re-ranking, inline visit toggles), **persona-weighted pins** (`MapRelevance` dims non-matching pins, never removes them; visited pins carry a Brass seal), and a **header** with the city switcher, global search, and Meet-the-City. MapKit is the P0 stand-in; production is MapLibre GL Native + OpenFreeMap PMTiles (`docs/03` §2). |
| **City switcher + search** | **Real** — the switcher lists `city` (live, US-then-International), routes through the shared `AppRouter` to re-scope the map (fly-to + refetch). Global search hits the `search_lore` RPC (debounced, kind-grouped); a tap resolves a `LoreRoute` and the one router switch in `LoreApp` opens the matching surface (place card / Meet-the-City / map / Tours). |
| **Place card → dive** | **Real** — card renders `layer1` (hook, year, architect, style), a **Meet-this-city** entry, and the dive affordance; dive dossier fetches `dive` (narrative, horizontal snap timeline with Amber nodes, links + Apple Maps deep-link). Dive rows are still seeding — the empty state is honest. |
| **Meet-the-City (Culture)** | **Real** — the `city_culture` surface: rotating quote, Famous Faces row (Wikipedia portraits), Local Lingo + Sayings flip cards, person bio sheets. Reached from the map header, the place card, or a culture search hit. |
| **Passport tab** | **Real** — `achievement` catalog joined with the user's `user_achievement` rows, grouped by category with tier medallions and an Insight tally. A logged visit runs `recompute_achievements`; newly-unlocked badges raise the `UnlockCelebration` overlay. Signed-out shows the catalog (reading is never gated). |
| **Travel / visits** | **Real** — `VisitToggle` logs `POST /visit` → `recompute_achievements`, optimistic with rollback; `VisitStore` holds the visited set; unlocks bridge to the Passport celebration via `TravelSession`. Signed-out marking nudges sign-in rather than dead-ending. |
| **Scanner tab** | **Real, coarse mode (v2 intelligence)** — AVCaptureSession preview + CLLocationManager GPS/true-heading; persona-weighted ranking, honest confidence tiers (locked pin / bearing chip / directional cluster), meanwhile-nearby story markers, disambiguation stacks, and the §3.2 audio auto-offer. City- and persona-aware (reads the shared `AppRouter.selectedCity` + `PrefsCoordinator.prefs`). Makes **no on-building claims** per the honesty contract (`docs/12`, `docs/05` §5 rung 2). |
| `GeoScoutingService` | **Stub with a real probe** — `ARGeoTrackingConfiguration.checkAvailability(at:)` answers "is there VPS-class coverage here" on-device today; the ARCore Geospatial `GARSession` integration is `TODO(P1)`. |
| **Tours tab** | **Real** — `tour` + embedded `tour_stop` rows by city, stop-stepper detail with curator notes. (Tables live, seed content landing.) |
| **Premium (Lore+)** | **StoreKit 2 wired** — `EntitlementStore` is the single "is this user Lore+?" source; `isPlus` now **unions** the server row (`entitlements.status ∈ {active, trialing}`) with the on-device `StoreKitService` (`Transaction.currentEntitlements`), the offline belt-and-suspenders (`docs/16` §1). `PaywallView` runs a **real StoreKit 2 purchase** (`Product.products` / `purchase()` / `AppStore.sync()`), localized prices, and a trial CTA that branches on real intro-offer eligibility. Products `lore_plus_monthly_4_99` / `lore_plus_annual_29_99`; test with `StoreKit/Lore.storekit`. RevenueCat remains the planned server-side truth at P3 (reconcile TODOs in `StoreKitService`/`PaywallView`). |
| **Auth** | **Real email sign-in** against GoTrue REST (`/auth/v1/token?grant_type=password`); session in-memory only at P0. Session changes fan out (via `LoreApp`) to entitlements, prefs, and the visit set. **Sign in with Apple is now a real native flow** — `AppleSignInCoordinator` runs `ASAuthorizationController` with a hashed nonce; `AuthService.signInWithApple` exchanges the identity token at `/auth/v1/token?grant_type=id_token` (`docs/11` §B.2, `docs/16` §2). Renders above email per guideline 4.8. Server prereq (bundle id in the Supabase Apple provider) is the same the web path already stood up; first-auth name/email are carried through for the profile write (TODO). |
| **Profile tab** | **Real when signed in** (`user_profile`: handle, trust tier, Insight points); Contributions (P2) and Lore+ (P3) rows are labeled stubs. |
| **Widget (`LoreWidget`)** | **Real, second target** — a WidgetKit extension with the "Nearby Lore" widget (small "daily lore" + medium "around you", `TimelineProvider`, Amber-pin brand styling). Reads a `LoreWidgetSnapshot` the app writes to a shared App Group after each near-me refresh (`WidgetPublisher`); falls back to a brand sample when the group isn't provisioned. Taps deep-link `lore://place/{id}`. **App Group is portal-gated** — commented in `project.yml`. |
| **Live Activity (tour)** | **Real** — `TourActivityAttributes` (shared type) + a Lock-Screen view and Dynamic Island (compact/expanded/minimal) in the widget extension; the app's `TourLiveActivityController` starts/updates/ends it from `TourDetailView` (a "Start walking tour" control; stop changes push progress). `NSSupportsLiveActivities` is set (not portal-gated). On-device driven — no push token (`docs/16` §8). Live distance from Core Location is a TODO. |
| **Push (APNs)** | **Client scaffold** — `PushService` (UNUserNotificationCenter authorization, `registerForRemoteNotifications`, delegate for foreground/tap) + `AppDelegate` (`@UIApplicationDelegateAdaptor`) for the APNs token callbacks. Onboarding's "Turn on nudges" now registers for remote too. `UIBackgroundModes: remote-notification` is set; the **Push capability + `aps-environment` entitlement are portal-gated** (commented in `project.yml`) and the **server sender is a TODO** (`docs/16` §5). |
| **AR pipeline** | **Not here yet.** ARKit + ARCore Geospatial + RealityKit (VPS pose, Streetscape Geometry, resolver, chunk store) is the P1 build (`docs/05` + `docs/03`). |
| `UIRequiredDeviceCapabilities` | **Deliberately commented out** in `project.yml` — `arkit` + `gps` are irreversible once shipped; they go in with the first ARCore build at P1 (`docs/10` §1). |

## Apple toolkits — real vs. Xcode-gated

The client paths from `docs/16-APPLE-TOOLKITS.md`'s "do-these-first" set are
implemented against pure Apple frameworks and **parse clean** (`swiftc -parse`,
whole tree). What can't be done on a Command-Line-Tools-only machine (or without
the Apple Developer portal) is deliberately isolated and labeled — no assumed
entitlements, no invented server pieces.

### Real, in-repo, parses clean

| Toolkit | What's wired |
|---|---|
| **StoreKit 2** | `StoreKitService` — `Product.products`, `product.purchase()`, `Transaction.currentEntitlements`, a `Transaction.updates` listener, `AppStore.sync()` restore, intro-offer eligibility. `EntitlementStore.isPlus` unions StoreKit's on-device answer with the server row. `PaywallView` drives it with localized prices + an eligibility-aware trial CTA. `StoreKit/Lore.storekit` for simulator testing. |
| **Sign in with Apple** | `AppleSignInCoordinator` (`ASAuthorizationController` + SHA-256 nonce + `ASAuthorizationAppleIDButton`) → `AuthService.signInWithApple` exchanges the identity token at GoTrue `grant_type=id_token`. |
| **WidgetKit** | `LoreWidget` extension target — `NearbyLoreWidget` (`TimelineProvider`, small + medium), App-Group snapshot contract (`Sources/Shared`), `lore://` deep links, `WidgetPublisher` on the app side. |
| **ActivityKit** | `TourActivityAttributes` (shared) + `TourLiveActivityWidget` (Lock Screen + Dynamic Island) + `TourLiveActivityController` started from `TourDetailView`. `NSSupportsLiveActivities` set. |
| **Push (client half)** | `PushService` + `AppDelegate` adaptor; UNUserNotificationCenter authorization, remote registration, token capture, foreground/tap delegate. `UIBackgroundModes: remote-notification` set. |

### Xcode-gated (needs the machine with Xcode)

- **Generate the project + build/type-check:** `xcodegen generate` then build in
  Xcode. `swiftc -parse` here is syntax-only — `import SwiftUI`/`StoreKit`/
  `ActivityKit`/`WidgetKit` and full type resolution need the iOS SDK.
- **StoreKit configuration in the scheme:** wire `StoreKit/Lore.storekit` into
  the Run scheme (Xcode-only) to exercise purchase/trial/restore in the
  simulator. See `StoreKit/README.md`.
- **Widget/Live-Activity on device:** Live Activities and the Dynamic Island
  need a real device (or the widget in the simulator); the extension target is
  built by Xcode from the `project.yml` spec.

### Portal-gated (needs the Apple Developer portal + entitlements)

All left **commented** in `project.yml` under the app target's "Capabilities
that REQUIRE the Apple Developer portal" note — none assumed:

- **Sign in with Apple entitlement** (`com.apple.developer.applesignin`) on the
  App ID; plus the bundle id in the Supabase Apple provider's Client IDs (the
  web OAuth path already stood up the shared `.p8`/Services ID, so no new
  Supabase console work — `docs/16` §2).
- **Push capability + `aps-environment` entitlement** on the App ID, and an
  APNs token-auth `.p8` key. The **server sender** (a Supabase Edge Function
  signing the APNs JWT) is a documented TODO (`docs/16` §5).
- **App Group `group.com.erickdronski.lore`** on *both* the app and widget targets — the
  widget↔app snapshot hand-off no-ops safely until it exists.
- **Paid Apps agreement + the two IAP products** in App Store Connect, and the
  **RevenueCat project** that becomes the server-side entitlement truth at P3
  (`docs/16` §1; reconcile TODOs already in the StoreKit code).

## Supabase surfaces used (`Sources/Lore/Networking/LoreAPI.swift`)

Base `https://uiuwzymvyrgfyiugqlkp.supabase.co/rest/v1/`, every request carrying
the anon `apikey`; authed reads/writes add the user's bearer token so RLS
resolves `auth.uid()`.

**Anonymous reads:** `city` (switcher roster), `place_explore` (map/scanner
pins, city-filtered), `dive` (dossier), `story` (meanwhile-nearby), `city_culture`
(Meet-the-City), `tour` + embedded `tour_stop`, `achievement` (Passport catalog),
`fact` (provenance). **RPC:** `search_lore` (global search).

**Authed reads:** `user_profile`, `user_prefs` (persona/interests/hidden_kinds —
loaded once by `PrefsCoordinator`), `user_achievement`, `entitlements` (Lore+).
**Authed writes / RPC:** `user_prefs` upsert (onboarding + filter changes),
`visit` insert (been-here), `recompute_achievements` RPC (settles badges).
**External:** Wikipedia REST `page/summary/{title}` for Culture portraits.

The Supabase URL + anon key are hardcoded in `Config.swift` — intentional; the
anon key is the publishable client key (RLS-limited, no client write policies
exist), the same posture as `lore-web`. The service-role key must never appear
in this repo.

## Sibling repos

| Repo | Role |
|---|---|
| `lore` | The brain: decision docs (`docs/00`–`11`), brand system + tokens, Supabase schema. **Docs win conflicts** — change the decision doc first, then propagate here. |
| `lore-web` | Next.js web app (marketing, explore map, web scanner, admin). This app's Scanner is the native twin of the web scanner; `Models/` mirrors `lore-web/lib/types.ts`. |
| `lore-ios` | This repo — the native client, and the only place the real AR pipeline can exist. |

## Week 1 on the new machine: the VPS spike

Before building anything else on this scaffold, run the **ARCore Geospatial
spike** — it's the riskiest assumption in the whole plan and nothing
de-risks it but a phone outdoors:

1. Bootstrap above, confirm the coarse scanner runs on device.
2. Add the ARCore SDK (`ARCore/Geospatial`, pin ≥ 1.45 — packaging is open
   question 1 in `docs/05`), create a `GARSession` behind
   `GeoScoutingService`, feed it `ARFrame`s.
3. Stand on the Riverwalk / in the Loop and measure: time-to-localize
   (target p50 < 3 s), `horizontalAccuracy` (~1 m claim), and
   `orientationYawAccuracy` (1–2° claim) — those two numbers are the entire
   basis of the far-field raycast doctrine.
4. Log `checkVPSAvailability` across the pilot zone while you're out there
   (`docs/05` open question 2 — Riverwalk lower level, Millennium Park,
   Museum Campus).

If the spike holds, P1 proceeds on spec. If it doesn't, the degraded-modes
ladder is the product until it does — which is exactly what this scaffold
already ships.
