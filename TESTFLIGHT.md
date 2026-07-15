# Lore TestFlight Release Runbook

**Audited:** July 14, 2026
**Bundle ID:** `com.erickdronski.lore`
**App Store Connect app ID:** `6788171860`

GitHub Actions is the authoritative native build, test, signing, archive, and
TestFlight lane. This machine has Command Line Tools rather than the full iOS
SDK; local Xcode is not required to publish Lore.

## Release contract

The workflow at `.github/workflows/ios-testflight.yml` always:

1. Checks out one exact commit.
2. Selects Xcode 26.3 and generates `Lore.xcodeproj` with XcodeGen.
3. Runs the Lore unit-test suite on an iPhone simulator.
4. Compiles the unsigned Release configuration.
5. Archives, signs, and uploads only when a manual dispatch sets
   `upload_to_testflight=true`.

An ordinary push to `main` cannot upload a build. The manual upload dispatch
repeats the same test and Release-compile gates before signing.

## Credentials

The GitHub repository must contain these Actions secrets:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_CONTENT`
- `MATCH_PASSWORD`
- `MATCH_GIT_BASIC_AUTHORIZATION`

Never print, copy into a workflow file, or commit their values. Fastlane Match
stores encrypted signing material in the private `erickdronski/lore-certs`
repository.

## Publish a tested commit

1. Confirm the intended Lore changes are committed and pushed to `main`.
2. Wait for the push-triggered `iOS CI and TestFlight` run to finish green.
3. Confirm the run's head SHA equals the intended commit.
4. Dispatch the same workflow on `main` with
   `upload_to_testflight=true`.
5. Wait for that run to pass. Fastlane reads the latest TestFlight build number,
   increments it, archives the Release build, and uploads it.
6. In App Store Connect, wait for processing to complete and confirm the build
   version, build number, SDK, export-compliance state, and commit evidence.
7. Install that build from TestFlight on a clean physical iPhone and run the
   release smoke test.

Useful non-interactive commands:

```bash
gh run list --workflow ios-testflight.yml --branch main --limit 5
gh run watch RUN_ID --exit-status
gh workflow run ios-testflight.yml --ref main -f upload_to_testflight=true
```

Do not dispatch from a local-only commit or assume a successful upload means
Apple has finished processing the build.

## Required TestFlight smoke test

- Clean launch, onboarding, map, city selection, place card, and deep dive
- Scanner permission denial, grant, restart, weak location, and known-place flow
- Optional Google identification disclosure, cancellation, success, auth expiry,
  and quota response
- Email registration, confirmation, sign-in, recovery, and sign-out
- Lore+ product loading, eligible/ineligible trial copy, purchase cancellation,
  pending purchase, completed purchase, and restore
- Visit, journal note/photo, badge progress, and account deletion
- Legal, support, sharing, and subscription-management links

Record device model, iOS version, build number, test account, city, and outcome.
Account deletion should use a disposable account.

## Screenshots are a separate release artifact

`fastlane screenshots_upload` intentionally cannot upload the existing
promotional set. The lane requires
`fastlane/promo_screenshots/SOURCE_SHA`, containing the full Git commit SHA from
which every screenshot was captured, and refuses to run unless it equals the
current checkout.

Regenerate the complete set from the exact release build, including a genuine
physical-device scanner capture. Audit every visible claim, flatten alpha, and
verify App Store Connect's current dimensions before creating `SOURCE_SHA`.
Never upload the old map/profile set.

## App Review is separate

A processed TestFlight build is not approval to submit version 1.0 for review.
Use `/Users/dron/Projects/lore/legal/APP-STORE-LISTING.md` and `HANDOFF.md` for
the current submission gates. Explicit approval is required before pressing
Submit for Review.
