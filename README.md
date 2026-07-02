# lore-ios

The native Swift app for **Lore** — point at a building, learn its story.
SwiftUI, iOS 17+, zero external dependencies at P0: pure Apple frameworks +
`URLSession` against the Lore Supabase project's PostgREST surface.

This repo was scaffolded on a machine with **Command Line Tools only** (no
Xcode, no iOS SDK). Every Swift file is syntax-validated (`swiftc -parse`);
the first full build happens on a machine with Xcode via the bootstrap below.
There is no checked-in `.xcodeproj` — the project is generated from
`project.yml` by XcodeGen, so the project file never causes a merge conflict
and never drifts from the source tree.

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
   **J9DMDH4S58** and bundle id **`app.lore.lore`** are pre-set in
   `project.yml` (constants locked in `lore/docs/10-APPSTORE.md`); with the
   App ID registered per that doc, "Automatically manage signing" just works.
5. **Run.**
   - **Simulator:** Map, Tours, place cards, dives, and sign-in all work
     (they're plain network + SwiftUI).
   - **Scanner needs a real iPhone** — camera, compass heading, and the
     ARKit geo-tracking availability probe don't exist in the simulator.
     Plug in a device, trust it, select it as the run destination.

## What's real vs. stubbed (P0)

| Area | Status |
|---|---|
| Map tab | **Real** — MapKit map of `place_explore` rows, emoji-badged Amber pins (compound render per brand rules), tap → Layer-1 card sheet. MapKit is a P0 stand-in; the locked production stack is MapLibre GL Native + OpenFreeMap PMTiles (`docs/03` §2). |
| Place card → dive | **Real** — card renders `layer1` (hook, year, architect, style); dive dossier fetches `dive` (narrative, horizontal snap timeline with Amber nodes, links section with an Apple Maps deep-link). Dive rows are still being seeded — the empty state is honest about it. |
| Scanner tab | **Real, coarse mode** — AVCaptureSession preview + CLLocationManager GPS/true-heading, bearing-projected chips in-FOV and an off-screen edge rail ("Willis Tower ↖ 600 m"), exactly the web scanner's behavior and exactly rung 2 of the degraded-modes ladder (`docs/05` §5). Per the honesty contract it makes **no on-building claims**. |
| `GeoScoutingService` | **Stub with a real probe** — `ARGeoTrackingConfiguration.checkAvailability(at:)` answers "is there VPS-class coverage here" on-device today; the ARCore Geospatial `GARSession` integration is `TODO(P1)` in the file. |
| Tours tab | **Real** — `tour` + embedded `tour_stop` rows by city, stop-stepper detail with curator notes. (Tables live, seed content landing.) |
| Auth | **Real email sign-in** against GoTrue REST (`/auth/v1/token?grant_type=password`); session is in-memory only at P0. **Sign in with Apple button is present but stubbed** — native flow specced in `lore/docs/11-AUTH-SETUP.md` §B; it renders above email per guideline 4.8. |
| Profile tab | **Real when signed in** (`user_profile`: handle, trust tier, Insight points); Contributions (P2) and Lore+ (P3) rows are labeled stubs. |
| AR pipeline | **Not here yet.** ARKit + ARCore Geospatial + RealityKit (VPS pose, Streetscape Geometry, resolver, chunk store) is the P1 build, specced end-to-end in `lore/docs/05-AR-PIPELINE.md` + `03-ARCHITECTURE.md`. |
| `UIRequiredDeviceCapabilities` | **Deliberately commented out** in `project.yml` — `arkit` + `gps` are irreversible once shipped; they go in with the first ARCore build at P1 (`docs/10` §1). |

The Supabase URL + anon key are hardcoded in
`Sources/Lore/Networking/Config.swift`. That's intentional — the anon key is
the publishable client key (RLS-limited, read-only surfaces, no client write
policies exist); it's the same posture as `lore-web`. The service-role key
must never appear in this repo.

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
