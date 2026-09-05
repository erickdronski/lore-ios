# Native regression verification

Generate the project with `xcodegen generate`. The `Lore` test action runs the
ordinary unit and network regression suite. `LoreStoreKitTests` runs six serial
StoreKit engine journeys separately using the bundled `StoreKit/Lore.storekit`.
Neither scheme requires real payments or a signed-in App Store account.

```sh
xcodebuild test -project Lore.xcodeproj -scheme Lore \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/lore-regression-build CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Lore.xcodeproj -scheme LoreStoreKitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/lore-regression-build -parallel-testing-enabled NO
```

The engine journeys use `StoreKitService.purchase`, `restore`, transaction
enumeration, and `Transaction.updates`. The signed-in purchase posts the engine's
JWS through the real `LoreAPI` request builder into a URLProtocol verifier stub.
They check guest access and transaction finishing, account-token isolation,
restore/new-service access, refund delivery during a server outage, unfinished
receipts after failed synchronization, and subscription expiration. The
verifier stub is an injected contract response; it does not replace Apple's
local transaction verification or claim to test the production Edge Function.

The hosted app's separate transaction listener is disabled only when the test
scheme supplies `LORE_UNIT_TESTS=1` in a Debug build. This prevents a second
listener from finishing a test receipt before the service under test handles
it. The tests themselves own the real service and listener. Release builds
have no such branch.

## StoreKit engine prerequisite

`SKTestSession` must successfully activate its local configuration. Setup sets
`disableDialogs` and reads it back before any purchase. If the engine refuses
the setting, setup throws `StoreKitJourneyTests.LocalEngineUnavailable`; it
does not silently continue into Sandbox or count a business assertion as passed.
Run this scheme on a functioning local StoreKit runtime in CI and before
release. Failure of this prerequisite is an uncompleted verification, not a
successful purchase test.

On 2026-09-05, Xcode 26.5 / simulator iOS 26.5 (23F77) returned
`SKInternalErrorDomain Code=3` for configuration and settings mutations from
`xcodebuild test`, both without signing and with simulator-only ad-hoc signing.
An IDE launch without rebuilding did not resolve the CLI failure. The first
attempt was interrupted when the runtime fell back to an Apple Sandbox sign-in
prompt; no authentication or payment was completed. Subsequent attempts failed
at setup before attempting purchase. All six engine journeys remain unverified
on that runtime. A separate IDE test launch could not select its simulator run
destination through Xcode scripting and was cancelled before tests began.

Apple documents the shared, serial test environment in
[SKTestSession](https://developer.apple.com/documentation/storekittest/sktestsession).
A firsthand report on the
[Apple Developer Forums](https://developer.apple.com/forums/tags/xctest/?sortBy=newest)
describes the matching iOS 26.5 command-line configuration failure. That report
provides context; the captured local failure is the evidence for this run.

## Public content cache epochs

A valid content contract namespaces public JSON, pinned JSON, packed media,
and pack manifests by contract version and review epoch, including when
`enforcement_enabled` is false. A new epoch makes previous bytes unreachable.
Known contracts survive endpoint outages and cannot revert to legacy URL-only
identity. The enforcement flag independently enables the declared offline age
limit. An absent contract before first adoption retains legacy compatibility.

Tests cover disabled-enforcement epoch changes, legacy purge, long-lived public
fallback in the same epoch, persisted contract recovery, and pack/media epoch
compatibility. Native membership tests separately cover finite expiration
serialization, the 72-hour server membership fallback, account switching,
cancellation, guest ownership, revoked server bindings, and versioned purchase
sync routing.
