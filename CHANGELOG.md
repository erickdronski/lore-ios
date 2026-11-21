# Changelog

App Store releases are listed separately from work that has reached internal
TestFlight. Dates below describe the product milestone, not the date a GitHub
release entry was published.

## [Unreleased] — 1.2.1 maintenance

The public App Store version remains **1.2**. Internal TestFlight version
**1.2.1 (build 49)** was uploaded from
[`9554c5c`](https://github.com/erickdronski/lore-ios/commit/9554c5c297d48f5c56e0a0ee50c489ff13e6ce81)
on October 20, 2026 by the
[validated upload workflow](https://github.com/erickdronski/lore-ios/actions/runs/39467341097).
A [read-only check on October 20](https://github.com/erickdronski/lore-ios/actions/runs/39470459418)
observed that exact TestFlight build as `VALID`. This historical verification
does not establish current tester availability. No 1.2.1 App Store release is
recorded here.

### Fixed

- Bound private journal photo loading and serialized uploads, retries, note edits,
  and deletion to prevent stale responses from restoring removed content.
- Isolated profile and photo responses when accounts change.
- Corrected deep links, Vision wording, and OAuth PKCE handling.

### Maintenance

- Prepared the 1.2.1 TestFlight version and journal-focused release notes.
- Updated release tooling and dependency pins, including the patched Fastlane
  bundle, and stabilized the account-deletion deadline test.

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
