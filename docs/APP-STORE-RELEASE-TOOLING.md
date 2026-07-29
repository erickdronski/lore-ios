# App Store Release Tooling

Lore's App Store release lanes fail closed around `APP_REVIEW_HOLD`.

## Hold contract

The `app-store-production` environment must define `APP_REVIEW_HOLD` as exactly
`true` or `false`. A missing or malformed value blocks the action.

When the value is `true`, these release mutations stop before App Store Connect
authentication:

- screenshot upload
- App Review submission
- build swap and resubmission
- auto-release configuration

`hold_review` is the protective exception. It is permitted only while the hold
is `true`, and only cancels the exact version and build supplied to the lane.
Read-only `preflight` and internal TestFlight upload do not advance an App Store
release and are not blocked by the hold.

## Preflight truth

Preflight performs read-only API requests. It emits one structured line for
every check:

```text
PF|PASS|...
PF|FAIL|...
PF|WARN|...
```

All `FAIL` findings are collected so the log retains the complete inspection.
The lane exits nonzero after the final check when any failure exists. `WARN`
means the item is optional, informational, or cannot be verified reliably by
the pinned App Store Connect API client. In particular, IAP review assets,
agreements, tax and banking, privacy labels, and EU trader status remain manual
checks; preflight never reports them as verified.

## Screenshot provenance

Every screenshot upload, submission, or build-swap submission must receive an
explicit 40-character `RELEASE_SOURCE_SHA`. The value must exactly equal
`fastlane/promo_screenshots/SOURCE_SHA`, name a commit available in the full
checkout, and be an ancestor of the workflow checkout.

This intentionally rejects the current screenshot package when it predates the
binary being submitted. Regenerate every screenshot from the exact tested
release source, commit the package and its `SOURCE_SHA`, then invoke the release
workflow with that exact release commit. Read-only preflight does not require a
release SHA.

## Offline verification

Run the deterministic guard suite without Apple credentials or network access:

```sh
ruby fastlane/spec/lore_release_tooling_test.rb
```
