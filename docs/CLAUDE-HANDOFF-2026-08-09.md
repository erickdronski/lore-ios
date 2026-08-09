# Claude Handoff - Lore iOS - 2026-08-09

## Scope

Lore only. Do not mix Nalee, Tapt, Scout, or other portfolio projects into this takeover.

## Branch

- Repo: `/Users/dron/Projects/lore-ios`
- Branch: `codex/lore-next-level-20260809`
- Current head: `d729cef21865737f5ee52c5dcc6f362689222731` (`Promote richer city field briefs`)
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

Result: `** TEST SUCCEEDED **` with 8 tests, including the richer
watch/hashtag/seasonal field-brief synthesis path.

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ExplorationJourneyTests
```

Result: `** TEST SUCCEEDED **` with 18 tests, including the compact near-me
card layout, expanded dock-clearance regression checks, and map blur dismissal
coverage.

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
- Current synced head: `014b5d11c2ccc47b7dc8a650b0ca0482ffabedf0` (`Expand public content surface audit`)
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
- 4,593 dives have an external link, but only 44 expose an external HTTPS
  `source` link

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
3. Verify the Discovery Deck/Around Me dock clipping fix on a real device with
   the latest build, specifically that the visit toggle clears the floating tab
   dock when expanded.
4. Verify App Store Connect status and whether the latest code has actually reached TestFlight.
5. Continue content depth waves, prioritizing thin cities and the richer section kinds that now power the Meet City field brief.
6. Use the backend `low-place-floor-001` canary recommendation before claiming
   that the empty-city feeling is fixed: +1 place each for Nashville, Seoul,
   Santiago, Nairobi, and Wellington, and +9 places for Stone Town, staged
   through the reviewed content lane rather than direct public writes.
