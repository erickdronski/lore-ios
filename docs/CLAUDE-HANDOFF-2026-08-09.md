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

## Files Changed

- `Sources/Lore/App/LoreApp.swift`
- `Sources/Lore/Features/Culture/CityFlavorViews.swift`
- `Sources/Lore/Features/Culture/CultureView.swift`
- `Sources/Lore/Features/Tours/TourDetailView.swift`
- `Sources/Lore/Features/Tours/ToursScreen.swift`
- `Sources/Lore/Features/Scanner/NarrationService.swift`
- `Sources/Lore/Features/Scanner/ScannerRanking.swift`
- `Sources/Lore/Features/Scanner/ScannerScreen.swift`
- `Sources/Lore/Models/Place.swift`
- `Sources/Lore/Models/CitySection.swift`
- `Sources/LoreTests/CitySectionTests.swift`
- `Sources/LoreTests/ExplorationJourneyTests.swift`
- `Sources/LoreTests/ScannerLogicTests.swift`

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

Result: `** TEST SUCCEEDED **` with 15 tests.

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/ScannerLogicTests
```

Result: `** TEST SUCCEEDED **` with 24 tests.

Also passed:

```sh
git diff --check
```

## Related Backend / Content Repo State

- Repo: `/Users/dron/Projects/lore`
- Branch: `main`
- Current synced head: `fed2a34` (`Add OSM geographic-feature ingest engine (+838 real places; app now 5,486 places / 38.6 avg)`)
- No backend/content repo changes were made in this branch.

Recent content work already on `lore/main` includes:

- Wikipedia place ingest
- OSM geographic-feature ingest
- content pipeline docs under `scripts/content-ingest/README.md`

Live read-only Supabase check on 2026-08-09 against project `uiuwzymvyrgfyiugqlkp`:

- 141 live cities
- 6,078 visible `place_explore` rows
- 6,259 `dive` rows
- 5,297 `city_section` rows
- 7,261 raw `fact` rows visible to the connected service role check

Known content gaps still needing follow-up:

- Stone Town is still thin in visible place count.
- Nairobi, Nashville, Santiago, Seoul, and Wellington also showed only 29 visible places.
- San Antonio has place rows but needs the city-row/orphan wiring checked.
- Some accepted content waves are not proven live/promoted yet.
- Public `fact` rows are still not visibly powering the app in current read-only checks.

## Release State Caveat

Historical docs say build 27 was submitted to Apple App Review on 2026-08-03 and was waiting for review at that time. That is not the same as a current live App Store Connect verification. Before claiming TestFlight/App Store completion, verify current App Store Connect status and selected build directly.

## Recommended Next Steps

1. Review and merge this branch after CI.
2. Run a broader simulator build/test pass before TestFlight.
3. Verify the Discovery Deck/Around Me dock clipping fix on a real device with the latest build.
4. Verify App Store Connect status and whether the latest code has actually reached TestFlight.
5. Continue content depth waves, prioritizing thin cities and the richer section kinds that now power the Meet City field brief.
