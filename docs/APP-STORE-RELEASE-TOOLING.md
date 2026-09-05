# App Store Release Tooling

The release target is explicit. Version `1.2` and the minimum build number `48`
come from `project.yml`; the app and widget must agree. A release action requires
`expected_version:1.2` and the actual uploaded `expected_build`. It never chooses
an implicit latest build. Beta uploads use `max(project floor, latest TestFlight
build for this marketing version + 1)`, so a retry may produce build 49 or higher.
Use that actual build number for subsequent actions.

## Hold contract

The `app-store-production` environment must define `APP_REVIEW_HOLD` as exactly
`true` or `false`. Missing or malformed values fail closed. While it is `true`,
version preparation, build selection, screenshot upload, submission, build swap,
and auto-release configuration stop before App Store Connect authentication.
This tooling does not change the hold.

`hold_review` is the protective exception: it requires the hold to be `true` and
cancels only the supplied version and build. Read-only `preflight` and internal
TestFlight uploads do not advance an App Store release and remain available
while held. App Store Connect UI changes are outside this lane guard.

## Release sequence

1. Finish and test all app code, metadata, release notes and tooling. Commit that
   source as **M**, retaining its full 40-character SHA. Run the beta workflow
   from M; record the marketing version and actual uploaded build. Wait for Apple
   to report the build `VALID` and nonexpired.
2. Capture and review every screenshot from that same M source. Commit the
   reviewed screenshot package and `fastlane/promo_screenshots/SOURCE_SHA` in a
   child commit **A**. The file must contain M, not A. No app code changes belong
   in A; any new code requires a new M, build and screenshot package.
3. After the release owner clears the hold, run `prepare-version` from the
   branch/tag pointing to A. It creates only the exact project version, with
   `MANUAL` release mode, and sets en-US What's New from the committed
   `fastlane/release_notes/1.2.en-US.txt`. It refuses to rename a different
   editable version. Reruns reuse the exact existing manual, editable version.
4. Upload the reviewed screenshots, then run `select-build` with the actual
   expected build and `release_source_sha=M`. The lane accepts exactly one iOS
   build matching app ID, marketing version and build number, with `VALID`
   processing state, `expired=false` and no elapsed expiration date. It rereads
   the attached build to confirm Apple's saved selection.
5. Run `preflight` with the same expected tuple, and complete its remaining
   manual checks. Resolve all failures before continuing.
6. Run `submit` with the same tuple and M. It checks the attached build again
   immediately before submission and requires exactly the intended version item
   in the review submission. Run `auto-release` with the same tuple and M only
   when automatic release after approval is intended. Preparation starts manual;
   automatic release is a separate explicit action.

Examples below assume `RELEASE_REF` points to A, `RELEASE_SOURCE_SHA` is M, and
`EXPECTED_BUILD` is the actual processed build (initially 48). The GitHub
workflow uses the configured environment credentials and hold value.

```sh
gh workflow run app-store-preflight.yml --ref "$RELEASE_REF" \
  -f action=prepare-version -f expected_version=1.2 -f expected_build="$EXPECTED_BUILD"
gh workflow run app-store-preflight.yml --ref "$RELEASE_REF" \
  -f action=select-build -f expected_version=1.2 -f expected_build="$EXPECTED_BUILD" \
  -f release_source_sha="$RELEASE_SOURCE_SHA"
gh workflow run app-store-preflight.yml --ref "$RELEASE_REF" \
  -f action=preflight -f expected_version=1.2 -f expected_build="$EXPECTED_BUILD"
gh workflow run app-store-preflight.yml --ref "$RELEASE_REF" \
  -f action=submit -f expected_version=1.2 -f expected_build="$EXPECTED_BUILD" \
  -f release_source_sha="$RELEASE_SOURCE_SHA"
gh workflow run app-store-preflight.yml --ref "$RELEASE_REF" \
  -f action=auto-release -f expected_version=1.2 -f expected_build="$EXPECTED_BUILD" \
  -f release_source_sha="$RELEASE_SOURCE_SHA"
```

Direct lane equivalents, with credentials and the hold already configured:

```sh
bundle exec fastlane preflight expected_version:1.2 expected_build:48
bundle exec fastlane prepare_version expected_version:1.2
bundle exec fastlane select_release_build expected_version:1.2 expected_build:48
bundle exec fastlane submit_for_review expected_version:1.2 expected_build:48
bundle exec fastlane set_auto_release expected_version:1.2 expected_build:48
```

The last three also require the `RELEASE_SOURCE_SHA` environment variable.
`swap-latest` is retained as a workflow compatibility name; it swaps only the
explicit `expected_version`/`expected_build`, cancels a review only if bound to
that version, waits for Apple to finish cancellation, and then verifies the
exact build and version item before resubmitting.

## Preflight truth

Preflight performs only GET requests, emits `PF|PASS|...`, `PF|FAIL|...`,
`PF|WARN|...` and `PF|INFO|...`, and collects every failure before exiting
nonzero. It checks the exact expected attached build when a target is supplied,
listing text, screenshot sets, age rating, privacy-policy URL, review state and
actual product catalog records. No editable version, no localizations, or no
screenshot sets are failures. Without an editable version, it may show the live
version as diagnostic context; that does not make the preflight pass.

The required `lore_plus_monthly`, `lore_plus_annual` and `lore_plus_lifetime`
products must each appear exactly once and have state `APPROVED`. The preflight
reads subscription groups, all subscriptions in each group, and one-time IAPs,
following pagination. An API access or schema failure is a blocking failure,
not assumed approval. It reads no prices and changes no products.

Product approval alone does not establish storefront availability or settlement.
Review screenshots, subscription availability/offers, Paid Applications
Agreement, tax and banking, privacy labels and EU trader status remain explicit
manual checks. Existing Resolution Center messages are surfaced for review; a
successful offline guard suite is not evidence that Apple's live state passes.

## Screenshot provenance

Screenshot upload, build selection, submission, swap and auto-release require
an explicit 40-character `RELEASE_SOURCE_SHA`. It must equal the screenshot
package's `SOURCE_SHA`, resolve in the full-history checkout, and be an ancestor
of that checkout. This validates Git/package provenance; the release owner must
also retain the build job and screenshot evidence proving both came from M.
Read-only preflight and version preparation do not require screenshot assets.

## Pinned API behavior and offline verification

Fastlane remains pinned at 2.237.0. Its
[`App.ensure_version!`](https://github.com/fastlane/fastlane/blob/2.237.0/spaceship/lib/spaceship/connect_api/models/app.rb)
can rename the editable version, so preparation uses the supported
[`post_app_store_version`](https://github.com/fastlane/fastlane/blob/2.237.0/spaceship/lib/spaceship/connect_api/tunes/tunes.rb)
API with explicit `versionString`, `IOS` platform and `MANUAL` release type.
Build verification uses the pinned
[`Build` model](https://github.com/fastlane/fastlane/blob/2.237.0/spaceship/lib/spaceship/connect_api/models/build.rb)
with app and prerelease-version associations loaded. Product reads use Apple's
[subscription groups](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-subscriptiongroups),
[subscriptions](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptiongroups-_id_-subscriptions)
and [in-app purchases](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-inapppurchasesv2)
endpoints through the pinned client's raw GET response, without relying on
unsupported product models.

Run deterministic guard tests without Apple credentials or network access:

```sh
ruby fastlane/spec/lore_release_tooling_test.rb
ruby -c fastlane/Fastfile
```

The suite checks holds before authentication, exact version/build/app/platform,
processing and expiry, build floors, version preparation without renaming,
review-item binding, screenshot provenance, pagination, and read-only product
lookup. `Release Tooling Tests` runs it on relevant pull requests and main pushes.
