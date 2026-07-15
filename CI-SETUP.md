# Lore iOS CI and TestFlight

Lore is native SwiftUI because the scanner uses Apple camera, Vision, ARKit,
and StoreKit APIs. GitHub Actions builds it on macOS with XcodeGen and Fastlane;
Expo/EAS is not part of this release lane.

## What publishes

- A push to `main` or a pull request runs the unit-test gate only.
- TestFlight upload requires an explicit **Run workflow** action with
  `upload_to_testflight` enabled.
- The upload job tests the exact checkout before it archives, signs, and uploads.
- The workflow exits after App Store Connect accepts the binary; Apple finishes
  TestFlight processing asynchronously.

## Required repositories

- `erickdronski/lore-ios`: application source and workflow.
- `erickdronski/lore-certs`: private Fastlane Match storage for the encrypted
  Apple Distribution certificate and App Store provisioning profiles.

Match handles both bundle identifiers:

- `com.erickdronski.lore`
- `com.erickdronski.lore.LoreWidget`

## Required GitHub secrets

Configure these in `lore-ios` under **Settings → Secrets and variables →
Actions**. Never commit their values.

| Secret | Purpose |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID |
| `ASC_KEY_CONTENT` | Base64-encoded `.p8` API private key |
| `MATCH_PASSWORD` | Encrypts/decrypts the Match repository |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 `github-user:token` credential with read/write access to the private cert repository |

The App Store Connect key needs enough access to read builds and manage the app
record. The GitHub token needs **Contents: read and write** on `lore-certs`
because the first Match run or a certificate renewal can update that repository.

Encode the `.p8` key without adding it to this repository:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Encode the Match Git credential:

```sh
printf '%s' 'github-user:github-token' | base64 | pbcopy
```

## Apple prerequisites

1. App Store Connect contains the Lore app record for bundle
   `com.erickdronski.lore` and SKU `lore-ios`.
2. The Apple Developer team is `J9DMDH4S58`.
3. Both app identifiers above exist in the Developer portal.
4. Paid Apps agreements, tax, and banking are active before testing purchases.
5. Lore+ products are attached to the app version before App Review.

## Run a build

1. Open GitHub Actions for `erickdronski/lore-ios`.
2. Select **iOS CI and TestFlight**.
3. Choose **Run workflow** on the intended branch.
4. Enable `upload_to_testflight`.
5. Confirm the unit-test, archive, and upload steps all pass.
6. In App Store Connect, wait for processing and verify the resulting build,
   export-compliance state, tester availability, and crash status.

The workflow pins Xcode 26.3, regenerates `Lore.xcodeproj`, installs the locked
Fastlane bundle, runs `fastlane tests`, then runs `fastlane beta`. Fastlane uses
one build number above the latest TestFlight build, installs Match signing
assets into a throwaway CI keychain, archives Release, and uploads the IPA.

## Troubleshooting

- **Match cannot clone:** verify `MATCH_GIT_BASIC_AUTHORIZATION` is base64 basic
  auth and its token can read the private `lore-certs` repository.
- **Match cannot decrypt:** verify `MATCH_PASSWORD` matches the existing cert
  repository encryption password.
- **No signing profile:** verify both app identifiers exist and the API key has
  sufficient Apple access; Match must create/fetch profiles for both targets.
- **Duplicate build number:** rerun the workflow. The lane queries the latest
  build for marketing version `1.0` and increments it.
- **Upload passed but build is absent:** allow Apple processing time, then inspect
  App Store Connect processing errors and the workflow build logs.
