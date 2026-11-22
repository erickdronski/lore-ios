# Changelog

App Store releases are listed separately from work that has reached TestFlight. Dates below describe the product milestone, not the date a GitHub
release entry was published.

## [1.2.1] — 2026-11-21 · App Store

Version **1.2.1 (build 50)** shipped on the
[App Store](https://apps.apple.com/us/app/lore-ar-city-history-guide/id6788171860)
on November 21, 2026 from source
[`1ea19ad`](https://github.com/erickdronski/lore-ios/commit/1ea19ad3068ae0dde3c102b4226818f2af49896f).
The [validated upload workflow](https://github.com/erickdronski/lore-ios/actions/runs/44860326507)
built and uploaded that exact commit as build 50, and the
[submission run](https://github.com/erickdronski/lore-ios/actions/runs/44873620798)
recorded build 50 attached and `VALID` for review. An earlier TestFlight build of
the same version, **1.2.1 (build 49)**, was uploaded from
[`9554c5c`](https://github.com/erickdronski/lore-ios/commit/9554c5c297d48f5c56e0a0ee50c489ff13e6ce81)
on October 20, 2026 by
[this run](https://github.com/erickdronski/lore-ios/actions/runs/39467341097).

### Added

- A free Starter Guide on the device for when sign-in or city services are
  unavailable: 16 sourced landmarks in five cities, searchable by city or place,
  with local bookmarks, directions and source links. Existing customers keep
  Apple restore and subscription management; new purchases need online services.

### Fixed

- Bound private journal photo loading and serialized uploads, retries, note edits,
  and deletion to prevent stale responses from restoring removed content.
- Isolated profile and photo responses when accounts change.
- Corrected deep links, Vision wording, and OAuth PKCE handling.

### Maintenance

- Prepared the 1.2.1 TestFlight version and journal-focused release notes.
- Updated release tooling and dependency pins, including the patched Fastlane
  bundle, and stabilized the account-deletion deadline test.
- Published the build 50 Starter Guide screenshots for iPhone and iPad from
  [`969ef22`](https://github.com/erickdronski/lore-ios/commit/969ef226e8ed9124b96e83c50d9862f8d5685541),
  without changing the app source.

## [1.2] — 2026-09-05 · App Store

Version **1.2 (build 48)** shipped on the
[App Store](https://apps.apple.com/us/app/lore-ar-city-history-guide/id6788171860)
from source
[`261d633`](https://github.com/erickdronski/lore-ios/commit/261d633d277a9940b849b108df0f10776e657f76).
The GitHub release entry was added retrospectively on November 20, 2026 to
document that existing release; it does not identify current `main` as shipped.

### Changed

- Clarified transport requirements and minimum-distance estimates for tours.
- Refreshed cached public content when a reviewed content version changes.
- Improved purchase ownership, restoration, and account handling.
- Improved source links and narration, retaining device voice when studio
  recordings are unavailable. Coverage and recordings vary by destination.

### Release evidence

- [Validated, signed build and upload](https://github.com/erickdronski/lore-ios/actions/runs/33984852047):
  source `261d633`, version 1.2, build 48.
- [App Store review submission](https://github.com/erickdronski/lore-ios/actions/runs/33990366067)
  and [post-submission verification](https://github.com/erickdronski/lore-ios/actions/runs/33990408311):
  the same explicit source, version, and build.
- [Screenshot provenance](fastlane/promo_screenshots/README.md):
  native captures from the same app source, committed separately with reviewed
  metadata and release tooling.

## 1.1 — 2026-08-16 · App Store

- Saved onboarding interests and persona to the account.
- Fixed display-name and profile saving, and expanded deep-dive presentation.
- Recorded purchases on the account so membership follows the user across devices.
- Removed retracted places and corrected city facts, sources, and permission copy.

The date and user-facing changes are recorded in the
[App Store version history](https://apps.apple.com/us/app/lore-ar-city-history-guide/id6788171860).

## 1.0 — 2026-07-25 · App Store

- Initial public App Store release, as recorded in the
  [App Store version history](https://apps.apple.com/us/app/lore-ar-city-history-guide/id6788171860).

## [1.0.0-beta.1] — 2026-07-23 · Engineering baseline

### Added

- Initial public engineering baseline for the native iOS application.
- Automated unit-test and unsigned release-build validation.
- Explicit, environment-gated TestFlight and App Store operations.

This original prerelease is retained. Its GitHub release was published on
July 24, 2026; it is an engineering milestone, separate from the July 25
App Store launch.

[Unreleased]: https://github.com/erickdronski/lore-ios/compare/v1.2...HEAD
[1.2]: https://github.com/erickdronski/lore-ios/releases/tag/v1.2
[1.0.0-beta.1]: https://github.com/erickdronski/lore-ios/releases/tag/v1.0.0-beta.1
