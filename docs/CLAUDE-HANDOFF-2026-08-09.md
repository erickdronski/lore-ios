# Claude Handoff - Lore iOS - 2026-08-09

## Scope

Lore only. Do not mix Nalee, Tapt, Scout, or other portfolio projects into this takeover.

## Branch

- Repo: `/Users/dron/Projects/lore-ios`
- Branch: `codex/lore-next-level-20260809`
- Claude takeover backup: this branch and `/Users/dron/Projects/lore` were
  checked clean and pushed on August 9, 2026. The latest verified native
  feature head before this docs-only handoff update was
  `c31bc874c3cdee287be223edd648fede8105e272` (`Use live origin for generated walks`).
- Current branch head: verify with `git rev-parse HEAD`; this file is updated on
  the branch as the takeover log evolves, so the final handoff commit will be a
  docs-only commit above the feature state listed here.
- Saved-place continuation started from handoff-only head
  `a411de655602828dc0f101fd6ed76531f99e7c0e`.
- Last feature head before the saved-place continuation:
  `d729cef21865737f5ee52c5dcc6f362689222731` (`Promote richer city field briefs`)
- GitHub PR: `https://github.com/erickdronski/lore-ios/pull/40`
- Base: `origin/main` at `466fd05` (`Journal: per-photo delete, remove-memory, server-enforced 12-photo cap`)

## What Changed In This Branch

1. Meet City now synthesizes a first-screen `CityFieldBrief` from already-loaded rich city rows:
   - watch / video links
   - local legends
   - first-timer mistakes
   - neighborhood decoders
   - photo prompts
   - seasonal hooks
   - It requires at least three eligible rows and does not invent content.

2. Meet City renders a new `CityFieldBriefCard` above the deeper shelves:
   - fast traveler context
   - responsive accessibility layout
   - optional source-backed external action from the row's existing URL
   - the brief now promotes hashtag/search and seasonal timing rows too, and
     uses a compact grid so seven local-context chips do not squeeze into one
     phone-width row

3. Tour stops can now open the full Lore place dossier:
   - stop card button: `Open full dossier`
   - opens `PlaceCardView` for the exact stop place
   - keeps the existing `Meet this city` route working from inside the dossier

4. Added focused Swift Testing coverage for:
   - field brief synthesis from rich local-expert rows
   - hidden field brief when there is not enough real content

5. Place cards now use the server-derived `place.teaser` fallback instead of
   only `layer1.hook`, so places with a published dive excerpt but no curated
   Layer-1 hook still feel written and useful.

6. The Layer-1 story teaser now has an explicit `Read full story` action that
   opens the full dossier. This fixes the visual dead end where truncated teaser
   text showed ellipses but did not clearly explain where to continue.

7. Scanner narration now uses the same server-derived `place.teaser` fallback
   as the place dossier, so the AR scanner speaks the best real published line
   available instead of dropping to a generic hook when Layer-1 is sparse.

8. Scanner audio offers now distinguish studio narration from generated scanner
   narration. When the locked scan has a dossier with `audio_url`, Lore+ users
   play the studio-backed story; otherwise the scanner falls back to the local
   premium system voice pipeline.

9. Profile is no longer just a utility list. It now has a real field-record
   dashboard powered by the server-computed `user_stats` RPC, plus one-stop
   links into Journal, Passport, Travel Preferences, Privacy & Data, Settings,
   and the live Lore+ membership surface.

10. Discovery Deck / Around You cards were compacted and lifted above the
    floating tab dock:
    - normal near-me cards are `244pt` tall instead of `268pt`
    - normal card teasers are one line to remove wasted vertical space
    - expanded deck clearance is explicit (`78pt`) so visit toggles and card
      footers do not sit under the tab bar
    - the map overlay remains an overlay, not a bottom safe-area inset, so the
      deck should not force MapKit to re-solve the camera and zoom out

11. Place dossier dismissal now clears the actual presentation state instead of
    relying on MapKit's retained selected pin id. This fixes the reported bug
    where closing a place card could leave the entire map dimmed/blurred.

12. The existing `saved_place` Supabase contract is now wired into the app as a
    real want-to-go loop:
    - every place card has a bookmark save/remove control
    - `SavedPlaceStore` hydrates owner-scoped saves, handles optimistic writes,
      rolls back failed writes, and resets on sign-out/session changes
    - Profile now has a `Saved places` field-kit entry and a saved-list view
      that opens the real database-backed place dossier
    - signed-out taps nudge sign-in instead of silently pretending to save

13. The generated "Build my walk" route now uses a fresh live location when it
    can honestly do so:
    - Tours observes an existing CoreLocation grant on appear and requests only
      when the traveler taps the routing action
    - stale or coarse fixes are rejected through the shared near-me provider
    - the route generator uses the traveler origin only when it is close enough
      to the selected city's story cluster, preserving normal remote city
      browsing
    - the first walking leg from the traveler to stop one now counts against
      both route distance and time budget

14. Place dossiers now render `dive.links.source_url` as a first-class source
    record row in `Sources & links`, alongside the existing official-site and
    Wikipedia links. The model accepts only HTTPS link values and dedupes repeated
    URLs before rendering, so internal provenance labels and malformed links do
    not become user-facing citation buttons.

## Files Changed

- `Sources/Lore/App/LoreApp.swift`
- `Sources/Lore/Features/Culture/CityFlavorViews.swift`
- `Sources/Lore/Features/Culture/CultureView.swift`
- `Sources/Lore/Features/Map/MapScreen.swift`
- `Sources/Lore/Features/Tours/OneHourTour.swift`
- `Sources/Lore/Features/Travel/NearMeShelf.swift`
- `Sources/Lore/Features/Travel/NearMeLocationProvider.swift`
- `Sources/Lore/Features/Travel/TravelMapOverlay.swift`
- `Sources/Lore/Features/Tours/TourDetailView.swift`
- `Sources/Lore/Features/Tours/ToursScreen.swift`
- `Sources/Lore/Features/Scanner/NarrationService.swift`
- `Sources/Lore/Features/Scanner/ScannerRanking.swift`
- `Sources/Lore/Features/Scanner/ScannerScreen.swift`
- `Sources/Lore/Features/Profile/ProfileJourneyModel.swift`
- `Sources/Lore/Features/Profile/ProfileScreen.swift`
- `Sources/Lore/Features/Profile/SavedPlacesView.swift`
- `Sources/Lore/Models/Place.swift`
- `Sources/Lore/Models/SavedPlace.swift`
- `Sources/Lore/Models/CitySection.swift`
- `Sources/Lore/Features/Travel/SavePlaceButton.swift`
- `Sources/Lore/Features/Travel/SavedPlaceStore.swift`
- `Sources/LoreTests/CitySectionTests.swift`
- `Sources/LoreTests/ExplorationJourneyTests.swift`
- `Sources/LoreTests/ScannerLogicTests.swift`
- `Sources/LoreTests/ProfileAccountTests.swift`
- `Sources/LoreTests/TravelReadsTests.swift`
- `Sources/LoreTests/LoreAPITests.swift`

## Validation

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/CitySectionTests
```

Result: `** TEST SUCCEEDED **` with 8 tests, including the richer
watch/hashtag/seasonal field-brief synthesis path.

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ExplorationJourneyTests
```

Result: `** TEST SUCCEEDED **` with 18 tests, including the compact near-me
card layout, expanded dock-clearance regression checks, and map blur dismissal
coverage.

Origin-aware generated-walk continuation validation:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ExplorationJourneyTests
```

Result: `** TEST SUCCEEDED **` with 23 tests, including the previous Discovery
Deck/map regressions plus fresh-origin route start, first-leg distance, and
remote-origin fallback coverage.

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ScannerLogicTests
```

Result: `** TEST SUCCEEDED **` with 24 tests.

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ProfileAccountTests
```

Result: `** TEST SUCCEEDED **` with 13 tests.

Also passed:

```sh
git diff --check
```

Saved-place continuation validation:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/TravelReadsTests -only-testing:LoreTests/ExplorationJourneyTests -only-testing:LoreTests/ProfileAccountTests
```

Result: `** TEST SUCCEEDED **` with 42 focused tests, including the saved-place
PostgREST contract, optimistic save rollback, signed-out behavior, existing
Discovery Deck regressions, and Profile account tests.

Also passed after the saved-place patch:

```sh
git diff --check
```

Dossier citation-link continuation validation:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/LoreAPITests
```

Result: `** TEST SUCCEEDED **` with 5 tests, including decoding/rendering support
for HTTPS `dive.links.source_url` and rejection of non-HTTPS dossier source
links.

Also passed after the citation-link patch:

```sh
git diff --check
```

Post-backup investigation note:

- An attempted `AtlasCache` in-flight request coalescing change was intentionally
  not shipped. It reduced duplicate cold anonymous reads in theory, but the
  focused cancellation path around
  `LoreNetworkResilienceTests.testCancellationDoesNotReturnAStaleAtlasPayload`
  did not exit cleanly under the URLProtocol test harness, and later simulator
  runs reported service-hub instability after interruption. Reattempt this only
  with a cancellation-first design and this regression test passing cleanly.

## Related Backend / Content Repo State

- Repo: `/Users/dron/Projects/lore`
- Branch: `main`
- Current synced feature head before the latest backend audit clarification:
  `e2fc77cf8fb6bce9516bb3a8ef502e753abe0528` (`Refresh thin city depth wave gate`)
- Backend/content repo handoff doc added separately:
  `docs/34-CONTENT-RICHNESS-AUDIT-2026-08-09.md`
- Repeatable public audit command:
  `node scripts/content-wave/audit-public-surface.mjs`
- Detailed takeover audit command:
  `node scripts/content-wave/audit-public-surface.mjs --city-details`

Recent content work already on `lore/main` includes:

- Wikipedia place ingest
- OSM geographic-feature ingest
- content pipeline docs under `scripts/content-ingest/README.md`

Live read-only public Supabase check on 2026-08-09 against project `uiuwzymvyrgfyiugqlkp`:

- 141 live cities
- 6,078 visible `place_explore` rows
- 6,078 visible `dive` rows
- 4,982 visible `city_section` rows
- 1,974 rich city-section rows
- 113 visible `dive.audio_path` rows
- all 141 live cities have every current rich city-section kind
- 4,593 dives have an external link; the v3 backend audit shows 4,592 dives
  (75.55%) with app-visible citation/read-more links
- 44 dives expose an external HTTPS `source` field, so strict source-field
  provenance cleanup remains separate from user-visible link coverage

Known content gaps still needing follow-up:

- Six cities are still below the 30-place public-content bar: Stone Town (21),
  Nairobi (29), Nashville (29), Santiago (29), Seoul (29), and Wellington (29).
- Premium/studio audio is partially live in app-visible data: the native app
  reads `dive.audio_path`, and the public surface currently has 113 rows with a
  path across only 3 cities. Most dives still fall back to on-device narration
  until audio coverage expands.
- The richer content kinds are visible publicly across every live city, but the
  current watch/hashtag rows are broad city-level context, not place-linked
  density. The next content pass should prioritize the six-city place floor and
  a small studio-audio sampler before another generic rich-section wave.

## Release State Caveat

Historical docs say build 27 was submitted to Apple App Review on 2026-08-03 and was waiting for review at that time. That is not the same as a current live App Store Connect verification. Before claiming TestFlight/App Store completion, verify current App Store Connect status and selected build directly.

## Tooling Caveat

Local `gh auth status` reported an invalid GitHub CLI token on August 9, 2026.
Use the connected GitHub app or re-authenticate `gh` before depending on GitHub
CLI PR/check commands.

## Recommended Next Steps

1. Review and merge this branch after CI.
2. Run a broader simulator build/test pass before TestFlight.
3. Verify the saved-place loop on a signed-in physical device: save from a place
   card, see it in Profile -> Saved places, reopen the dossier, remove it, sign
   out, and confirm the list clears.
4. Verify the Discovery Deck/Around Me dock clipping fix on a real device with
   the latest build, specifically that the visit toggle clears the floating tab
   dock when expanded.
5. Verify App Store Connect status and whether the latest code has actually reached TestFlight.
6. Continue content depth waves, prioritizing thin cities and the richer section kinds that now power the Meet City field brief.
7. Use the backend `low-place-floor-001` and `low-place-floor-002` candidate
   waves before claiming that the empty-city feeling is fixed. The second wave
   adds candidate supply for Nairobi and Wellington, but neither wave changes
   public counts until rows are reviewed and promoted through the private
   `lore_ops` lane.
