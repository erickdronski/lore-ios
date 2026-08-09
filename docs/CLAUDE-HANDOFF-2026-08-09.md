# Claude Handoff - Lore iOS - 2026-08-09

## Scope

Lore only. Do not mix Nalee, Tapt, Scout, or other portfolio projects into this takeover.

## Branch

- Repo: `/Users/dron/Projects/lore-ios`
- Branch: `codex/lore-next-level-20260809`
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

## Files Changed

- `Sources/Lore/App/LoreApp.swift`
- `Sources/Lore/Features/Culture/CityFlavorViews.swift`
- `Sources/Lore/Features/Culture/CultureView.swift`
- `Sources/Lore/Features/Map/MapScreen.swift`
- `Sources/Lore/Features/Travel/NearMeShelf.swift`
- `Sources/Lore/Features/Travel/TravelMapOverlay.swift`
- `Sources/Lore/Features/Tours/TourDetailView.swift`
- `Sources/Lore/Features/Tours/ToursScreen.swift`
- `Sources/Lore/Features/Scanner/NarrationService.swift`
- `Sources/Lore/Features/Scanner/ScannerRanking.swift`
- `Sources/Lore/Features/Scanner/ScannerScreen.swift`
- `Sources/Lore/Features/Profile/ProfileJourneyModel.swift`
- `Sources/Lore/Features/Profile/ProfileScreen.swift`
- `Sources/Lore/Models/Place.swift`
- `Sources/Lore/Models/CitySection.swift`
- `Sources/LoreTests/CitySectionTests.swift`
- `Sources/LoreTests/ExplorationJourneyTests.swift`
- `Sources/LoreTests/ScannerLogicTests.swift`
- `Sources/LoreTests/ProfileAccountTests.swift`

## Validation

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/CitySectionTests
```

Result: `** TEST SUCCEEDED **`

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ExplorationJourneyTests
```

Result: `** TEST SUCCEEDED **` with 16 tests, including the compact near-me
card layout and expanded dock-clearance regression checks.

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

## Related Backend / Content Repo State

- Repo: `/Users/dron/Projects/lore`
- Branch: `main`
- Current synced head: `fed2a34` (`Add OSM geographic-feature ingest engine (+838 real places; app now 5,486 places / 38.6 avg)`)
- Backend/content repo handoff doc added separately:
  `docs/34-CONTENT-RICHNESS-AUDIT-2026-08-09.md`

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
- 0 visible `dive.audio_url` rows

Known content gaps still needing follow-up:

- Six cities are still below the 30-place public-content bar: Stone Town (21),
  Nairobi (29), Nashville (29), Santiago (29), Seoul (29), and Wellington (29).
- Premium/studio audio is not live in the app-visible data yet because
  `dive.audio_url` is still empty.
- The richer content kinds are visible publicly across every live city, but the
  next content pass should keep proving app-visible promotion rather than only
  candidate/import state.

## Release State Caveat

Historical docs say build 27 was submitted to Apple App Review on 2026-08-03 and was waiting for review at that time. That is not the same as a current live App Store Connect verification. Before claiming TestFlight/App Store completion, verify current App Store Connect status and selected build directly.

## Recommended Next Steps

1. Review and merge this branch after CI.
2. Run a broader simulator build/test pass before TestFlight.
3. Verify the Discovery Deck/Around Me dock clipping fix on a real device with
   the latest build, specifically that the visit toggle clears the floating tab
   dock when expanded.
4. Verify App Store Connect status and whether the latest code has actually reached TestFlight.
5. Continue content depth waves, prioritizing thin cities and the richer section kinds that now power the Meet City field brief.
