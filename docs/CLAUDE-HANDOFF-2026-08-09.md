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

## Files Changed

- `Sources/Lore/App/LoreApp.swift`
- `Sources/Lore/Features/Culture/CityFlavorViews.swift`
- `Sources/Lore/Features/Culture/CultureView.swift`
- `Sources/Lore/Features/Tours/TourDetailView.swift`
- `Sources/Lore/Features/Tours/ToursScreen.swift`
- `Sources/Lore/Models/CitySection.swift`
- `Sources/LoreTests/CitySectionTests.swift`

## Validation

Passed:

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LoreTests/CitySectionTests
```

Result: `** TEST SUCCEEDED **`

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

Known content gaps still needing follow-up:

- Stone Town is still thin in visible place count.
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
