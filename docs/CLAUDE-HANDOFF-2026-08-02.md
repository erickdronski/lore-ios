# Lore iOS Claude handoff - 2026-08-02

This handoff is for the Lore iOS repository only.

## GitHub state

- Repository: `erickdronski/lore-ios`
- Default branch at time of handoff: `origin/main` = `1cba3af7ef46dac9a34aebda6aa88968a7ad2c79`
- Backed-up work branch: `codex/local-expert-content-wave-20260802`
- Latest backed-up commit before this handoff note: `5f318f1e219aebb7522a43e977c47cd1ba51fe7d`
- Pull request: https://github.com/erickdronski/lore-ios/pull/39
- PR status before this handoff note: mergeable, CI green, not merged
- TestFlight status: not uploaded from this branch. PR validation skips the signed TestFlight job.

Do not claim TestFlight or App Store delivery until a commit is on `main` and the manual TestFlight workflow has uploaded and processed in App Store Connect.

## What changed on the backed-up branch

- Discovery deck / Around Me polish:
  - `TravelMapControlsLayout.expandedBottomDockClearance = 136`
  - `TravelMapControlsLayout.collapsedBottomClearance = 18`
  - `NearMeShelf` regular cards are compact, reserve CTA space, and shorten proximity labels.
- Place sheet polish:
  - Header/body content is constrained so long text does not bleed horizontally.
  - Story cards expose the deeper route instead of leaving truncated text as a dead end.
  - Dismissal clears the transient map presentation state to avoid the blurred-map regression.
- Tours polish:
  - Top spacing tightened.
  - Decorative route art is clipped inside the tile.
- Profile redesign:
  - The profile tab has been rebuilt into a richer command-center surface with membership, progress, settings, about, and account actions.
- Content wave:
  - Added source-backed local-expert addon artifacts for the 139 cities that were missing rich local content.
  - Committed final artifacts live under `supabase/content/wave-2026-08/` with the `.agent-merged` suffix and regional `.agent.json` source files.
  - Added compiler/test support under `tools/content-wave/`.

## Supabase production evidence

Production project: `lore`, ref `uiuwzymvyrgfyiugqlkp`.

Readback from the completed production content wave:

- Live cities: `141`
- Wave cities: `141`
- Wave rows: `1,974`
- v3 expansion rows: `1,946`
- Stale generated rows from earlier passes: `0`
- Kind failures: `0`
- Final content audit: `PASS`, `141/141` cities passing
- Final source check for the committed agent-reviewed merged artifact: `911` sources, `899` reachable, `12` gated, `0` dead, `0` error

All 141 live cities have the required local-expert kinds: `watch`, `hashtag`, `local_legend`, `first_timer_mistake`, `neighborhood_decode`, `photo_prompt`, and `seasonal`.

## Content artifact warning

The publication artifact is:

- `supabase/content/wave-2026-08/local-expert-addons-global-139.agent-merged.json`
- `supabase/content/wave-2026-08/local-expert-addons-global-139.agent-merged.sql`
- `supabase/content/wave-2026-08/local-expert-addons-global-139.agent-merged.manifest.json`

The older generated files without the `.agent-merged` suffix are backed up only for provenance and recovery. They were rougher draft outputs and should not be treated as the final publication source. The production note at `supabase/content/wave-2026-08/local-expert-addons-production-2026-08-02.md` documents that the first compact pass was replaced after sampling.

## Verification already performed

- Focused simulator tests: `LoreTests/ExplorationJourneyTests`, 14 tests passed.
- Full simulator unit suite: 158 XCTest tests plus 6 Swift Testing tests passed.
- Unsigned Release simulator build passed with `CODE_SIGNING_ALLOWED=NO`.
- GitHub Actions PR validation run `30762892495` completed successfully.

## Next release steps

1. Review PR #39 and the current handoff commit.
2. Merge or fast-forward this branch to `main`.
3. Wait for `ios-testflight.yml` source validation on `main` to pass.
4. Manually dispatch `ios-testflight.yml` on `main` with `upload_to_testflight=true`.
5. Confirm the uploaded build number and processing state in App Store Connect.
6. Only then mark TestFlight delivered or select the build for App Review.

## Follow-up audit items

- Real-device verification is still required for camera/scanner behavior, GPS movement, haptics feel, audio interruption, Live Activities, and StoreKit purchase/restore.
- Keep the scanner claims conservative: database-backed nearby recognition is the release path; broad universal landmark recognition remains gated infrastructure.
- Continue editorial sampling of the 2026-08 local-expert content wave before promoting any `reference_only` content to a stronger provenance state.
